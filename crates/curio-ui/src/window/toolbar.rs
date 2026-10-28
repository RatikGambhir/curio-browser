//! The toolbar (horizontal layout, or vertical layout with the sidebar
//! hidden) and the horizontal tab strip.

use curio_core::{GroupId, TabId};
use curio_tabs::{GroupPlacement, Item, Placement, Section};
use gpui_kit::AppContext as _;
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants as _};
use gpui_kit::component::menu::{ContextMenuExt as _, DropdownMenu as _, PopupMenuItem};
use gpui_kit::component::tooltip::Tooltip;
use gpui_kit::component::{Icon, Sizable as _, h_flex};
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{
    AnyElement, ClickEvent, Context, FontWeight, InteractiveElement as _, IntoElement, MouseButton,
    ParentElement as _, SharedString, StatefulInteractiveElement as _, Styled as _, Window, div,
    px,
};

use super::sidebar::space_menu;
use super::{BrowserWindow, DraggedGroup, DraggedTab};
use crate::actions;
use crate::components::{chrome_button, favicon};
use crate::theme::{CurioTheme, metrics};

impl BrowserWindow {
    pub(crate) fn render_toolbar(
        &mut self,
        horizontal: bool,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        let state = self.active_tab_entity().map(|t| t.read(cx).state().clone());
        let can_back = state.as_ref().is_some_and(|s| s.history.can_go_back);
        let can_forward = state.as_ref().is_some_and(|s| s.history.can_go_forward);
        let loading = state.as_ref().is_some_and(|s| s.loading);
        let space = self.workspace.active_space();
        let space_label = SharedString::from(format!("{}  {}", space.icon, space.name));
        let spaces: Vec<(curio_core::SpaceId, String)> = self
            .workspace
            .spaces()
            .iter()
            .map(|s| (s.id, format!("{}  {}", s.icon, s.name)))
            .collect();
        let active_space = space.id;
        let this = cx.entity().downgrade();
        h_flex()
            .id("toolbar")
            .h(metrics::TOOLBAR_HEIGHT)
            .flex_shrink_0()
            .px(px(10.))
            .gap(px(4.))
            .on_mouse_down(MouseButton::Left, |event, window, _| {
                if event.click_count >= 2 {
                    window.titlebar_double_click();
                } else {
                    window.start_window_move();
                }
            })
            .child(
                div()
                    .w(metrics::TRAFFIC_LIGHTS_WIDTH - px(10.))
                    .flex_shrink_0(),
            )
            .when(!horizontal, |el| {
                el.child(
                    chrome_button("toolbar-sidebar", IconName::PanelLeft, cx)
                        .tooltip(|w, cx| {
                            Tooltip::new("Show Sidebar")
                                .action(&actions::ToggleSidebar, None)
                                .build(w, cx)
                        })
                        .on_click(|_, window, cx| {
                            window.dispatch_action(Box::new(actions::ToggleSidebar), cx)
                        }),
                )
            })
            .when(horizontal, |el| {
                el.child(
                    Button::new("space-picker")
                        .ghost()
                        .small()
                        .label(space_label)
                        .icon(IconName::ChevronDown)
                        .dropdown_menu(move |mut menu, _, _| {
                            for (id, label) in &spaces {
                                let id = *id;
                                let this = this.clone();
                                menu = menu.item(
                                    PopupMenuItem::new(SharedString::from(label.clone()))
                                        .checked(id == active_space)
                                        .on_click(move |_, window, cx| {
                                            let _ = this.update(cx, |this, cx| {
                                                this.switch_space(id, window, cx)
                                            });
                                        }),
                                );
                            }
                            menu.separator().item(
                                PopupMenuItem::new("New Space…")
                                    .icon(IconName::Plus)
                                    .on_click(|_, window, cx| {
                                        window.dispatch_action(Box::new(actions::NewSpace), cx)
                                    }),
                            )
                        }),
                )
            })
            .child(
                chrome_button("tb-back", IconName::ArrowLeft, cx)
                    .when(!can_back, |el| el.opacity(0.35))
                    .tooltip(|w, cx| {
                        Tooltip::new("Back")
                            .action(&actions::GoBack, None)
                            .build(w, cx)
                    })
                    .on_click(|_, window, cx| {
                        window.dispatch_action(Box::new(actions::GoBack), cx)
                    }),
            )
            .child(
                chrome_button("tb-forward", IconName::ArrowRight, cx)
                    .when(!can_forward, |el| el.opacity(0.35))
                    .tooltip(|w, cx| {
                        Tooltip::new("Forward")
                            .action(&actions::GoForward, None)
                            .build(w, cx)
                    })
                    .on_click(|_, window, cx| {
                        window.dispatch_action(Box::new(actions::GoForward), cx)
                    }),
            )
            .child(if loading {
                chrome_button("tb-stop", IconName::X, cx).on_click(|_, window, cx| {
                    window.dispatch_action(Box::new(actions::StopLoading), cx)
                })
            } else {
                chrome_button("tb-reload", IconName::RotateCw, cx)
                    .tooltip(|w, cx| {
                        Tooltip::new("Reload")
                            .action(&actions::Reload, None)
                            .build(w, cx)
                    })
                    .on_click(|_, window, cx| window.dispatch_action(Box::new(actions::Reload), cx))
            })
            .child(
                div()
                    .flex_1()
                    .max_w(px(720.))
                    .mx_auto()
                    .child(self.render_url_pill(cx)),
            )
            .child(
                chrome_button("tb-ai", IconName::Sparkles, cx)
                    .when(self.ai_open, |el| {
                        el.text_color(theme.accent_text).bg(theme.row_hover)
                    })
                    .tooltip(|w, cx| {
                        Tooltip::new("Curio Assistant")
                            .action(&actions::ToggleAiPanel, None)
                            .build(w, cx)
                    })
                    .on_click(|_, window, cx| {
                        window.dispatch_action(Box::new(actions::ToggleAiPanel), cx)
                    }),
            )
            .child(
                chrome_button("tb-downloads", IconName::ArrowDown, cx)
                    .tooltip(|w, cx| Tooltip::new("Downloads").build(w, cx))
                    .on_click(|_, window, cx| {
                        window.dispatch_action(Box::new(actions::ShowDownloads), cx)
                    }),
            )
            .child(
                chrome_button("tb-settings", IconName::Settings, cx)
                    .tooltip(|w, cx| Tooltip::new("Settings").build(w, cx))
                    .on_click(|_, window, cx| {
                        window.dispatch_action(Box::new(actions::OpenSettings), cx)
                    }),
            )
            .into_any_element()
    }

