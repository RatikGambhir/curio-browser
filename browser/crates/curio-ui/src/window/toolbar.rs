//! The toolbar (horizontal layout), the page bar at the top of the page
//! card (vertical layout), the address pill and the horizontal tab strip.

use curio_core::{GroupId, SpaceId, TabId};
use curio_tabs::{GroupPlacement, Item, Placement, Section};
use gpui_kit::AppContext as _;
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants as _};
use gpui_kit::component::menu::{ContextMenuExt as _, DropdownMenu as _, PopupMenuItem};
use gpui_kit::component::{Icon, Sizable as _, h_flex};
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{
    AnyElement, ClickEvent, Context, FontWeight, InteractiveElement as _, IntoElement,
    ParentElement as _, SharedString, StatefulInteractiveElement as _, Styled as _, Window, div,
    px,
};

use super::sidebar::{MenuContext, space_menu};
use super::view_model::PageNav;
use super::{BrowserWindow, DraggedGroup, DraggedTab};
use crate::actions;
use crate::components::prelude::*;
use crate::theme::{CurioTheme, metrics};

/// Back, forward, and reload (or stop while loading).
fn nav_buttons(nav: &PageNav) -> [AnyElement; 3] {
    let reload = if nav.loading {
        IconButton::new("nav-stop", IconName::X)
            .tooltip("Stop")
            .action(actions::StopLoading)
    } else {
        IconButton::new("nav-reload", IconName::RotateCw)
            .tooltip("Reload")
            .action(actions::Reload)
    };
    [
        IconButton::new("nav-back", IconName::ArrowLeft)
            .tooltip("Back")
            .action(actions::GoBack)
            .disabled(!nav.can_go_back)
            .into_any_element(),
        IconButton::new("nav-forward", IconName::ArrowRight)
            .tooltip("Forward")
            .action(actions::GoForward)
            .disabled(!nav.can_go_forward)
            .into_any_element(),
        reload.into_any_element(),
    ]
}

/// Toggles the assistant panel.
fn assistant_button(open: bool) -> IconButton {
    IconButton::new("tool-ai", IconName::Sparkles)
        .tooltip("Curio Assistant")
        .action(actions::ToggleAiPanel)
        .selected(open)
}

/// Opens the downloads list.
fn downloads_button() -> IconButton {
    IconButton::new("tool-downloads", IconName::ArrowDown)
        .tooltip("Downloads")
        .action(actions::ShowDownloads)
}

impl BrowserWindow {
    pub(crate) fn render_toolbar(
        &mut self,
        horizontal: bool,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let nav = self.page_nav(cx);
        h_flex()
            .id("toolbar")
            .h(metrics::TOOLBAR_HEIGHT)
            .flex_shrink_0()
            .px(px(10.))
            .gap(px(4.))
            .window_drag_area()
            .child(traffic_lights_spacer(px(10.)))
            .when(!horizontal, |el| {
                el.child(
                    IconButton::new("tool-sidebar", IconName::PanelLeft)
                        .tooltip("Show Sidebar")
                        .action(actions::ToggleSidebar),
                )
            })
            .when(horizontal, |el| el.child(self.render_space_picker(cx)))
            .children(nav_buttons(&nav))
            .child(
                div()
                    .flex_1()
                    .max_w(px(720.))
                    .mx_auto()
                    .child(self.render_url_pill(&nav, cx)),
            )
            .child(assistant_button(self.ai_open))
            .child(downloads_button())
            .child(
                IconButton::new("tool-settings", IconName::Settings)
                    .tooltip("Settings")
                    .action(actions::OpenSettings),
            )
            .into_any_element()
    }

    /// The space dropdown at the start of the horizontal toolbar.
    fn render_space_picker(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let space = self.workspace.active_space();
        let label = SharedString::from(format!("{}  {}", space.icon, space.name));
        let active_space = space.id;
        let spaces: Vec<(SpaceId, SharedString)> = self
            .workspace
            .spaces()
            .iter()
            .map(|s| (s.id, SharedString::from(format!("{}  {}", s.icon, s.name))))
            .collect();
        let this = cx.entity().downgrade();
        Button::new("space-picker")
            .ghost()
            .small()
            .label(label)
            .icon(IconName::ChevronDown)
            .dropdown_menu(move |mut menu, _, _| {
                for (id, label) in &spaces {
                    let id = *id;
                    menu = menu.item(
                        entity_item(&this, label.clone(), move |this, window, cx| {
                            this.switch_space(id, window, cx);
                        })
                        .checked(id == active_space),
                    );
                }
                menu.separator().item(
                    PopupMenuItem::new("New Space…")
                        .icon(IconName::Plus)
                        .on_click(|_, window, cx| {
                            window.dispatch_action(Box::new(actions::NewSpace), cx);
                        }),
                )
            })
    }

