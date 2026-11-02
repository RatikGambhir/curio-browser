//! A solid colored circle.

use gpui_kit::component::StyledExt as _;
use gpui_kit::{
    App, Hsla, IntoElement, Pixels, RenderOnce, StyleRefinement, Styled, Window, div, px,
};

/// A small colored circle marking a space or group color.
#[derive(IntoElement)]
pub struct ColorDot {
    style: StyleRefinement,
    color: Hsla,
    size: Pixels,
}

impl ColorDot {
    /// An 8px dot in `color`.
    #[must_use]
    pub fn new(color: Hsla) -> Self {
        Self {
            style: StyleRefinement::default(),
            color,
            size: px(8.),
        }
    }

    /// The diameter.
    #[must_use]
    pub fn diameter(mut self, size: Pixels) -> Self {
        self.size = size;
        self
    }
}

impl Styled for ColorDot {
    fn style(&mut self) -> &mut StyleRefinement {
        &mut self.style
    }
}

impl RenderOnce for ColorDot {
    fn render(self, _: &mut Window, _: &mut App) -> impl IntoElement {
        div()
            .flex_shrink_0()
            .size(self.size)
            .rounded_full()
            .bg(self.color)
            .refine_style(&self.style)
    }
}