    pub(crate) fn render_tab_strip(
        &mut self,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        let menu = self.menu_context(cx);
        let space = self.workspace.active_space();
        let active = space.active_tab;
        let mut children: Vec<AnyElement> = Vec::new();

        // Favorites and pinned tabs as compact icons.
        let compact: Vec<(TabId, Option<String>, String)> = self
            .workspace
            .favorites()
            .iter()
            .map(|f| (f.tab.id, f.tab.favicon_url.clone(), f.tab.display_title()))
            .chain(space.strip.items(Section::Pinned).iter().flat_map(|item| {
                match item {
                    Item::Tab(id) => space
                        .strip
                        .tab(*id)
                        .map(|t| vec![(t.id, t.favicon_url.clone(), t.display_title())])
                        .unwrap_or_default(),
                    Item::Group(group) => space
                        .strip
                        .group(*group)
                        .map(|g| {
                            g.tabs
                                .iter()
                                .filter_map(|id| space.strip.tab(*id))
                                .map(|t| (t.id, t.favicon_url.clone(), t.display_title()))
                                .collect()
                        })
                        .unwrap_or_default(),
                }
            }))
            .collect();
        for (id, icon, title) in compact {
            let is_active = Some(id) == active;
            let tip = SharedString::from(title.clone());
            children.push(
                div()
                    .id(SharedString::from(format!("hpin-{id}")))
                    .size(px(30.))
                    .flex_shrink_0()
                    .rounded(px(8.))
                    .flex()
                    .items_center()
                    .justify_center()
                    .cursor_pointer()
                    .when(is_active, |el| el.bg(theme.row_active).shadow_xs())
                    .when(!is_active, |el| el.hover(|s| s.bg(theme.row_hover)))
                    .child(favicon(icon.as_deref(), &title, px(16.)))
                    .tooltip(move |w, cx| Tooltip::new(tip.clone()).build(w, cx))
                    .on_click(
                        cx.listener(move |this, _, window, cx| this.activate_tab(id, window, cx)),
                    )
                    .into_any_element(),
            );
        }
        if !children.is_empty() {
            children.push(
                div()
                    .w(px(1.))
                    .h(px(18.))
                    .mx(px(4.))
                    .bg(theme.divider)
                    .into_any_element(),
            );
        }

        // Regular tabs, with groups as colored labels.
        for item in space.strip.items(Section::Unpinned) {
            match item {
                Item::Tab(id) => children.push(self.render_strip_tab(*id, None, &menu, cx)),
                Item::Group(gid) => {
                    let Some(group) = space.strip.group(*gid) else {
                        continue;
                    };
                    children.push(self.render_strip_group(*gid, cx));
                    if !group.collapsed || group.tabs.contains(&active.unwrap_or_default()) {
                        for id in &group.tabs {
                            if !group.collapsed || Some(*id) == active {
                                children.push(self.render_strip_tab(*id, Some(*gid), &menu, cx));
                            }
                        }
                    }
                }
            }
        }
        children.push(
            chrome_button("strip-new-tab", IconName::Plus, cx)
                .flex_shrink_0()
                .tooltip(|w, cx| {
                    Tooltip::new("New Tab")
                        .action(&actions::NewTab, None)
                        .build(w, cx)
                })
                .on_click(|_, window, cx| window.dispatch_action(Box::new(actions::NewTab), cx))
                .into_any_element(),
        );

        let space_id = space.id;
        let this = menu.this.clone();
        h_flex()
            .id("tab-strip")
            .h(px(38.))
            .flex_shrink_0()
            .px(px(10.))
            .gap(px(3.))
            .overflow_x_scroll()
            .on_scroll(cx.listener(Self::on_sidebar_swipe))
            .children(children)
            .child(
                div()
                    .id("strip-end")
                    .flex_1()
                    .h_full()
                    .min_w(px(24.))
                    .drag_over::<DraggedTab>(move |s, _, _, _| s.bg(theme.accent_soft))
                    .on_drop(cx.listener(|this, dragged: &DraggedTab, window, cx| {
                        this.drop_tab(
                            dragged.id,
                            Placement::SectionEnd(Section::Unpinned),
                            window,
                            cx,
                        );
                    }))
                    .context_menu(move |menu, _, _| space_menu(menu, this.clone(), space_id)),
            )
            .into_any_element()
    }