    /// The compact address display; clicking it edits the URL in the
    /// command bar.
    fn render_url_pill(&self, nav: &PageNav, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let is_page = nav.page.is_some();
        let label = nav.page.as_ref().map_or_else(
            || SharedString::from("Search or enter address"),
            |p| SharedString::from(p.host.clone()),
        );
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
                div()
                    .text_color(theme.text_faint)
                    .child(Icon::new(nav.address_icon()).xsmall()),
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
                    .child(label),
            )
            .when_some(nav.zoom_label(), |el, zoom| {
                el.child(div().text_xs().text_color(theme.text_faint).child(zoom))
            })
            .when(is_page, |el| {
                el.child(
                    div()
                        .id("copy-url")
                        .text_color(theme.text_faint)
                        .hover(|s| s.text_color(theme.text))
                        .tooltip_action("Copy Link", &actions::CopyUrl)
                        .on_click(|_, window, cx| {
                            cx.stop_propagation();
                            window.dispatch_action(Box::new(actions::CopyUrl), cx);
                        })
                        .child(Icon::new(IconName::Link).xsmall()),
                )
            })
            .when(nav.loading, |el| {
                el.child(
                    LoadingBar::new("url-loading")
                        .absolute()
                        .left_0()
                        .bottom_0(),
                )
            })
    }

    /// The top row of the page card in the vertical layout: navigation, the
    /// page's address and the window tools, on the card's own surface.
    pub(crate) fn render_page_bar(&self, cx: &mut Context<Self>) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        let nav = self.page_nav(cx);
        let sidebar_tip = if self.sidebar_visible(cx) {
            "Hide Sidebar"
        } else {
            "Show Sidebar"
        };

        let address = h_flex()
            .id("page-address")
            .min_w_0()
            .h(px(28.))
            .px(px(8.))
            .gap(px(6.))
            .rounded(px(7.))
            .text_sm()
            .cursor_text()
            .hover(|s| s.bg(theme.row_hover))
            .on_click(|_, window, cx| window.dispatch_action(Box::new(actions::EditUrl), cx))
            .tooltip_action("Edit Address", &actions::EditUrl)
            .child(
                div()
                    .text_color(theme.text_faint)
                    .child(Icon::new(nav.address_icon()).xsmall()),
            )
            .map(|el| match &nav.page {
                Some(page) => el
                    .child(
                        div()
                            .flex_shrink_0()
                            .text_color(theme.text)
                            .child(SharedString::from(page.host.clone())),
                    )
                    .when(page.title != page.host, |el| {
                        el.child(div().text_color(theme.text_faint).child("/"))
                            .child(
                                div()
                                    .min_w_0()
                                    .truncate()
                                    .text_color(theme.text_muted)
                                    .child(SharedString::from(page.title.clone())),
                            )
                    }),
                None => el.child(
                    div()
                        .text_color(theme.text_faint)
                        .child("Search or enter address"),
                ),
            })
            .when_some(nav.zoom_label(), |el, zoom| {
                el.child(div().text_xs().text_color(theme.text_faint).child(zoom))
            });

        h_flex()
            .id("page-bar")
            .h(metrics::TOOLBAR_HEIGHT)
            .flex_shrink_0()
            .px(px(8.))
            .gap(px(2.))
            .border_b_1()
            .border_color(theme.divider)
            .window_drag_area()
            // Without a left column the traffic lights sit over the card.
            .when(!self.left_column_visible(cx), |el| {
                el.child(traffic_lights_spacer(px(16.)))
            })
            .child(
                IconButton::new("tool-sidebar", IconName::PanelLeft)
                    .tooltip(sidebar_tip)
                    .action(actions::ToggleSidebar),
            )
            .children(nav_buttons(&nav))
            .child(div().w(px(6.)).flex_shrink_0())
            .child(address)
            .child(div().flex_1().min_w(px(12.)))
            .child(assistant_button(self.ai_open))
            .child(downloads_button())
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
        let pinned_tabs = space
            .strip
            .items(Section::Pinned)
            .iter()
            .flat_map(|item| match item {
                Item::Tab(id) => vec![*id],
                Item::Group(group) => space
                    .strip
                    .group(*group)
                    .map(|g| g.tabs.clone())
                    .unwrap_or_default(),
            })
            .filter_map(|id| space.strip.tab(id));
        let compact: Vec<(TabId, Option<String>, String)> = self
            .workspace
            .favorites()
            .iter()
            .map(|f| &f.tab)
            .chain(pinned_tabs)
            .map(|t| (t.id, t.favicon_url.clone(), t.display_title()))
            .collect();
        for (id, icon, title) in compact {
            children.push(
                IconTile::new(
                    SharedString::from(format!("hpin-{id}")),
                    Favicon::new(title.clone()).url(icon.as_deref()),
                )
                .selected(Some(id) == active)
                .tooltip_text(title)
                .on_click(cx.listener(move |this, _, window, cx| this.activate_tab(id, window, cx)))
                .into_any_element(),
            );
        }
        if !children.is_empty() {
            children.push(Divider::vertical().mx(px(4.)).into_any_element());
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
                    // A collapsed group still shows its active tab.
                    for id in &group.tabs {
                        if !group.collapsed || Some(*id) == active {
                            children.push(self.render_strip_tab(*id, Some(*gid), &menu, cx));
                        }
                    }
                }
            }
        }
        children.push(
            IconButton::new("strip-new-tab", IconName::Plus)
                .tooltip("New Tab")
                .action(actions::NewTab)
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
                    .context_menu(move |menu, _, _| space_menu(menu, &this, space_id)),
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
            .child(ColorDot::new(color).diameter(px(7.)))
            .child(SharedString::from(group.name.clone()))
            .when(collapsed, |el| {
                el.child(
                    div()
                        .text_color(theme.text_faint)
                        .child(SharedString::from(group.tabs.len().to_string())),
                )
            })
            .on_click(cx.listener(move |this, _, _, cx| {
                this.set_group_collapsed(space_id, id, !collapsed, cx);
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
        menu: &MenuContext,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        let Some(tab) = self.tab_view(id, cx) else {
            return div().into_any_element();
        };
        let group_color = group
            .and_then(|g| self.workspace.active_space().strip.group(g))
            .map(|g| CurioTheme::swatch(g.color));
        let this = menu.this.clone();
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
            .map(|el| {
                if tab.active {
                    el.bg(theme.row_active)
                        .text_color(theme.row_active_text)
                        .shadow_xs()
                } else {
                    el.text_color(theme.text_muted)
                        .hover(|s| s.bg(theme.row_hover))
                }
            })
            .child(
                Favicon::new(tab.title.clone())
                    .url(tab.favicon.as_deref())
                    .size(px(15.))
                    .loading(tab.loading),
            )
            .child(
                div()
                    .flex_1()
                    .min_w_0()
                    .truncate()
                    .child(SharedString::from(tab.title.clone())),
            )
            .child(
                IconButton::new(SharedString::from(format!("hclose-{id}")), IconName::X)
                    .xsmall()
                    .reveal_on_hover("strip-tab")
                    .force_visible(tab.active)
                    .size(px(20.))
                    .rounded(px(5.))
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
            .on_drag(tab.drag(), |dragged, _, _, cx| cx.new(|_| dragged.clone()))
            .drag_over::<DraggedTab>(move |s, _, _, _| s.border_l_2().border_color(theme.accent))
            .on_drop(cx.listener(move |this, dragged: &DraggedTab, window, cx| {
                this.drop_tab(dragged.id, Placement::BeforeTab(id), window, cx);
            }))
            .context_menu(move |popup, _, _| {
                popup
                    .item(
                        entity_item(&this, "Pin Tab", move |this, _, cx| this.toggle_pin(id, cx))
                            .icon(IconName::Star),
                    )
                    .item(
                        entity_item(&this, "Add to Favorites", move |this, window, cx| {
                            this.add_favorite(id, window, cx);
                        })
                        .icon(IconName::Heart),
                    )
                    .item(
                        entity_item(
                            &this,
                            "Ask Curio About This Tab",
                            move |this, window, cx| {
                                this.attach_tab_to_ai(id, window, cx);
                            },
                        )
                        .icon(IconName::Sparkles),
                    )
                    .separator()
                    .item(
                        entity_item(&this, "Close Tab", move |this, window, cx| {
                            this.close_tab(id, window, cx);
                        })
                        .icon(IconName::X),
                    )
            })
            .into_any_element()
    }
}
