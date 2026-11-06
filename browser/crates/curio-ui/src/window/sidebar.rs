//! The vertical sidebar: favorites, the active space's pinned and regular
//! tabs with folders, and the space switcher.

use std::time::Duration;

use curio_core::{GroupId, SpaceId, TabId};
use curio_settings::TabLayout;
use curio_spaces::TabOwner;
use curio_tabs::{GroupPlacement, Item, Placement, Row, Section};
use gpui_kit::AppContext as _;
use gpui_kit::assets::IconName;
use gpui_kit::component::input::{Input, InputEvent, InputState};
use gpui_kit::component::menu::{ContextMenuExt as _, PopupMenu};
use gpui_kit::component::{Icon, Sizable as _, h_flex, v_flex};
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{
    Animation, AnimationExt as _, AnyElement, ClickEvent, Context, Entity, FontWeight, Hsla,
    InteractiveElement as _, IntoElement, MouseButton, ParentElement as _, Pixels, SharedString,
    StatefulInteractiveElement as _, Styled as _, Subscription, WeakEntity, Window, div, px,
};

use super::{BrowserWindow, DraggedGroup, DraggedTab};
use crate::components::prelude::*;
use crate::theme::{CurioTheme, metrics};
use crate::{actions, settings};

/// Height of a favorite tile.
const FAVORITE_TILE_HEIGHT: Pixels = px(40.);
/// Space between favorite tiles, across and down.
const FAVORITE_GAP: Pixels = px(6.);

/// How many favorite tiles fit in a row of a sidebar this wide: four, or
/// three when four would make tiles narrower than 48px.
fn favorite_columns(sidebar_width: Pixels) -> usize {
    // The sidebar body's side padding is 10px on each side.
    let inner = sidebar_width - px(20.);
    if inner >= px(48.) * 4. + FAVORITE_GAP * 3. {
        4
    } else {
        3
    }
}