    fn render_strip_group(&self, id: GroupId, cx: &mut Context<Self>) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        let space = self.workspace.active_space();
        let Some(group) = space.strip.group(id) else {
            return div().into_any_element();
        };
        let color = CurioTheme::swatch(group.color);
        let collapsed = group.collapsed;
        let space_id = space.id;
        let drag = DraggedGroup {
            id,
            space: space_id,
            name: SharedString::from(group.name.clone()),
        };
        h_flex()
            .id(SharedString::from(format!("hgroup-{id}")))
            .h(px(24.))
            .px(px(8.))
            .gap(px(4.))
            .flex_shrink_0()
            .rounded(px(6.))
            .bg(gpui_kit::Hsla { a: 0.18, ..color })
            .text_xs()
            .font_weight(FontWeight::SEMIBOLD)
            .text_color(theme.text)
            .cursor_pointer()
            .child(div().size(px(7.)).rounded_full().bg(color))
            .child(SharedString::from(group.name.clone()))
            .when(collapsed, |el| {
                el.child(
                    div()
                        .text_color(theme.text_faint)
                        .child(SharedString::from(group.tabs.len().to_string())),
                )
            })
            .on_click(cx.listener(move |this, _, _, cx| {
                if let Some(space) = this.workspace.space_mut(space_id) {
                    space.strip.set_group_collapsed(id, !collapsed);
                }
                this.schedule_save(cx);
                cx.notify();
            }))
            .on_drag(drag, |dragged, _, _, cx| cx.new(|_| dragged.clone()))
            .drag_over::<DraggedTab>(move |s, _, _, _| s.border_1().border_color(theme.accent))
            .on_drop(cx.listener(move |this, dragged: &DraggedTab, window, cx| {
                this.drop_tab(dragged.id, Placement::InGroup(id, None), window, cx);
            }))
            .on_drop(cx.listener(move |this, dragged: &DraggedGroup, _, cx| {
                this.drop_group(dragged, GroupPlacement::BeforeItem(Item::Group(id)), cx);
            }))
            .into_any_element()
    }

    fn render_strip_tab(
        &self,
        id: TabId,
        group: Option<GroupId>,
        menu: &super::sidebar::MenuContext,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        let Some(tab) = self.workspace.tab(id) else {
            return div().into_any_element();
        };
        let is_active = self.workspace.active_tab_id() == Some(id);
        let loading = self
            .tabs
            .get(&id)
            .is_some_and(|e| e.read(cx).state().loading);
        let title = tab.display_title();
        let group_color = group
            .and_then(|g| self.workspace.active_space().strip.group(g))
            .map(|g| CurioTheme::swatch(g.color));
        let drag = DraggedTab {
            id,
            title: SharedString::from(title.clone()),
            favicon: tab.favicon_url.clone(),
        };
        let menu_data = menu.clone();
        let _ = menu_data;
        h_flex()
            .id(SharedString::from(format!("htab-{id}")))
            .group("strip-tab")
            .h(px(30.))
            .min_w(px(96.))
            .max_w(px(220.))
            .flex_1()
            .pl(px(10.))
            .pr(px(4.))
            .gap(px(8.))
            .rounded(px(8.))
            .text_sm()
            .cursor_pointer()
            .when_some(group_color, |el, color| el.border_b_2().border_color(color))
            .when(is_active, |el| {
                el.bg(theme.row_active)
                    .text_color(theme.row_active_text)
                    .shadow_xs()
            })
            .when(!is_active, |el| {
                el.text_color(theme.text_muted)
                    .hover(|s| s.bg(theme.row_hover))
            })
            .child(if loading {
                gpui_kit::component::spinner::Spinner::new()
                    .xsmall()
                    .color(theme.accent)
                    .into_any_element()
            } else {
                favicon(tab.favicon_url.as_deref(), &title, px(15.))
            })
            .child(
                div()
                    .flex_1()
                    .min_w_0()
                    .truncate()
                    .child(SharedString::from(title)),
            )
            .child(
                div()
                    .id(SharedString::from(format!("hclose-{id}")))
                    .size(px(20.))
                    .rounded(px(5.))
                    .flex()
                    .items_center()
                    .justify_center()
                    .invisible()
                    .group_hover("strip-tab", |s| s.visible())
                    .when(is_active, |el| el.visible())
                    .hover(|s| s.bg(theme.row_hover))
                    .child(Icon::new(IconName::X).xsmall())
                    .on_click(cx.listener(move |this, _: &ClickEvent, window, cx| {
                        cx.stop_propagation();
                        this.close_tab(id, window, cx);
                    })),
            )
            .on_click(cx.listener(move |this, _, window, cx| {
                this.activate_tab(id, window, cx);
                this.focus_page_or_window(window, cx);
            }))
            .on_aux_click(cx.listener(move |this, event: &ClickEvent, window, cx| {
                if event.is_middle_click() {
                    this.close_tab(id, window, cx);
                }
            }))
            .on_drag(drag, |dragged, _, _, cx| cx.new(|_| dragged.clone()))
            .drag_over::<DraggedTab>(move |s, _, _, _| s.border_l_2().border_color(theme.accent))
            .on_drop(cx.listener(move |this, dragged: &DraggedTab, window, cx| {
                this.drop_tab(dragged.id, Placement::BeforeTab(id), window, cx);
            }))
            .context_menu({
                let this = menu.this.clone();
                move |popup, _, _| {
                    let pin = this.clone();
                    let fav = this.clone();
                    let close = this.clone();
                    let ask = this.clone();
                    popup
                        .item(PopupMenuItem::new("Pin Tab").icon(IconName::Star).on_click(
                            move |_, _, cx| {
                                let _ = pin.update(cx, |this, cx| this.toggle_pin(id, cx));
                            },
                        ))
                        .item(
                            PopupMenuItem::new("Add to Favorites")
                                .icon(IconName::Heart)
                                .on_click(move |_, window, cx| {
                                    let _ = fav
                                        .update(cx, |this, cx| this.add_favorite(id, window, cx));
                                }),
                        )
                        .item(
                            PopupMenuItem::new("Ask Curio About This Tab")
                                .icon(IconName::Sparkles)
                                .on_click(move |_, window, cx| {
                                    let _ = ask.update(cx, |this, cx| {
                                        this.attach_tab_to_ai(id, window, cx)
                                    });
                                }),
                        )
                        .separator()
                        .item(PopupMenuItem::new("Close Tab").icon(IconName::X).on_click(
                            move |_, window, cx| {
                                let _ = close.update(cx, |this, cx| this.close_tab(id, window, cx));
                            },
                        ))
                }
            })
            .into_any_element()
    }
}
