//! The card that follows the pointer during a drag.

use gpui_kit::component::{StyledExt as _, h_flex};
use gpui_kit::{
    AnyElement, App, IntoElement, ParentElement as _, RenderOnce, SharedString, StyleRefinement,
    Styled, Window, div, px,
};

use super::style::CurioStyled as _;
use crate::theme::CurioTheme;

/// A floating card with an icon and a title, shown while dragging.
#[derive(IntoElement)]
pub struct DragPreview {
    style: StyleRefinement,
    leading: AnyElement,
    title: SharedString,
}

impl DragPreview {
    /// A 220px card with `leading` before `title`; set `.w(...)` to resize.
    #[must_use]
    pub fn new(leading: impl IntoElement, title: impl Into<SharedString>) -> Self {
        Self {
            style: StyleRefinement::default(),
            leading: leading.into_any_element(),
            title: title.into(),
        }
    }
}

impl Styled for DragPreview {
    fn style(&mut self) -> &mut StyleRefinement {
        &mut self.style
    }
}

impl RenderOnce for DragPreview {
    fn render(self, _: &mut Window, cx: &mut App) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        h_flex()
            .gap(px(8.))
            .h(px(32.))
            .px(px(10.))
            .w(px(220.))
            .rounded(px(8.))
            .surface(&theme)
            .shadow_lg()
            .text_sm()
            .text_color(theme.text)
            .child(self.leading)
            .child(div().flex_1().truncate().child(self.title))
            .refine_style(&self.style)
    }
}
