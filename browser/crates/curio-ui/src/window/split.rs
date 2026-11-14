//! Split view: two to four tabs shown side by side, like Arc and Dia.
//!
//! The split itself lives in the space's tab strip ([`TabSplit`]), next to
//! the tabs (and inside the folder) it was made from, so it is saved with
//! the space. This module draws the panes, the dividers between them and
//! the drop zones for dragging a tab onto the page, and runs the split
//! commands. The workspace's active tab is the focused pane.

use curio_core::{SplitId, SplitOrientation, Tab, TabId, TabSplit};
use curio_tabs::Placement;
use gpui_kit::assets::IconName;
use gpui_kit::component::WindowExt as _;
use gpui_kit::component::{Sizable as _, h_flex};
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{
    AnyElement, ClickEvent, Context, InteractiveElement as _, IntoElement, MouseButton,
    ParentElement as _, Pixels, Point, SharedString, StatefulInteractiveElement as _, Styled as _,
    Window, canvas, deferred, div, px,
};

use super::{BrowserWindow, DraggedTab, Resize};
use crate::command_bar::CommandMode;
use crate::components::prelude::*;
use crate::theme::{CurioTheme, metrics};

/// The gap between panes, which is also the divider's grab area.
pub(super) const SPLIT_GAP: Pixels = metrics::PANEL_GAP;

/// How a page card is shown.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum PaneRole {
    /// The only page in view.
    Single,
    /// One pane of a split view.
    Split {
        focused: bool,
        /// The leftmost (or topmost) pane, which makes room for the
        /// traffic lights when the sidebar is hidden.
        first: bool,
    },
}

impl PaneRole {
    pub fn focused(self) -> bool {
        match self {
            Self::Single => true,
            Self::Split { focused, .. } => focused,
        }
    }
}

/// Which side of the page a dragged tab is dropped on.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum DropSide {
    Before,
    After,
}

impl BrowserWindow {
    /// The split view of the active tab, if it's in one. Cloned so render
    /// code can hold it while borrowing `self` mutably; it's at most four
    /// ids and sizes.
    pub(crate) fn visible_split(&self) -> Option<TabSplit> {
        let active = self.workspace.active_tab_id()?;
        self.workspace
            .active_space()
            .strip
            .split_of(active)
            .cloned()
    }

    /// The tabs whose pages are on screen: the active tab, or every pane of
    /// its split view.
    pub(crate) fn visible_tab_ids(&self) -> Vec<TabId> {
        match (self.visible_split(), self.workspace.active_tab_id()) {
            (Some(split), _) => split.tabs,
            (None, Some(active)) => vec![active],
            (None, None) => Vec::new(),
        }
    }

    // ----- Commands -------------------------------------------------------

    /// "Split View": adds a new tab beside the active one (or as another
    /// pane of its split) and opens the command bar to pick its page.
    pub(crate) fn split_view(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(active) = self.workspace.active_tab_id() else {
            self.open_command_bar(CommandMode::NewTab, window, cx);
            return;
        };
        let Some(space) = self.workspace.space_of_tab(active) else {
            window.push_notification("Favorites can’t be shown in a split view", cx);
            return;
        };
        let Some(strip) = self.workspace.space_mut(space).map(|s| &mut s.strip) else {
            return;
        };
        let existing = strip.split_of(active).map(|split| {
            let index = split.tabs.iter().position(|t| *t == active).unwrap_or(0);
            (split.id, index, split.is_full())
        });
        if existing.is_some_and(|(_, _, full)| full) {
            window.push_notification(full_message(), cx);
            return;
        }
        let new_tab = strip.insert(Tab::default(), Placement::AfterTab(active));
        let joined = match existing {
            Some((split, index, _)) => strip.add_to_split(split, new_tab, index + 1),
            None => strip
                .create_split(&[active, new_tab], SplitOrientation::Horizontal)
                .is_some(),
        };
        if !joined {
            tracing::warn!("could not make a split view");
        }
        self.activate_tab(new_tab, window, cx);
        self.open_command_bar(CommandMode::NewTab, window, cx);
    }

