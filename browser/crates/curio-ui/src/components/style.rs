//! Style recipes and small behaviors shared by every component.
//!
//! These are extension traits rather than components because they decorate
//! an element you already have: a surface look, a tooltip, a window-drag
//! area.

use std::rc::Rc;

use gpui_kit::component::h_flex;
use gpui_kit::component::tooltip::Tooltip;
use gpui_kit::{
    Action, Div, InteractiveElement, MouseButton, Pixels, SharedString, StatefulInteractiveElement,
    Styled, div, px,
};

use crate::theme::{CurioTheme, metrics};

/// Curio's recurring looks, available on any styled element.
pub trait CurioStyled: Styled + Sized {
    /// A floating surface: popovers, banners, drag previews, the command bar.
    /// Add a shadow and radius to taste.
    #[must_use]
    fn surface(self, theme: &CurioTheme) -> Self {
        self.bg(theme.surface_raised)
            .border_1()
            .border_color(theme.surface_border)
    }

    /// The rounded card the page floats on.
    #[must_use]
    fn card(self, theme: &CurioTheme) -> Self {
        self.rounded(metrics::CARD_RADIUS)
            .overflow_hidden()
            .bg(theme.card)
            .border_1()
            .border_color(theme.card_border)
            .shadow_md()
    }

    /// The lifted look of the selected row or tab on the chrome.
    #[must_use]
    fn raised_row(self, theme: &CurioTheme) -> Self {
        self.bg(theme.row_active)
            .text_color(theme.row_active_text)
            .border_1()
            .border_color(theme.row_active_border)
            .shadow_xs()
    }
}

impl<E: Styled> CurioStyled for E {}

/// Tooltips from plain text, optionally showing an action's shortcut.
pub trait TooltipExt: StatefulInteractiveElement + Sized {
    /// Shows `text` on hover.
    #[must_use]
    fn tooltip_text(self, text: impl Into<SharedString>) -> Self {
        let text = text.into();
        self.tooltip(move |window, cx| Tooltip::new(text.clone()).build(window, cx))
    }

    /// Shows `text` on hover together with the shortcut bound to `action`.
    #[must_use]
    fn tooltip_action(self, text: impl Into<SharedString>, action: &dyn Action) -> Self {
        let text = text.into();
        let action: Rc<dyn Action> = Rc::from(action.boxed_clone());
        self.tooltip(move |window, cx| {
            Tooltip::new(text.clone())
                .action(action.as_ref(), None)
                .build(window, cx)
        })
    }
}

impl<E: StatefulInteractiveElement> TooltipExt for E {}

/// Makes an element behave like a title bar.
pub trait WindowDragExt: InteractiveElement + Sized {
    /// Dragging moves the window; double-clicking zooms it, as the system
    /// title bar would.
    #[must_use]
    fn window_drag_area(self) -> Self {
        self.on_mouse_down(MouseButton::Left, |event, window, _| {
            if event.click_count >= 2 {
                window.titlebar_double_click();
            } else {
                window.start_window_move();
            }
        })
    }
}

impl<E: InteractiveElement> WindowDragExt for E {}

/// Empty space reserved for the macOS traffic lights, less `trim` when the
/// surrounding padding already covers part of it.
#[must_use]
pub fn traffic_lights_spacer(trim: Pixels) -> Div {
    div()
        .w(metrics::TRAFFIC_LIGHTS_WIDTH - trim)
        .flex_shrink_0()
}

/// The right-aligned button row at the bottom of a dialog.
#[must_use]
pub fn dialog_footer() -> Div {
    h_flex().w_full().justify_end().gap(px(8.))
}
