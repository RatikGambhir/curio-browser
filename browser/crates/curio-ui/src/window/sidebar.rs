//! The vertical sidebar: navigation, address pill, favorites, the active
//! space's pinned and regular tabs with folders, and the space switcher.

use std::time::Duration;

use curio_core::{GroupId, SpaceId, TabId, display_host};
use curio_spaces::TabOwner;
use curio_tabs::{GroupPlacement, Item, Placement, Row, Section};
use gpui_kit::AppContext as _;
use gpui_kit::assets::IconName;
use gpui_kit::component::menu::{ContextMenuExt as _, PopupMenu, PopupMenuItem};
use gpui_kit::component::tooltip::Tooltip;
use gpui_kit::component::{Icon, Sizable as _, h_flex, v_flex};
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{
    Animation, AnimationExt as _, AnyElement, ClickEvent, Context, FontWeight,
    InteractiveElement as _, IntoElement, MouseButton, ParentElement as _, SharedString,
    StatefulInteractiveElement as _, Styled as _, WeakEntity, Window, div, px, relative,
};

use super::{BrowserWindow, DraggedGroup, DraggedTab};
use crate::components::{chrome_button, favicon};
use crate::theme::{CurioTheme, metrics};
use crate::{actions, settings};

/// Data needed to build tab and group context menus.
#[derive(Clone)]
pub(crate) struct MenuContext {
    pub this: WeakEntity<BrowserWindow>,
    pub spaces: Vec<(SpaceId, String, String)>,
    pub current_space: SpaceId,
    pub groups: Vec<(GroupId, String)>,
}

impl BrowserWindow {
    pub(crate) fn menu_context(&self, cx: &Context<Self>) -> MenuContext {
        let space = self.workspace.active_space();
        let mut groups: Vec<(GroupId, String)> = space
            .strip
            .groups()
            .map(|g| (g.id, g.name.clone()))
            .collect();
        groups.sort_by(|a, b| a.1.cmp(&b.1));
        MenuContext {
            this: cx.entity().downgrade(),
            spaces: self
                .workspace
                .spaces()
                .iter()
                .map(|s| (s.id, s.name.clone(), s.icon.clone()))
                .collect(),
            current_space: space.id,
            groups,
        }
    }

    pub(crate) fn render_sidebar(
        &mut self,
        peek: bool,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        let reduce_motion = settings(cx).appearance.reduce_motion;
        let direction = self.space_direction;
        let menu = self.menu_context(cx);

        let body = v_flex()
            .id("sidebar-body")
            .flex_1()
            .min_h_0()
            .overflow_y_scroll()
            .px(px(10.))
            .gap(px(2.))
            .child(self.render_favorites(&menu, cx))
            .child(self.render_space_header(&menu, cx))
            .children(self.render_tab_rows(&menu, window, cx))
            .child(
                // Empty space at the end: drop target for "move to end".
                div()
                    .id("unpinned-end")
                    .flex_1()
                    .min_h(px(48.))
                    .w_full()
                    .drag_over::<DraggedTab>(move |s, _, _, _| {
                        s.bg(theme.accent_soft).rounded(metrics::ROW_RADIUS)
                    })
                    .on_drop(cx.listener(|this, dragged: &DraggedTab, window, cx| {
                        this.drop_tab(
                            dragged.id,
                            Placement::SectionEnd(Section::Unpinned),
                            window,
                            cx,
                        );
                    }))
                    .on_drop(cx.listener(|this, dragged: &DraggedGroup, _, cx| {
                        this.drop_group(dragged, GroupPlacement::SectionEnd(Section::Unpinned), cx);
                    })),
            );

        let animated = body.with_animation(
            ("space-slide", self.space_transition),
            Animation::new(Duration::from_millis(if reduce_motion { 1 } else { 260 }))
                .with_easing(gpui_kit::ease_out_quint()),
            move |el, t| {
                el.left(px(direction * 22. * (1. - t)))
                    .opacity(0.2 + 0.8 * t)
            },
        );

        v_flex()
            .id("sidebar")
            .size_full()
            .relative()
            .on_scroll(cx.listener(Self::on_sidebar_swipe))
            .child(self.render_sidebar_header(peek, cx))
            .child(div().px(px(10.)).pb(px(8.)).child(self.render_url_pill(cx)))
            .child(
                div()
                    .relative()
                    .flex_1()
                    .min_h_0()
                    .flex()
                    .flex_col()
                    .child(animated),
            )
            .child(self.render_sidebar_footer(&menu, cx))
            .into_any_element()
    }