    /// Shows `tab` beside the active tab: before or after it, in a new split
    /// or as another pane of the active tab's split. The split stays where
    /// the active tab is (its space and folder), and `tab` becomes active.
    pub(crate) fn split_with(
        &mut self,
        tab: TabId,
        side: DropSide,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(active) = self.workspace.active_tab_id().filter(|a| *a != tab) else {
            return;
        };
        let Some(space) = self.workspace.space_of_tab(active) else {
            // The active tab is a favorite: just show the tab.
            self.activate_tab(tab, window, cx);
            return;
        };
        match self.workspace.space_of_tab(tab) {
            None => {
                window.push_notification("Favorites can’t be shown in a split view", cx);
                return;
            }
            Some(other) if other != space => {
                self.workspace.move_tab_to_space(tab, space);
            }
            Some(_) => {}
        }
        let Some(strip) = self.workspace.space_mut(space).map(|s| &mut s.strip) else {
            return;
        };
        let target = strip.split_of(active).map(|split| {
            let index = split.tabs.iter().position(|t| *t == active).unwrap_or(0);
            (split.id, index, split.is_full(), split.contains(tab))
        });
        let ok = match target {
            // Already a pane: nothing to change but the focus.
            Some((_, _, _, true)) => true,
            Some((_, _, true, false)) => {
                window.push_notification(full_message(), cx);
                return;
            }
            Some((split, index, false, false)) => {
                let at = match side {
                    DropSide::Before => index,
                    DropSide::After => index + 1,
                };
                strip.add_to_split(split, tab, at)
            }
            None => {
                // Out of any other split, then right beside the active tab
                // so the new split forms where the active tab is.
                strip.remove_from_split(tab);
                let (placement, order) = match side {
                    DropSide::Before => (Placement::BeforeTab(active), [tab, active]),
                    DropSide::After => (Placement::AfterTab(active), [active, tab]),
                };
                strip.move_tab(tab, placement);
                strip
                    .create_split(&order, SplitOrientation::Horizontal)
                    .is_some()
            }
        };
        if !ok {
            tracing::warn!(%tab, "could not add the tab to the split view");
        }
        self.activate_tab(tab, window, cx);
        self.focus_page_or_window(window, cx);
    }

    /// "Separate Split View": the active tab's split becomes ordinary tabs.
    pub(crate) fn separate_split_view(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if let Some(split) = self.visible_split() {
            self.dissolve_split(split.id, window, cx);
        }
    }

    /// Dissolves a split of the active space, keeping its tabs in place.
    pub(crate) fn dissolve_split(
        &mut self,
        split: SplitId,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self
            .workspace
            .active_space_mut()
            .strip
            .dissolve_split(split)
        {
            self.sync_active_tab(window, cx);
            self.schedule_save(cx);
        }
    }

    /// Takes a tab out of its split, putting it right after the split.
    pub(crate) fn remove_tab_from_split(
        &mut self,
        tab: TabId,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(space) = self.workspace.space_of_tab(tab) else {
            return;
        };
        if self
            .workspace
            .space_mut(space)
            .is_some_and(|s| s.strip.remove_from_split(tab))
        {
            self.sync_active_tab(window, cx);
            self.schedule_save(cx);
        }
    }

    /// Switches a split between side by side and stacked.
    pub(crate) fn flip_split(&mut self, split: SplitId, cx: &mut Context<Self>) {
        if self.workspace.active_space_mut().strip.flip_split(split) {
            self.schedule_save(cx);
            cx.notify();
        }
    }

    /// Gives every pane of a split the same room.
    pub(crate) fn equalize_split(&mut self, split: SplitId, cx: &mut Context<Self>) {
        if self
            .workspace
            .active_space_mut()
            .strip
            .equalize_split(split)
        {
            self.schedule_save(cx);
            cx.notify();
        }
    }

    /// Follows the mouse while a divider is dragged.
    pub(super) fn drag_split_divider(
        &mut self,
        split: SplitId,
        divider: usize,
        position: Point<Pixels>,
    ) -> bool {
        let bounds = self.split_bounds.get();
        let strip = &mut self.workspace.active_space_mut().strip;
        let Some(current) = strip.split(split) else {
            return false;
        };
        let horizontal = current.orientation == SplitOrientation::Horizontal;
        let (pointer, origin, total) = if horizontal {
            (position.x, bounds.origin.x, bounds.size.width)
        } else {
            (position.y, bounds.origin.y, bounds.size.height)
        };
        let fraction = divider_fraction(
            f32::from(pointer - origin),
            f32::from(total),
            f32::from(SPLIT_GAP),
            current.tabs.len(),
            divider,
        );
        let Some(fraction) = fraction else {
            return false;
        };
        let boundary: f32 = current.sizes.iter().take(divider + 1).sum();
        strip.resize_split(split, divider, fraction - boundary)
    }