/// A folder name being edited in place.
pub(crate) struct FolderRename {
    space: SpaceId,
    group: GroupId,
    input: Entity<InputState>,
    _events: Subscription,
}

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
                    }))
                    .context_menu({
                        let this = menu.this.clone();
                        move |popup, _, _| {
                            popup.item(
                                entity_item(&this, "New Folder", |this, window, cx| {
                                    this.new_folder(window, cx);
                                })
                                .icon(IconName::FolderPlus),
                            )
                        }
                    }),
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
            // The traffic lights sit over the header strip, which also moves
            // the window. Navigation lives in the page bar above the page.
            .when(!peek, |el| {
                el.child(
                    div()
                        .id("sidebar-header")
                        .h(metrics::TOOLBAR_HEIGHT)
                        .w_full()
                        .flex_shrink_0()
                        .window_drag_area(),
                )
            })
            .when(peek, |el| el.pt(px(8.)))
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

    /// Favorites as a grid of tiles at the top of the sidebar, like Dia:
    /// four to a row (three when the sidebar is narrow), stretching with
    /// the sidebar's width. The next free slot is a dashed tile that adds
    /// the current tab, and the whole grid takes dropped tabs.
    fn render_favorites(&self, menu: &MenuContext, cx: &mut Context<Self>) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        let active = self.workspace.active_tab_id();
        let columns = favorite_columns(self.sidebar_width);
        let mut tiles: Vec<AnyElement> = self
            .workspace
            .favorites()
            .iter()
            .map(|favorite| {
                let id = favorite.tab.id;
                let fav_id = favorite.id;
                let title = favorite.tab.display_title();
                let this = menu.this.clone();
                IconTile::new(
                    SharedString::from(format!("fav-{fav_id}")),
                    Favicon::new(title.clone())
                        .url(favorite.tab.favicon_url.as_deref())
                        .size(px(18.)),
                )
                .filled(true)
                .selected(Some(id) == active)
                .flex_1()
                .min_w_0()
                .h(FAVORITE_TILE_HEIGHT)
                .rounded(px(10.))
                .tooltip_text(title)
                .on_click(cx.listener(move |this, _, window, cx| this.activate_tab(id, window, cx)))
                .context_menu(move |menu, _, _| {
                    menu.item(
                        entity_item(&this, "Go to Saved Address", move |this, window, cx| {
                            this.reset_favorite(id, window, cx);
                        })
                        .icon(IconName::Undo2),
                    )
                    .separator()
                    .item(
                        entity_item(&this, "Remove from Favorites", move |this, window, cx| {
                            this.remove_favorite(fav_id, window, cx);
                        })
                        .icon(IconName::Delete),
                    )
                })
                .into_any_element()
            })
            .collect();

        // The next free slot invites a new favorite. A full last row skips
        // it rather than start a row of one; the grid still takes drops.
        if !tiles.len().is_multiple_of(columns) || tiles.is_empty() {
            let edge = Hsla {
                a: 0.28,
                ..theme.text_faint
            };
            tiles.push(
                div()
                    .id("fav-add")
                    .flex_1()
                    .min_w_0()
                    .h(FAVORITE_TILE_HEIGHT)
                    .rounded(px(10.))
                    .border_1()
                    .border_dashed()
                    .border_color(edge)
                    .flex()
                    .items_center()
                    .justify_center()
                    .text_color(theme.text_faint)
                    .cursor_pointer()
                    .hover(|s| s.bg(theme.row_hover).text_color(theme.text_muted))
                    .active(|s| s.opacity(0.7))
                    .child(Icon::new(IconName::Plus).small())
                    .tooltip_text("Add Current Tab to Favorites")
                    .on_click(cx.listener(|this, _, window, cx| {
                        if let Some(id) = this.workspace.active_tab_id() {
                            this.add_favorite(id, window, cx);
                        }
                    }))
                    .into_any_element(),
            );
        }

        // Fixed columns: the last row is padded so every tile keeps its width.
        let mut rows: Vec<AnyElement> = Vec::with_capacity(tiles.len().div_ceil(columns));
        let mut tiles = tiles.into_iter().peekable();
        while tiles.peek().is_some() {
            let row: Vec<AnyElement> = tiles.by_ref().take(columns).collect();
            let padding = columns - row.len();
            rows.push(
                h_flex()
                    .gap(FAVORITE_GAP)
                    .children(row)
                    .children((0..padding).map(|_| div().flex_1().min_w_0()))
                    .into_any_element(),
            );
        }

        v_flex()
            .id("favorites")
            .pt(px(2.))
            .pb(px(10.))
            .gap(FAVORITE_GAP)
            .rounded(px(12.))
            .drag_over::<DraggedTab>(move |s, _, _, _| s.bg(theme.accent_soft))
            .on_drop(cx.listener(|this, dragged: &DraggedTab, window, cx| {
                this.add_favorite(dragged.id, window, cx);
            }))
            .children(rows)
            .into_any_element()
    }

    fn render_space_header(&self, menu: &MenuContext, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let space = self.workspace.active_space();
        let space_id = space.id;
        let button_menu = menu.this.clone();
        let row_menu = menu.this.clone();
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
                IconButton::new("space-menu", IconName::Ellipsis)
                    .context_menu(move |menu, _, _| space_menu(menu, &button_menu, space_id)),
            )
            .context_menu(move |menu, _, _| space_menu(menu, &row_menu, space_id))
    }

    fn render_tab_rows(
        &self,
        menu: &MenuContext,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Vec<AnyElement> {
        let space = self.workspace.active_space();
        let rows = space.strip.rows(space.active_tab);
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
            out.push(match row {
                Row::Tab { id, group, .. } => self.render_tab_row(id, group, menu, window, cx),
                Row::Group { id, .. } => self.render_group_row(id, menu, cx),
            });
        }
        if !divider_done {
            out.push(self.render_new_tab_divider(has_pinned, cx));
        }
        if space.strip.is_empty() {
            out.push(
                EmptyState::new(
                    "Tabs you open in this space appear here. Drag tabs above the line to pin them.",
                )
                .compact()
                .px(px(8.))
                .py(px(10.))
                .text_xs()
                .into_any_element(),
            );
        }
        out
    }

    /// The pinned/unpinned boundary (a drop target) and the New Tab row.
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
                ListItem::new("new-tab-row")
                    .muted(true)
                    .leading(Icon::new(IconName::Plus).small())
                    .title("New Tab")
                    .on_click(|_, window, cx| {
                        window.dispatch_action(Box::new(actions::NewTab), cx);
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
        let Some(tab) = self.tab_view(id, cx) else {
            return div().into_any_element();
        };
        let (active, pinned) = (tab.active, tab.pinned);
        // Pinned tabs and tabs in folders are kept when "closed".
        let saved = pinned || group.is_some();
        let menu = menu.clone();
        ListItem::new(SharedString::from(format!("tab-{id}")))
            .group("tab-row")
            .muted(true)
            .selected(active)
            .pl(if group.is_some() { px(22.) } else { px(8.) })
            .pr(px(4.))
            .leading(
                div()
                    .when(tab.asleep && !active && !pinned, |el| el.opacity(0.65))
                    .child(
                        Favicon::new(tab.title.clone())
                            .url(tab.favicon.as_deref())
                            .loading(tab.loading),
                    ),
            )
            .title(tab.title.clone())
            .when(active, |el| el.title_weight(FontWeight::MEDIUM))
            .child(
                IconButton::new(
                    SharedString::from(format!("close-{id}")),
                    if saved { IconName::Minus } else { IconName::X },
                )
                .xsmall()
                .reveal_on_hover("tab-row")
                .force_visible(active)
                .text_color(theme.text_faint)
                .tooltip(if saved { "Unload Tab" } else { "Close Tab" })
                .on_click(cx.listener(move |this, _: &ClickEvent, window, cx| {
                    cx.stop_propagation();
                    this.close_or_unload_tab(id, window, cx);
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
                    this.close_or_unload_tab(id, window, cx);
                }
            }))
            .on_drag(tab.drag(), |dragged, _, _, cx| cx.new(|_| dragged.clone()))
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
        let space_id = space.id;
        let drag = DraggedGroup {
            id,
            space: space_id,
            name: SharedString::from(group.name.clone()),
        };
        let menu = menu.clone();
        // Same height, icon size and text as a tab row.
        ListItem::new(SharedString::from(format!("group-{id}")))
            .muted(true)
            .leading(
                h_flex()
                    .gap(px(8.))
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
                        div().text_color(CurioTheme::swatch(group.color)).child(
                            Icon::new(if collapsed {
                                IconName::Folder
                            } else {
                                IconName::FolderOpen
                            })
                            .size(Favicon::DEFAULT_SIZE),
                        ),
                    ),
            )
            .map(
                |el| match self.folder_rename.as_ref().filter(|r| r.group == id) {
                    // Editing the name: the field replaces the title. Mouse
                    // downs stay in the field so they don't fold or drag.
                    Some(rename) => el.child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
                            .child(Input::new(&rename.input).small().appearance(false).px_0()),
                    ),
                    None => el.title(group.name.clone()),
                },
            )
            .when(collapsed, |el| {
                el.child(
                    div()
                        .text_xs()
                        .text_color(theme.text_faint)
                        .child(SharedString::from(group.tabs.len().to_string())),
                )
            })
            .on_click(cx.listener(move |this, event: &ClickEvent, window, cx| {
                // The first click of a double-click already folded or
                // unfolded the folder, so the second puts that back.
                this.set_group_collapsed(space_id, id, !collapsed, cx);
                if event.click_count() >= 2 {
                    this.rename_group(space_id, id, window, cx);
                }
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
                let this = menu.this.clone();
                // Like Arc: one dot per space in the color picked for it; the
                // active space's dot is larger and solid.
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
                        ColorDot::new(CurioTheme::gradient_swatch(space.gradient))
                            .diameter(px(if is_active { 8. } else { 6. })),
                    )
                    .tooltip_text(space.name.clone())
                    .on_click(
                        cx.listener(move |this, _, window, cx| this.switch_space(id, window, cx)),
                    )
                    .drag_over::<DraggedTab>(move |s, _, _, _| s.bg(theme.accent_soft))
                    .on_drop(cx.listener(move |this, dragged: &DraggedTab, window, cx| {
                        this.move_tab_to_space(dragged.id, id, window, cx);
                    }))
                    .on_drop(
                        cx.listener(move |this, dragged: &DraggedGroup, window, cx| {
                            this.move_group_to_space(dragged.id, dragged.space, id, window, cx);
                        }),
                    )
                    .context_menu(move |menu, _, _| space_menu(menu, &this, id))
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
                IconButton::new("library", IconName::ArrowRight)
                    .tooltip("Library")
                    .action(actions::ToggleLibrary)
                    .when(downloads_active, |el| el.text_color(theme.accent_text)),
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
                IconButton::new("new-space", IconName::Plus)
                    .tooltip("New Space")
                    .action(actions::NewSpace),
            )
            .child(
                IconButton::new("settings", IconName::Settings)
                    .tooltip("Settings")
                    .action(actions::OpenSettings),
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

    pub(crate) fn move_group_to_space(
        &mut self,
        group: GroupId,
        from: SpaceId,
        to: SpaceId,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.workspace.move_group_to_space(group, from, to) {
            self.sync_active_tab(window, cx);
            self.schedule_save(cx);
        }
    }

    /// Starts editing a folder's name in place in the sidebar. Enter or
    /// clicking away saves; Escape cancels.
    pub(crate) fn rename_group(
        &mut self,
        space: SpaceId,
        group: GroupId,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        // Folders only show in the vertical sidebar.
        if self.layout(cx) == TabLayout::Horizontal {
            return;
        }
        self.commit_folder_rename(cx);
        let Some(current) = self
            .workspace
            .space(space)
            .and_then(|s| s.strip.group(group))
            .map(|g| g.name.clone())
        else {
            return;
        };
        let input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Folder name")
                .default_value(current)
        });
        input.update(cx, |input, cx| {
            input.focus(window, cx);
            input.select_all(window, cx);
        });
        let events =
            cx.subscribe_in(
                &input,
                window,
                |this, _, event: &InputEvent, window, cx| match event {
                    InputEvent::PressEnter { .. } => {
                        this.commit_folder_rename(cx);
                        window.focus(&this.focus_handle, cx);
                    }
                    InputEvent::Blur => this.commit_folder_rename(cx),
                    InputEvent::Change | InputEvent::Focus => {}
                },
            );
        self.folder_rename = Some(FolderRename {
            space,
            group,
            input,
            _events: events,
        });
        cx.notify();
    }

    /// Saves the folder name being edited. A blank name keeps the old one.
    pub(crate) fn commit_folder_rename(&mut self, cx: &mut Context<Self>) {
        let Some(rename) = self.folder_rename.take() else {
            return;
        };
        let name = rename.input.read(cx).value().to_string();
        if let Some(space) = self.workspace.space_mut(rename.space)
            && space.strip.rename_group(rename.group, &name)
        {
            self.schedule_save(cx);
        }
        cx.notify();
    }

    /// Stops editing a folder name without saving it.
    pub(crate) fn cancel_folder_rename(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.folder_rename.take().is_some() {
            window.focus(&self.focus_handle, cx);
            cx.notify();
        }
    }

    /// Folds or unfolds a tab group.
    pub(crate) fn set_group_collapsed(
        &mut self,
        space: SpaceId,
        group: GroupId,
        collapsed: bool,
        cx: &mut Context<Self>,
    ) {
        if let Some(space) = self.workspace.space_mut(space) {
            space.strip.set_group_collapsed(group, collapsed);
        }
        self.schedule_save(cx);
        cx.notify();
    }

    pub(crate) fn unload_tab(&mut self, id: TabId, window: &mut Window, cx: &mut Context<Self>) {
        // Pinned tabs and tabs in folders are kept; "closing" them unloads
        // the page and resets it to its home URL instead.
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

    /// Closes a tab, or unloads it when it is pinned.
    pub(crate) fn close_or_unload_tab(
        &mut self,
        id: TabId,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let saved = self
            .workspace
            .space_of_tab(id)
            .and_then(|space| self.workspace.space(space))
            .is_some_and(|space| space.strip.is_saved(id));
        if saved {
            self.unload_tab(id, window, cx);
        } else {
            self.close_tab(id, window, cx);
        }
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

    /// Opens the assistant on `space`, comparing its tabs.
    fn ask_about_space(&mut self, space: SpaceId, window: &mut Window, cx: &mut Context<Self>) {
        self.switch_space(space, window, cx);
        self.show_ai(window, cx);
        self.ai_panel.update(cx, |panel, cx| {
            panel.quick_action(&curio_ai::QuickAction::CompareTabs, window, cx);
        });
    }

    /// Closes every unpinned tab of the active space except `keep`.
    fn close_other_tabs(&mut self, keep: TabId, window: &mut Window, cx: &mut Context<Self>) {
        let others: Vec<TabId> = self
            .workspace
            .active_space()
            .strip
            .items(Section::Unpinned)
            .iter()
            .filter_map(|item| match item {
                Item::Tab(t) if *t != keep => Some(*t),
                _ => None,
            })
            .collect();
        for other in others {
            self.close_tab(other, window, cx);
        }
    }

    /// Takes a tab out of its group, placing it right after the group.
    fn remove_tab_from_group(&mut self, id: TabId, window: &mut Window, cx: &mut Context<Self>) {
        let group = self
            .workspace
            .active_space()
            .strip
            .location_of(id)
            .and_then(|l| l.group);
        if let Some(group) = group {
            self.drop_tab(id, Placement::AfterGroup(group), window, cx);
        }
    }

    /// Deletes a group together with its tabs.
    fn close_group(
        &mut self,
        space: SpaceId,
        group: GroupId,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let closed: Vec<TabId> = self
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
            self.release_tab(id);
        }
        if let Some(space) = self.workspace.space_mut(space)
            && space.active_tab.is_some_and(|t| !space.strip.contains(t))
        {
            space.active_tab = space.strip.ordered_tab_ids().first().copied();
        }
        self.sync_active_tab(window, cx);
        self.schedule_save(cx);
    }

    /// Dissolves a group, keeping its tabs in place.
    fn ungroup(&mut self, space: SpaceId, group: GroupId, cx: &mut Context<Self>) {
        if let Some(space) = self.workspace.space_mut(space) {
            space.strip.delete_group(group, true);
        }
        self.schedule_save(cx);
        cx.notify();
    }

    fn set_group_color(
        &mut self,
        space: SpaceId,
        group: GroupId,
        color: curio_core::AccentColor,
        cx: &mut Context<Self>,
    ) {
        if let Some(space) = self.workspace.space_mut(space) {
            space.strip.set_group_color(group, color);
        }
        self.schedule_save(cx);
        cx.notify();
    }
}