    fn render_sidebar_header(&self, peek: bool, cx: &mut Context<Self>) -> impl IntoElement {
        let state = self.active_tab_entity().map(|t| t.read(cx).state().clone());
        let can_back = state.as_ref().is_some_and(|s| s.history.can_go_back);
        let can_forward = state.as_ref().is_some_and(|s| s.history.can_go_forward);
        let loading = state.as_ref().is_some_and(|s| s.loading);
        let theme = *CurioTheme::get(cx);
        h_flex()
            .id("sidebar-header")
            .h(metrics::TOOLBAR_HEIGHT)
            .px(px(10.))
            .gap(px(2.))
            .on_mouse_down(MouseButton::Left, |event, window, _| {
                if event.click_count >= 2 {
                    window.titlebar_double_click();
                } else {
                    window.start_window_move();
                }
            })
            .when(!peek, |el| {
                el.child(
                    div()
                        .w(metrics::TRAFFIC_LIGHTS_WIDTH - px(10.))
                        .flex_shrink_0(),
                )
            })
            .child(
                chrome_button("toggle-sidebar", IconName::PanelLeft, cx)
                    .tooltip(|w, cx| {
                        Tooltip::new("Toggle Sidebar")
                            .action(&actions::ToggleSidebar, None)
                            .build(w, cx)
                    })
                    .on_click(|_, window, cx| {
                        window.dispatch_action(Box::new(actions::ToggleSidebar), cx)
                    }),
            )
            .child(div().flex_1())
            .child(
                chrome_button("nav-back", IconName::ArrowLeft, cx)
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
                chrome_button("nav-forward", IconName::ArrowRight, cx)
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
                chrome_button("nav-stop", IconName::X, cx)
                    .tooltip(|w, cx| Tooltip::new("Stop").build(w, cx))
                    .on_click(|_, window, cx| {
                        window.dispatch_action(Box::new(actions::StopLoading), cx)
                    })
            } else {
                chrome_button("nav-reload", IconName::RotateCw, cx)
                    .tooltip(|w, cx| {
                        Tooltip::new("Reload")
                            .action(&actions::Reload, None)
                            .build(w, cx)
                    })
                    .on_click(|_, window, cx| window.dispatch_action(Box::new(actions::Reload), cx))
            })
            .child(
                chrome_button("toggle-ai", IconName::Sparkles, cx)
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
    }

    /// The compact address display; clicking it edits the URL in the
    /// command bar.
    pub(crate) fn render_url_pill(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let tab = self.workspace.active_tab().cloned();
        let state = self.active_tab_entity().map(|t| t.read(cx).state().clone());
        let loading = state.as_ref().is_some_and(|s| s.loading);
        let secure = state.as_ref().is_some_and(|s| s.secure)
            || tab.as_ref().is_some_and(|t| t.url.starts_with("https:"));
        let (label, is_page) = match &tab {
            Some(tab) if !tab.is_new_tab_page() => (display_host(&tab.url), true),
            _ => ("Search or enter address".to_owned(), false),
        };
        let zoom = state.as_ref().map_or(1.0, |s| s.zoom);
        h_flex()
            .id("url-pill")
            .relative()
            .h(px(34.))
            .px(px(10.))
            .gap(px(7.))
            .rounded(metrics::FIELD_RADIUS)
            .bg(theme.field)
            .hover(|s| s.bg(theme.field_hover))
            .cursor_text()
            .overflow_hidden()
            .on_click(|_, window, cx| window.dispatch_action(Box::new(actions::EditUrl), cx))
            .child(
                div().text_color(theme.text_faint).child(
                    Icon::new(if !is_page {
                        IconName::Search
                    } else if secure {
                        IconName::Lock
                    } else {
                        IconName::Globe
                    })
                    .xsmall(),
                ),
            )
            .child(
                div()
                    .flex_1()
                    .min_w_0()
                    .truncate()
                    .text_sm()
                    .text_color(if is_page {
                        theme.text
                    } else {
                        theme.text_faint
                    })
                    .child(SharedString::from(label)),
            )
            .when((zoom - 1.0).abs() > 0.01, |el| {
                el.child(
                    div()
                        .text_xs()
                        .text_color(theme.text_faint)
                        .child(SharedString::from(format!("{:.0}%", zoom * 100.0))),
                )
            })
            .when(is_page, |el| {
                el.child(
                    div()
                        .id("copy-url")
                        .text_color(theme.text_faint)
                        .hover(|s| s.text_color(theme.text))
                        .tooltip(|w, cx| {
                            Tooltip::new("Copy Link")
                                .action(&actions::CopyUrl, None)
                                .build(w, cx)
                        })
                        .on_click(|_, window, cx| {
                            cx.stop_propagation();
                            window.dispatch_action(Box::new(actions::CopyUrl), cx);
                        })
                        .child(Icon::new(IconName::Link).xsmall()),
                )
            })
            .when(loading, |el| {
                el.child(
                    div()
                        .absolute()
                        .left_0()
                        .bottom_0()
                        .h(px(2.))
                        .w_full()
                        .child(
                            div()
                                .h_full()
                                .w(relative(0.3))
                                .rounded_full()
                                .bg(theme.accent)
                                .with_animation(
                                    "url-loading",
                                    Animation::new(Duration::from_millis(1200))
                                        .repeat()
                                        .with_easing(gpui_kit::ease_in_out),
                                    |el, t| el.ml(relative(-0.3 + 1.3 * t)),
                                ),
                        ),
                )
            })
    }