    // ----- Rendering ------------------------------------------------------

    /// The panes of a split view with dividers between them.
    pub(super) fn render_split(
        &mut self,
        split: &TabSplit,
        page_bar: bool,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let horizontal = split.orientation == SplitOrientation::Horizontal;
        let active = self.workspace.active_tab_id();
        let bounds = self.split_bounds.clone();
        let mut panes = div()
            .id("split-view")
            .relative()
            .size_full()
            .flex()
            .when(horizontal, |el| el.flex_row())
            .when(!horizontal, |el| el.flex_col())
            // Records where the split is, so dividers can follow the mouse.
            .child(
                canvas(move |b, _, _| bounds.set(b), |_, (), _, _| {})
                    .absolute()
                    .size_full(),
            );
        for (index, (tab, size)) in split.tabs.iter().zip(&split.sizes).enumerate() {
            if index > 0 {
                panes = panes.child(self.render_split_divider(split.id, index - 1, horizontal, cx));
            }
            let role = PaneRole::Split {
                focused: Some(*tab) == active,
                first: index == 0,
            };
            panes = panes.child(
                div()
                    .id(("split-pane", index))
                    .flex_basis(px(0.))
                    .flex_grow(*size)
                    .flex_shrink_0()
                    .min_w_0()
                    .min_h_0()
                    .when(horizontal, |el| el.h_full())
                    .when(!horizontal, |el| el.w_full())
                    .child(self.render_page_card(Some(*tab), role, page_bar, window, cx)),
            );
        }
        panes.into_any_element()
    }