/// "🌿  Name", the label a space has in menus.
fn space_label(icon: &str, name: &str) -> SharedString {
    SharedString::from(format!("{icon}  {name}"))
}

/// The context menu for a space.
pub(crate) fn space_menu(
    menu: PopupMenu,
    this: &WeakEntity<BrowserWindow>,
    space: SpaceId,
) -> PopupMenu {
    menu.item(
        entity_item(this, "Edit Space…", move |this, window, cx| {
            this.edit_space(Some(space), window, cx);
        })
        .icon(IconName::Palette),
    )
    .item(
        entity_item(
            this,
            "Ask Curio About This Space",
            move |this, window, cx| {
                this.ask_about_space(space, window, cx);
            },
        )
        .icon(IconName::Sparkles),
    )
    .separator()
    .item(
        entity_item(this, "Move Left", move |this, _, cx| {
            this.shift_space(space, -1, cx)
        })
        .icon(IconName::ChevronLeft),
    )
    .item(
        entity_item(this, "Move Right", move |this, _, cx| {
            this.shift_space(space, 1, cx)
        })
        .icon(IconName::ChevronRight),
    )
    .separator()
    .item(
        entity_item(this, "Delete Space…", move |this, window, cx| {
            this.confirm_delete_space(space, window, cx);
        })
        .icon(IconName::Delete),
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
    let this = &ctx.this;
    let saved = pinned || group.is_some();
    let spaces = ctx.spaces.clone();
    let current_space = ctx.current_space;
    let groups = ctx.groups.clone();
    let group_this = this.clone();
    let move_this = this.clone();
    let mut menu = menu
        .item(
            entity_item(
                this,
                if pinned { "Unpin Tab" } else { "Pin Tab" },
                move |this, _, cx| {
                    this.toggle_pin(id, cx);
                },
            )
            .icon(IconName::Star),
        )
        .item(
            entity_item(this, "Add to Favorites", move |this, window, cx| {
                this.add_favorite(id, window, cx);
            })
            .icon(IconName::Heart),
        )
        .item(
            entity_item(this, "Duplicate Tab", move |this, window, cx| {
                if this.workspace.duplicate_tab(id).is_some() {
                    this.sync_active_tab(window, cx);
                    this.schedule_save(cx);
                }
            })
            .icon(IconName::Copy),
        )
        .item(
            entity_item(this, "Copy Link", move |this, _, cx| {
                if let Some(tab) = this.workspace.tab(id) {
                    cx.write_to_clipboard(gpui_kit::ClipboardItem::new_string(tab.url.clone()));
                }
            })
            .icon(IconName::Link),
        )
        .item(
            entity_item(this, "Ask Curio About This Tab", move |this, window, cx| {
                this.attach_tab_to_ai(id, window, cx);
            })
            .icon(IconName::Sparkles),
        )
        .separator()
        .submenu("Move to Folder", window, cx, move |mut menu, _, _| {
            menu = menu.item(
                entity_item(&group_this, "New Folder…", move |this, window, cx| {
                    this.new_group_with(vec![id], window, cx);
                })
                .icon(IconName::FolderPlus),
            );
            if !groups.is_empty() {
                menu = menu.separator();
            }
            for (gid, name) in &groups {
                let gid = *gid;
                menu = menu.item(
                    entity_item(&group_this, name.clone(), move |this, window, cx| {
                        this.drop_tab(id, Placement::InGroup(gid, None), window, cx);
                    })
                    .icon(IconName::Folder)
                    .checked(group == Some(gid)),
                );
            }
            menu
        });
    if group.is_some() {
        menu = menu.item(
            entity_item(this, "Remove from Folder", move |this, window, cx| {
                this.remove_tab_from_group(id, window, cx);
            })
            .icon(IconName::FolderMinus),
        );
    }
    menu.submenu("Move to Space", window, cx, move |mut menu, _, _| {
        for (sid, name, icon) in spaces.iter().filter(|(sid, ..)| *sid != current_space) {
            let sid = *sid;
            menu = menu.item(entity_item(
                &move_this,
                space_label(icon, name),
                move |this, window, cx| this.move_tab_to_space(id, sid, window, cx),
            ));
        }
        menu
    })
    .separator()
    .item(
        entity_item(
            this,
            if saved { "Unload Tab" } else { "Close Tab" },
            move |this, window, cx| {
                this.close_or_unload_tab(id, window, cx);
            },
        )
        .icon(IconName::X),
    )
    .when(saved, |menu| {
        menu.item(
            entity_item(this, "Delete Tab", move |this, window, cx| {
                this.close_tab(id, window, cx);
            })
            .icon(IconName::Delete),
        )
    })
    .item(
        entity_item(this, "Close Other Tabs", move |this, window, cx| {
            this.close_other_tabs(id, window, cx);
        })
        .icon(IconName::CircleX),
    )
}

/// The context menu for a folder.
fn group_menu(
    menu: PopupMenu,
    ctx: &MenuContext,
    space: SpaceId,
    group: GroupId,
    window: &mut Window,
    cx: &mut Context<PopupMenu>,
) -> PopupMenu {
    let this = &ctx.this;
    let spaces = ctx.spaces.clone();
    let color_this = this.clone();
    let move_this = this.clone();
    menu.item(
        entity_item(this, "Rename Folder", move |this, window, cx| {
            this.rename_group(space, group, window, cx);
        })
        .icon(IconName::Pencil),
    )
    .submenu("Color", window, cx, move |mut menu, _, _| {
        for color in curio_core::AccentColor::ALL {
            menu = menu.item(
                entity_item(&color_this, color.label(), move |this, _, cx| {
                    this.set_group_color(space, group, color, cx);
                })
                .icon(Icon::new(IconName::CircleSmall).text_color(CurioTheme::swatch(color))),
            );
        }
        menu
    })
    .submenu("Move Folder to Space", window, cx, move |mut menu, _, _| {
        for (sid, name, icon) in spaces.iter().filter(|(sid, ..)| *sid != space) {
            let sid = *sid;
            menu = menu.item(entity_item(
                &move_this,
                space_label(icon, name),
                move |this, window, cx| this.move_group_to_space(group, space, sid, window, cx),
            ));
        }
        menu
    })
    .separator()
    .item(
        entity_item(this, "Remove Folder, Keep Tabs", move |this, _, cx| {
            this.ungroup(space, group, cx)
        })
        .icon(IconName::FolderMinus),
    )
    .item(
        entity_item(this, "Delete Folder and Tabs", move |this, window, cx| {
            this.close_group(space, group, window, cx);
        })
        .icon(IconName::Delete),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn favorites_fit_four_across_unless_the_sidebar_is_narrow() {
        // Default width and wider: four.
        assert_eq!(favorite_columns(px(260.)), 4);
        assert_eq!(favorite_columns(px(420.)), 4);
        // Narrowest sidebar: three, so tiles stay at least 48px wide.
        assert_eq!(favorite_columns(px(200.)), 3);
        // The switch happens where four 48px tiles and their gaps stop fitting.
        assert_eq!(favorite_columns(px(230.)), 4);
        assert_eq!(favorite_columns(px(229.)), 3);
    }
}