    fn render_favorites(&self, menu: &MenuContext, cx: &mut Context<Self>) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        let favorites = self.workspace.favorites().to_vec();
        let active = self.workspace.active_tab_id();
        let tiles: Vec<AnyElement> = favorites
            .iter()
            .map(|favorite| {
                let id = favorite.tab.id;
                let fav_id = favorite.id;
                let is_active = Some(id) == active;
                let title = favorite.tab.display_title();
                let this = menu.this.clone();
                div()
                    .id(SharedString::from(format!("fav-{fav_id}")))
                    .h(px(44.))
                    .flex_1()
                    .min_w(px(44.))
                    .max_w(relative(0.25))
                    .rounded(px(10.))
                    .flex()
                    .items_center()
                    .justify_center()
                    .bg(if is_active {
                        theme.row_active
                    } else {
                        theme.field
                    })
                    .when(is_active, |el| el.shadow_sm())
                    .hover(|s| s.bg(theme.field_hover))
                    .cursor_pointer()
                    .tooltip({
                        let title = SharedString::from(title.clone());
                        move |w, cx| Tooltip::new(title.clone()).build(w, cx)
                    })
                    .child(favicon(
                        favorite.tab.favicon_url.as_deref(),
                        &title,
                        px(20.),
                    ))
                    .on_click(
                        cx.listener(move |this, _, window, cx| this.activate_tab(id, window, cx)),
                    )
                    .context_menu(move |menu, _, _| {
                        let reset = this.clone();
                        let remove = this.clone();
                        menu.item(
                            PopupMenuItem::new("Go to Saved Address")
                                .icon(IconName::Undo2)
                                .on_click(move |_, window, cx| {
                                    let _ = reset
                                        .update(cx, |this, cx| this.reset_favorite(id, window, cx));
                                }),
                        )
                        .separator()
                        .item(
                            PopupMenuItem::new("Remove from Favorites")
                                .icon(IconName::Delete)
                                .on_click(move |_, window, cx| {
                                    let _ = remove.update(cx, |this, cx| {
                                        this.remove_favorite(fav_id, window, cx)
                                    });
                                }),
                        )
                    })
                    .into_any_element()
            })
            .collect();
        div()
            .id("favorites")
            .pt(px(2.))
            .pb(px(8.))
            .drag_over::<DraggedTab>(move |s, _, _, _| s.bg(theme.accent_soft).rounded(px(10.)))
            .on_drop(cx.listener(|this, dragged: &DraggedTab, window, cx| {
                this.add_favorite(dragged.id, window, cx);
            }))
            .when(!tiles.is_empty(), |el| {
                el.child(h_flex().flex_wrap().gap(px(6.)).children(tiles))
            })
            .into_any_element()
    }

    fn render_space_header(&self, menu: &MenuContext, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let space = self.workspace.active_space();
        let space_id = space.id;
        let this = menu.this.clone();
        h_flex()
            .id("space-header")
            .h(px(32.))
            .px(px(6.))
            .gap(px(8.))
            .mt(px(2.))
            .rounded(metrics::ROW_RADIUS)
            .child(
                div()
                    .text_size(px(15.))
                    .child(SharedString::from(space.icon.clone())),
            )
            .child(
                div()
                    .flex_1()
                    .truncate()
                    .text_sm()
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_color(theme.text)
                    .child(SharedString::from(space.name.clone())),
            )
            .child(
                chrome_button("space-menu", IconName::Ellipsis, cx)
                    .context_menu(move |menu, _, _| space_menu(menu, this.clone(), space_id)),
            )
            .context_menu({
                let this = menu.this.clone();
                move |menu, _, _| space_menu(menu, this.clone(), space_id)
            })
    }

    fn render_tab_rows(
        &self,
        menu: &MenuContext,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Vec<AnyElement> {
        let theme = *CurioTheme::get(cx);
        let space = self.workspace.active_space();
        let active = space.active_tab;
        let rows = space.strip.rows(active);
        let has_pinned = !space.strip.items(Section::Pinned).is_empty();
        let mut out: Vec<AnyElement> = Vec::with_capacity(rows.len() + 2);
        let mut divider_done = false;
        for row in rows {
            let section = match row {
                Row::Tab { section, .. } | Row::Group { section, .. } => section,
            };
            if section == Section::Unpinned && !divider_done {
                out.push(self.render_new_tab_divider(has_pinned, cx));
                divider_done = true;
            }
            match row {
                Row::Tab { id, group, .. } => {
                    out.push(self.render_tab_row(id, group, menu, window, cx))
                }
                Row::Group { id, .. } => out.push(self.render_group_row(id, menu, cx)),
            }
        }
        if !divider_done {
            out.push(self.render_new_tab_divider(has_pinned, cx));
        }
        if space.strip.is_empty() {
            out.push(
                div()
                    .px(px(8.))
                    .py(px(10.))
                    .text_xs()
                    .text_color(theme.text_faint)
                    .child("Tabs you open in this space appear here. Drag tabs above the line to pin them.")
                    .into_any_element(),
            );
        }
        out
    }

    fn render_new_tab_divider(&self, has_pinned: bool, cx: &mut Context<Self>) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        v_flex()
            .id("new-tab-divider")
            .gap(px(4.))
            .py(px(4.))
            .child(
                div()
                    .id("pinned-end")
                    .h(px(6.))
                    .mx(px(6.))
                    .border_b_1()
                    .border_color(theme.divider)
                    .when(!has_pinned, |el| el.opacity(0.6))
                    .drag_over::<DraggedTab>(move |s, _, _, _| {
                        s.border_color(theme.accent).border_b_2()
                    })
                    .on_drop(cx.listener(|this, dragged: &DraggedTab, window, cx| {
                        this.drop_tab(
                            dragged.id,
                            Placement::SectionEnd(Section::Pinned),
                            window,
                            cx,
                        );
                    }))
                    .on_drop(cx.listener(|this, dragged: &DraggedGroup, _, cx| {
                        this.drop_group(dragged, GroupPlacement::SectionEnd(Section::Pinned), cx);
                    })),
            )
            .child(
                h_flex()
                    .id("new-tab-row")
                    .h(metrics::ROW_HEIGHT)
                    .px(px(8.))
                    .gap(px(10.))
                    .rounded(metrics::ROW_RADIUS)
                    .text_sm()
                    .text_color(theme.text_muted)
                    .cursor_pointer()
                    .hover(|s| s.bg(theme.row_hover).text_color(theme.text))
                    .child(Icon::new(IconName::Plus).small())
                    .child("New Tab")
                    .on_click(|_, window, cx| {
                        window.dispatch_action(Box::new(actions::NewTab), cx)
                    }),
            )
            .into_any_element()
    }

    fn render_tab_row(
        &self,
        id: TabId,
        group: Option<GroupId>,
        menu: &MenuContext,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        let Some(tab) = self.workspace.tab(id) else {
            return div().into_any_element();
        };
        let space = self.workspace.active_space();
        let is_active = space.active_tab == Some(id);
        let pinned = space.strip.is_pinned(id);
        let live = self.tabs.get(&id).map(|e| e.read(cx).state().clone());
        let loading = live.as_ref().is_some_and(|s| s.loading);
        let asleep = !self.tabs.get(&id).is_some_and(|e| e.read(cx).is_awake());
        let title = tab.display_title();
        let favicon_url = tab.favicon_url.clone();
        let drag = DraggedTab {
            id,
            title: SharedString::from(title.clone()),
            favicon: favicon_url.clone(),
        };
        let menu = menu.clone();
        h_flex()
            .id(SharedString::from(format!("tab-{id}")))
            .group("tab-row")
            .h(metrics::ROW_HEIGHT)
            .pl(if group.is_some() { px(22.) } else { px(8.) })
            .pr(px(4.))
            .gap(px(10.))
            .rounded(metrics::ROW_RADIUS)
            .text_sm()
            .cursor_pointer()
            .when(is_active, |el| {
                el.bg(theme.row_active)
                    .text_color(theme.row_active_text)
                    .border_1()
                    .border_color(theme.row_active_border)
                    .shadow_xs()
            })
            .when(!is_active, |el| {
                el.text_color(theme.text_muted)
                    .hover(|s| s.bg(theme.row_hover).text_color(theme.text))
            })
            .child(
                div()
                    .size(px(16.))
                    .flex_shrink_0()
                    .when(asleep && !is_active && !pinned, |el| el.opacity(0.65))
                    .child(if loading {
                        gpui_kit::component::spinner::Spinner::new()
                            .xsmall()
                            .color(theme.accent)
                            .into_any_element()
                    } else {
                        favicon(favicon_url.as_deref(), &title, px(16.))
                    }),
            )
            .child(
                div()
                    .flex_1()
                    .min_w_0()
                    .truncate()
                    .when(is_active, |el| el.font_weight(FontWeight::MEDIUM))
                    .child(SharedString::from(title)),
            )
            .child(
                div()
                    .id(SharedString::from(format!("close-{id}")))
                    .size(px(22.))
                    .flex_shrink_0()
                    .rounded(px(6.))
                    .flex()
                    .items_center()
                    .justify_center()
                    .text_color(theme.text_faint)
                    .invisible()
                    .group_hover("tab-row", |s| s.visible())
                    .when(is_active, |el| el.visible())
                    .hover(|s| s.bg(theme.row_hover).text_color(theme.text))
                    .child(Icon::new(if pinned { IconName::Minus } else { IconName::X }).xsmall())
                    .tooltip(move |w, cx| {
                        Tooltip::new(if pinned { "Unload Tab" } else { "Close Tab" }).build(w, cx)
                    })
                    .on_click(cx.listener(move |this, _: &ClickEvent, window, cx| {
                        cx.stop_propagation();
                        if pinned {
                            this.unload_tab(id, window, cx);
                        } else {
                            this.close_tab(id, window, cx);
                        }
                    })),
            )
            .on_click(cx.listener(move |this, event: &ClickEvent, window, cx| {
                if event.modifiers().secondary(cx) {
                    // ⌘-click adds the tab to the assistant's context.
                    this.attach_tab_to_ai(id, window, cx);
                } else {
                    this.activate_tab(id, window, cx);
                    this.focus_page_or_window(window, cx);
                }
            }))
            .on_aux_click(cx.listener(move |this, event: &ClickEvent, window, cx| {
                if event.is_middle_click() {
                    this.close_tab(id, window, cx);
                }
            }))
            .on_drag(drag, |dragged, _, _, cx| cx.new(|_| dragged.clone()))
            .drag_over::<DraggedTab>(move |s, _, _, _| s.border_t_2().border_color(theme.accent))
            .on_drop(cx.listener(move |this, dragged: &DraggedTab, window, cx| {
                this.drop_tab(dragged.id, Placement::BeforeTab(id), window, cx);
            }))
            .when(group.is_none(), |el| {
                el.on_drop(cx.listener(move |this, dragged: &DraggedGroup, _, cx| {
                    this.drop_group(dragged, GroupPlacement::BeforeItem(Item::Tab(id)), cx);
                }))
            })
            .context_menu(move |popup, window, cx| {
                tab_menu(popup, &menu, id, pinned, group, window, cx)
            })
            .into_any_element()
    }

    fn render_group_row(
        &self,
        id: GroupId,
        menu: &MenuContext,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        let space = self.workspace.active_space();
        let Some(group) = space.strip.group(id) else {
            return div().into_any_element();
        };
        let collapsed = group.collapsed;
        let color = CurioTheme::swatch(group.color);
        let space_id = space.id;
        let drag = DraggedGroup {
            id,
            space: space_id,
            name: SharedString::from(group.name.clone()),
        };
        let count = group.tabs.len();
        let menu = menu.clone();
        h_flex()
            .id(SharedString::from(format!("group-{id}")))
            .h(px(30.))
            .px(px(8.))
            .gap(px(8.))
            .rounded(metrics::ROW_RADIUS)
            .text_sm()
            .text_color(theme.text_muted)
            .cursor_pointer()
            .hover(|s| s.bg(theme.row_hover).text_color(theme.text))
            .child(
                div()
                    .size(px(16.))
                    .flex()
                    .items_center()
                    .justify_center()
                    .child(
                        Icon::new(if collapsed {
                            IconName::ChevronRight
                        } else {
                            IconName::ChevronDown
                        })
                        .xsmall(),
                    ),
            )
            .child(
                div().text_color(color).child(
                    Icon::new(if collapsed {
                        IconName::Folder
                    } else {
                        IconName::FolderOpen
                    })
                    .small(),
                ),
            )
            .child(
                div()
                    .flex_1()
                    .truncate()
                    .font_weight(FontWeight::MEDIUM)
                    .child(SharedString::from(group.name.clone())),
            )
            .when(collapsed, |el| {
                el.child(
                    div()
                        .text_xs()
                        .text_color(theme.text_faint)
                        .child(SharedString::from(count.to_string())),
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
            .drag_over::<DraggedTab>(move |s, _, _, _| s.bg(theme.accent_soft))
            .drag_over::<DraggedGroup>(move |s, _, _, _| s.border_t_2().border_color(theme.accent))
            .on_drop(cx.listener(move |this, dragged: &DraggedTab, window, cx| {
                this.drop_tab(dragged.id, Placement::InGroup(id, None), window, cx);
            }))
            .on_drop(cx.listener(move |this, dragged: &DraggedGroup, _, cx| {
                this.drop_group(dragged, GroupPlacement::BeforeItem(Item::Group(id)), cx);
            }))
            .context_menu(move |popup, window, cx| {
                group_menu(popup, &menu, space_id, id, window, cx)
            })
            .into_any_element()
    }

    fn render_sidebar_footer(
        &self,
        menu: &MenuContext,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let active = self.workspace.active_space_id();
        let downloads_active = self.downloads.iter().any(|d| !d.finished);
        let spaces: Vec<AnyElement> = self
            .workspace
            .spaces()
            .iter()
            .map(|space| {
                let id = space.id;
                let is_active = id == active;
                let name = SharedString::from(space.name.clone());
                let this = menu.this.clone();
                // Like Arc: one dot per space in the color picked for it; the
                // active space's dot is larger and solid.
                let dot = px(if is_active { 8. } else { 6. });
                div()
                    .id(SharedString::from(format!("space-{id}")))
                    .w(px(18.))
                    .h(px(28.))
                    .rounded(px(6.))
                    .flex()
                    .items_center()
                    .justify_center()
                    .cursor_pointer()
                    .when(!is_active, |el| el.opacity(0.5).hover(|s| s.opacity(1.)))
                    .child(
                        div()
                            .size(dot)
                            .rounded_full()
                            .bg(CurioTheme::swatch(space.color)),
                    )
                    .tooltip(move |w, cx| Tooltip::new(name.clone()).build(w, cx))
                    .on_click(
                        cx.listener(move |this, _, window, cx| this.switch_space(id, window, cx)),
                    )
                    .drag_over::<DraggedTab>(move |s, _, _, _| s.bg(theme.accent_soft))
                    .on_drop(cx.listener(move |this, dragged: &DraggedTab, window, cx| {
                        this.move_tab_to_space(dragged.id, id, window, cx);
                    }))
                    .on_drop(
                        cx.listener(move |this, dragged: &DraggedGroup, window, cx| {
                            if this
                                .workspace
                                .move_group_to_space(dragged.id, dragged.space, id)
                            {
                                this.sync_active_tab(window, cx);
                                this.schedule_save(cx);
                            }
                        }),
                    )
                    .context_menu(move |menu, _, _| space_menu(menu, this.clone(), id))
                    .into_any_element()
            })
            .collect();
        h_flex()
            .h(px(44.))
            .px(px(10.))
            .gap(px(4.))
            .border_t_1()
            .border_color(theme.divider)
            .child(
                chrome_button("library", IconName::ArrowRight, cx)
                    .when(downloads_active, |el| el.text_color(theme.accent_text))
                    .tooltip(|w, cx| {
                        Tooltip::new("Library")
                            .action(&actions::ToggleLibrary, None)
                            .build(w, cx)
                    })
                    .on_click(|_, window, cx| {
                        window.dispatch_action(Box::new(actions::ToggleLibrary), cx)
                    }),
            )
            .child(
                h_flex()
                    .id("space-switcher")
                    .flex_1()
                    .justify_center()
                    .gap(px(2.))
                    .overflow_x_scroll()
                    .children(spaces),
            )
            .child(
                chrome_button("new-space", IconName::Plus, cx)
                    .tooltip(|w, cx| {
                        Tooltip::new("New Space")
                            .action(&actions::NewSpace, None)
                            .build(w, cx)
                    })
                    .on_click(|_, window, cx| {
                        window.dispatch_action(Box::new(actions::NewSpace), cx)
                    }),
            )
            .child(
                chrome_button("settings", IconName::Settings, cx)
                    .tooltip(|w, cx| {
                        Tooltip::new("Settings")
                            .action(&actions::OpenSettings, None)
                            .build(w, cx)
                    })
                    .on_click(|_, window, cx| {
                        window.dispatch_action(Box::new(actions::OpenSettings), cx)
                    }),
            )
    }

    // ----- Drag and drop and menu operations -------------------------------

    pub(crate) fn drop_tab(
        &mut self,
        id: TabId,
        placement: Placement,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let target_space = self.workspace.active_space_id();
        match self.workspace.find_tab(id).map(|(owner, _)| owner) {
            Some(TabOwner::Space(space)) if space == target_space => {
                if let Some(space) = self.workspace.space_mut(space) {
                    space.strip.move_tab(id, placement);
                }
            }
            Some(TabOwner::Space(_)) => {
                self.move_tab_to_space(id, target_space, window, cx);
                if let Some(space) = self.workspace.space_mut(target_space) {
                    space.strip.move_tab(id, placement);
                }
            }
            Some(TabOwner::Favorite(_)) | None => return,
        }
        self.schedule_save(cx);
        cx.notify();
    }

    pub(crate) fn drop_group(
        &mut self,
        dragged: &DraggedGroup,
        placement: GroupPlacement,
        cx: &mut Context<Self>,
    ) {
        if dragged.space != self.workspace.active_space_id() {
            return;
        }
        if let Some(space) = self.workspace.space_mut(dragged.space) {
            space.strip.move_group(dragged.id, placement);
        }
        self.schedule_save(cx);
        cx.notify();
    }

    pub(crate) fn move_tab_to_space(
        &mut self,
        id: TabId,
        space: SpaceId,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.workspace.move_tab_to_space(id, space) {
            self.sync_active_tab(window, cx);
            self.schedule_save(cx);
        }
    }

    pub(crate) fn unload_tab(&mut self, id: TabId, window: &mut Window, cx: &mut Context<Self>) {
        // Pinned tabs are kept; "closing" them unloads the page instead.
        if let Some(entity) = self.tabs.get(&id).cloned() {
            entity.update(cx, |tab, cx| tab.sleep(cx));
        }
        if let Some(home) = self.workspace.tab(id).and_then(|t| t.home_url.clone())
            && let Some(tab) = self.workspace.tab_mut(id)
        {
            tab.url = home;
            tab.scroll_y = 0.0;
        }
        self.release_tab(id);
        if self.workspace.active_tab_id() == Some(id) {
            let next = self
                .workspace
                .active_space()
                .strip
                .ordered_tab_ids()
                .into_iter()
                .find(|t| *t != id);
            self.workspace.active_space_mut().active_tab = next;
        }
        self.sync_active_tab(window, cx);
        self.schedule_save(cx);
    }

    pub(crate) fn reset_favorite(
        &mut self,
        id: TabId,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(home) = self.workspace.tab(id).and_then(|t| t.home_url.clone()) else {
            return;
        };
        self.activate_tab(id, window, cx);
        self.navigate_active(&home, window, cx);
    }

    pub(crate) fn remove_favorite(
        &mut self,
        id: curio_core::FavoriteId,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if let Some(favorite) = self.workspace.remove_favorite(id) {
            self.release_tab(favorite.tab.id);
            self.sync_active_tab(window, cx);
            self.schedule_save(cx);
        }
    }

    pub(crate) fn attach_tab_to_ai(
        &mut self,
        id: TabId,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(tab) = self.workspace.tab(id).cloned() else {
            return;
        };
        self.show_ai(window, cx);
        self.ai_panel.update(cx, |panel, cx| {
            panel.attach_tab(
                crate::ai_panel::ContextTab {
                    id,
                    title: tab.display_title(),
                    url: tab.url.clone(),
                    favicon: tab.favicon_url.clone(),
                },
                cx,
            );
        });
    }
}

/// The context menu for a space.
pub(crate) fn space_menu(
    menu: PopupMenu,
    this: WeakEntity<BrowserWindow>,
    space: SpaceId,
) -> PopupMenu {
    let edit = this.clone();
    let left = this.clone();
    let right = this.clone();
    let delete = this.clone();
    let ask = this;
    menu.item(
        PopupMenuItem::new("Edit Space…")
            .icon(IconName::Palette)
            .on_click(move |_, window, cx| {
                let _ = edit.update(cx, |this, cx| this.edit_space(Some(space), window, cx));
            }),
    )
    .item(
        PopupMenuItem::new("Ask Curio About This Space")
            .icon(IconName::Sparkles)
            .on_click(move |_, window, cx| {
                let _ = ask.update(cx, |this, cx| {
                    this.switch_space(space, window, cx);
                    this.show_ai(window, cx);
                    this.ai_panel.update(cx, |panel, cx| {
                        panel.quick_action(&curio_ai::QuickAction::CompareTabs, window, cx);
                    });
                });
            }),
    )
    .separator()
    .item(
        PopupMenuItem::new("Move Left")
            .icon(IconName::ChevronLeft)
            .on_click(move |_, _, cx| {
                let _ = left.update(cx, |this, cx| this.shift_space(space, -1, cx));
            }),
    )
    .item(
        PopupMenuItem::new("Move Right")
            .icon(IconName::ChevronRight)
            .on_click(move |_, _, cx| {
                let _ = right.update(cx, |this, cx| this.shift_space(space, 1, cx));
            }),
    )
    .separator()
    .item(
        PopupMenuItem::new("Delete Space…")
            .icon(IconName::Delete)
            .on_click(move |_, window, cx| {
                let _ = delete.update(cx, |this, cx| this.confirm_delete_space(space, window, cx));
            }),
    )
}

/// The context menu for a tab.
fn tab_menu(
    menu: PopupMenu,
    ctx: &MenuContext,
    id: TabId,
    pinned: bool,
    group: Option<GroupId>,
    window: &mut Window,
    cx: &mut Context<PopupMenu>,
) -> PopupMenu {
    let this = ctx.this.clone();
    let action =
        |label: &'static str,
         icon: IconName,
         f: fn(&mut BrowserWindow, TabId, &mut Window, &mut Context<BrowserWindow>)| {
            let this = this.clone();
            PopupMenuItem::new(label)
                .icon(icon)
                .on_click(move |_, window, cx| {
                    let _ = this.update(cx, |this, cx| f(this, id, window, cx));
                })
        };
    let spaces = ctx.spaces.clone();
    let current_space = ctx.current_space;
    let groups = ctx.groups.clone();
    let move_this = this.clone();
    let group_this = this.clone();
    let mut menu = menu
        .item(action(
            if pinned { "Unpin Tab" } else { "Pin Tab" },
            IconName::Star,
            |this, id, _, cx| this.toggle_pin(id, cx),
        ))
        .item(action(
            "Add to Favorites",
            IconName::Heart,
            |this, id, window, cx| {
                this.add_favorite(id, window, cx);
            },
        ))
        .item(action(
            "Duplicate Tab",
            IconName::Copy,
            |this, id, window, cx| {
                if this.workspace.duplicate_tab(id).is_some() {
                    this.sync_active_tab(window, cx);
                    this.schedule_save(cx);
                }
            },
        ))
        .item(action("Copy Link", IconName::Link, |this, id, _, cx| {
            if let Some(tab) = this.workspace.tab(id) {
                cx.write_to_clipboard(gpui_kit::ClipboardItem::new_string(tab.url.clone()));
            }
        }))
        .item(action(
            "Ask Curio About This Tab",
            IconName::Sparkles,
            |this, id, window, cx| {
                this.attach_tab_to_ai(id, window, cx);
            },
        ))
        .separator();
    menu = menu.submenu("Move to Group", window, cx, move |mut menu, _, _| {
        let this = group_this.clone();
        let create = this.clone();
        menu = menu.item(
            PopupMenuItem::new("New Group…")
                .icon(IconName::FolderPlus)
                .on_click(move |_, window, cx| {
                    let _ = create.update(cx, |this, cx| this.new_group_with(vec![id], window, cx));
                }),
        );
        if !groups.is_empty() {
            menu = menu.separator();
        }
        for (gid, name) in &groups {
            let gid = *gid;
            let this = this.clone();
            menu = menu.item(
                PopupMenuItem::new(SharedString::from(name.clone()))
                    .icon(IconName::Folder)
                    .checked(group == Some(gid))
                    .on_click(move |_, window, cx| {
                        let _ = this.update(cx, |this, cx| {
                            this.drop_tab(id, Placement::InGroup(gid, None), window, cx)
                        });
                    }),
            );
        }
        menu
    });
    if group.is_some() {
        menu = menu.item(action(
            "Remove from Group",
            IconName::FolderMinus,
            |this, id, window, cx| {
                let anchor = this
                    .workspace
                    .active_space()
                    .strip
                    .location_of(id)
                    .and_then(|l| l.group);
                if let Some(group) = anchor {
                    this.drop_tab(id, Placement::AfterGroup(group), window, cx);
                }
            },
        ));
    }
    menu = menu.submenu("Move to Space", window, cx, move |mut menu, _, _| {
        for (sid, name, icon) in &spaces {
            if *sid == current_space {
                continue;
            }
            let sid = *sid;
            let this = move_this.clone();
            menu = menu.item(
                PopupMenuItem::new(SharedString::from(format!("{icon}  {name}"))).on_click(
                    move |_, window, cx| {
                        let _ =
                            this.update(cx, |this, cx| this.move_tab_to_space(id, sid, window, cx));
                    },
                ),
            );
        }
        menu
    });
    menu.separator()
        .item(action(
            if pinned { "Unload Tab" } else { "Close Tab" },
            IconName::X,
            |this, id, window, cx| {
                if this.workspace.active_space().strip.is_pinned(id) {
                    this.unload_tab(id, window, cx);
                } else {
                    this.close_tab(id, window, cx);
                }
            },
        ))
        .item(action(
            "Close Other Tabs",
            IconName::CircleX,
            |this, id, window, cx| {
                let others: Vec<TabId> = this
                    .workspace
                    .active_space()
                    .strip
                    .items(Section::Unpinned)
                    .iter()
                    .filter_map(|item| match item {
                        Item::Tab(t) if *t != id => Some(*t),
                        _ => None,
                    })
                    .collect();
                for other in others {
                    this.close_tab(other, window, cx);
                }
            },
        ))
}

/// The context menu for a tab group.
fn group_menu(
    menu: PopupMenu,
    ctx: &MenuContext,
    space: SpaceId,
    group: GroupId,
    window: &mut Window,
    cx: &mut Context<PopupMenu>,
) -> PopupMenu {
    let this = ctx.this.clone();
    let rename = this.clone();
    let ungroup = this.clone();
    let close = this.clone();
    let colors = this.clone();
    let spaces = ctx.spaces.clone();
    let move_this = this.clone();
    menu.item(
        PopupMenuItem::new("Rename Group…")
            .icon(IconName::Pencil)
            .on_click(move |_, window, cx| {
                let _ = rename.update(cx, |this, cx| this.rename_group(space, group, window, cx));
            }),
    )
    .submenu("Color", window, cx, move |mut menu, _, _| {
        for color in curio_core::AccentColor::ALL {
            let this = colors.clone();
            menu = menu.item(
                PopupMenuItem::new(color.label())
                    .icon(Icon::new(IconName::CircleSmall).text_color(CurioTheme::swatch(color)))
                    .on_click(move |_, _, cx| {
                        let _ = this.update(cx, |this, cx| {
                            if let Some(space) = this.workspace.space_mut(space) {
                                space.strip.set_group_color(group, color);
                            }
                            this.schedule_save(cx);
                            cx.notify();
                        });
                    }),
            );
        }
        menu
    })
    .submenu("Move Group to Space", window, cx, move |mut menu, _, _| {
        for (sid, name, icon) in &spaces {
            if *sid == space {
                continue;
            }
            let sid = *sid;
            let this = move_this.clone();
            menu = menu.item(
                PopupMenuItem::new(SharedString::from(format!("{icon}  {name}"))).on_click(
                    move |_, window, cx| {
                        let _ = this.update(cx, |this, cx| {
                            if this.workspace.move_group_to_space(group, space, sid) {
                                this.sync_active_tab(window, cx);
                                this.schedule_save(cx);
                            }
                        });
                    },
                ),
            );
        }
        menu
    })
    .separator()
    .item(
        PopupMenuItem::new("Ungroup Tabs")
            .icon(IconName::FolderMinus)
            .on_click(move |_, _, cx| {
                let _ = ungroup.update(cx, |this, cx| {
                    if let Some(space) = this.workspace.space_mut(space) {
                        space.strip.delete_group(group, true);
                    }
                    this.schedule_save(cx);
                    cx.notify();
                });
            }),
    )
    .item(
        PopupMenuItem::new("Close Group and Tabs")
            .icon(IconName::Delete)
            .on_click(move |_, window, cx| {
                let _ = close.update(cx, |this, cx| {
                    let closed: Vec<TabId> = this
                        .workspace
                        .space_mut(space)
                        .map(|s| {
                            s.strip
                                .delete_group(group, false)
                                .into_iter()
                                .map(|t| t.id)
                                .collect()
                        })
                        .unwrap_or_default();
                    for id in closed {
                        this.release_tab(id);
                    }
                    if let Some(space) = this.workspace.space_mut(space)
                        && space.active_tab.is_some_and(|t| !space.strip.contains(t))
                    {
                        space.active_tab = space.strip.ordered_tab_ids().first().copied();
                    }
                    this.sync_active_tab(window, cx);
                    this.schedule_save(cx);
                });
            }),
    )
}