    fn render_split_divider(
        &self,
        split: SplitId,
        divider: usize,
        horizontal: bool,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let dragging = self.resizing == Some(Resize::SplitDivider(split, divider));
        let line = div()
            .rounded_full()
            .when(horizontal, |el| el.w(px(2.)).h(px(36.)))
            .when(!horizontal, |el| el.h(px(2.)).w(px(36.)))
            .when(dragging, |el| el.bg(theme.accent))
            .group_hover("split-divider", |s| s.bg(theme.text_faint));
        div()
            .id(("split-divider", divider))
            .group("split-divider")
            .flex_shrink_0()
            .flex()
            .items_center()
            .justify_center()
            .when(horizontal, |el| {
                el.w(SPLIT_GAP).h_full().cursor_col_resize()
            })
            .when(!horizontal, |el| {
                el.h(SPLIT_GAP).w_full().cursor_row_resize()
            })
            .child(line)
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(move |this, _, _, cx| {
                    this.resizing = Some(Resize::SplitDivider(split, divider));
                    cx.stop_propagation();
                    cx.notify();
                }),
            )
            .on_click(cx.listener(move |this, event: &ClickEvent, _, cx| {
                if event.click_count() >= 2 {
                    this.equalize_split(split, cx);
                }
            }))
    }

    /// The top bar of a split pane that isn't focused: its page, and
    /// buttons to take it out of the split or close it. Clicking it focuses
    /// the pane.
    pub(super) fn render_pane_header(
        &self,
        tab: TabId,
        first: bool,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        let (title, favicon, url) = self
            .workspace
            .tab(tab)
            .map(|t| (t.display_title(), t.favicon_url.as_deref(), t.url.as_str()))
            .unwrap_or_default();
        let saved = self.workspace.active_space().strip.is_saved(tab);
        h_flex()
            .id("pane-bar")
            .h(metrics::TOOLBAR_HEIGHT)
            .flex_shrink_0()
            .px(px(10.))
            .gap(px(8.))
            .border_b_1()
            .border_color(theme.divider)
            .text_sm()
            .text_color(theme.text_muted)
            .cursor_pointer()
            .hover(|s| s.text_color(theme.text))
            // The traffic lights sit over the first pane with the sidebar
            // hidden, as they do over the page bar.
            .when(first && self.left_reveal < 1.0, |el| {
                el.child(
                    traffic_lights_spacer(px(16.))
                        .w((metrics::TRAFFIC_LIGHTS_WIDTH - px(16.)) * (1.0 - self.left_reveal)),
                )
            })
            .child(Favicon::new(title.clone()).url(favicon).page_url(url))
            .child(
                div()
                    .flex_1()
                    .min_w_0()
                    .truncate()
                    .child(SharedString::from(title)),
            )
            .child(
                IconButton::new("pane-separate", IconName::Unlink)
                    .xsmall()
                    .tooltip("Remove from Split View")
                    .on_click(cx.listener(move |this, _: &ClickEvent, window, cx| {
                        cx.stop_propagation();
                        this.remove_tab_from_split(tab, window, cx);
                    })),
            )
            .child(
                IconButton::new(
                    "pane-close",
                    if saved { IconName::Minus } else { IconName::X },
                )
                .xsmall()
                .tooltip(if saved { "Unload Tab" } else { "Close Tab" })
                .on_click(cx.listener(move |this, _: &ClickEvent, window, cx| {
                    cx.stop_propagation();
                    this.close_or_unload_tab(tab, window, cx);
                })),
            )
            .on_click(cx.listener(move |this, _, window, cx| {
                this.activate_tab(tab, window, cx);
                this.focus_page_or_window(window, cx);
            }))
            .into_any_element()
    }

    /// While a tab is dragged, the page area's halves take it as a drop:
    /// left opens it before the current page in a split, right after it.
    pub(super) fn render_split_drop_zones(&self, cx: &mut Context<Self>) -> Option<AnyElement> {
        if !cx.has_active_drag() {
            return None;
        }
        // Only a tab of a space can be split with.
        let active = self.workspace.active_tab_id()?;
        self.workspace.space_of_tab(active)?;
        let theme = *CurioTheme::get(cx);
        let zone = |id: &'static str, side: DropSide, cx: &mut Context<Self>| {
            div()
                .id(id)
                .flex_1()
                .h_full()
                .m(px(6.))
                .rounded(metrics::CARD_RADIUS)
                .drag_over::<DraggedTab>(move |s, _, _, _| {
                    s.bg(theme.accent_soft)
                        .border_2()
                        .border_color(theme.accent)
                })
                .on_drop(cx.listener(move |this, dragged: &DraggedTab, window, cx| {
                    this.split_with(dragged.id, side, window, cx);
                }))
        };
        Some(
            deferred(
                h_flex()
                    .absolute()
                    .inset_0()
                    .child(zone("split-drop-before", DropSide::Before, cx))
                    .child(zone("split-drop-after", DropSide::After, cx)),
            )
            .into_any_element(),
        )
    }
}

fn full_message() -> SharedString {
    SharedString::from(format!(
        "A split view shows up to {} tabs",
        TabSplit::MAX_PANES
    ))
}

/// Where the pointer is along a split, as a share of the room the panes
/// have (the split's length less its gaps), measured from the divider's
/// center. `None` when the split has no room.
fn divider_fraction(
    pointer: f32,
    total: f32,
    gap: f32,
    panes: usize,
    divider: usize,
) -> Option<f32> {
    #[allow(clippy::cast_precision_loss)] // At most four panes.
    let gaps = panes.saturating_sub(1) as f32;
    let room = total - gap * gaps;
    if room <= 1.0 || !pointer.is_finite() {
        return None;
    }
    #[allow(clippy::cast_precision_loss)]
    let before = gap * divider as f32 + gap / 2.0;
    Some((pointer - before) / room)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn divider_fraction_ignores_the_gaps() {
        // Two panes in 808px with an 8px gap: 400px each. The divider's
        // center (404px) is halfway.
        let half = divider_fraction(404.0, 808.0, 8.0, 2, 0).expect("room");
        assert!((half - 0.5).abs() < 1e-5);
        // Three panes: the second divider's center after two 200px panes.
        let second = divider_fraction(412.0, 616.0, 8.0, 3, 1).expect("room");
        assert!((second - 2.0 / 3.0).abs() < 1e-5);
        assert_eq!(divider_fraction(10.0, 8.0, 8.0, 2, 0), None);
    }
}
