//! A hairline separator.

use gpui_kit::component::StyledExt as _;
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{App, IntoElement, RenderOnce, StyleRefinement, Styled, Window, div, px};

use crate::theme::CurioTheme;

/// A 1px line in the theme's divider color.
#[derive(IntoElement)]
pub struct Divider {
    style: StyleRefinement,
    vertical: bool,
}

impl Divider {
    /// A full-width horizontal line.
    #[must_use]
    pub fn horizontal() -> Self {
        Self {
            style: StyleRefinement::default(),
            vertical: false,
        }
    }

    /// An 18px vertical line, for separating groups in a toolbar.
    #[must_use]
    pub fn vertical() -> Self {
        Self {
            style: StyleRefinement::default(),
            vertical: true,
        }
    }
}

impl Styled for Divider {
    fn style(&mut self) -> &mut StyleRefinement {
        &mut self.style
    }
}

impl RenderOnce for Divider {
    fn render(self, _: &mut Window, cx: &mut App) -> impl IntoElement {
        let color = CurioTheme::get(cx).divider;
        div()
            .flex_shrink_0()
            .bg(color)
            .map(|el| {
                if self.vertical {
                    el.w(px(1.)).h(px(18.))
                } else {
                    el.h(px(1.)).w_full()
                }
            })
            .refine_style(&self.style)
    }
}
