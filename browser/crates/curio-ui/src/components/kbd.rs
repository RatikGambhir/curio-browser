//! A keyboard shortcut hint.

use gpui_kit::component::StyledExt as _;
use gpui_kit::{
    App, IntoElement, ParentElement as _, RenderOnce, SharedString, StyleRefinement, Styled,
    Window, div, px,
};

use crate::theme::CurioTheme;

/// A key or shortcut drawn as a small keycap, e.g. "⌘T".
#[derive(IntoElement)]
pub struct Kbd {
    style: StyleRefinement,
    keys: SharedString,
}

impl Kbd {
    /// A keycap reading `keys`.
    #[must_use]
    pub fn new(keys: impl Into<SharedString>) -> Self {
        Self {
            style: StyleRefinement::default(),
            keys: keys.into(),
        }
    }
}

impl Styled for Kbd {
    fn style(&mut self) -> &mut StyleRefinement {
        &mut self.style
    }
}

impl RenderOnce for Kbd {
    fn render(self, _: &mut Window, cx: &mut App) -> impl IntoElement {
        let theme = CurioTheme::get(cx);
        div()
            .flex_shrink_0()
            .px(px(5.))
            .py(px(1.))
            .rounded(px(4.))
            .bg(theme.row_hover)
            .text_xs()
            .text_color(theme.text_faint)
            .child(self.keys)
            .refine_style(&self.style)
    }
}
