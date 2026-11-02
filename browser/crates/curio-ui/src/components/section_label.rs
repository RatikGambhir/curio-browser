//! A small heading over a group of items.

use gpui_kit::component::StyledExt as _;
use gpui_kit::{
    App, FontWeight, IntoElement, ParentElement as _, RenderOnce, SharedString, StyleRefinement,
    Styled, Window, div,
};

use crate::theme::CurioTheme;

/// A faint, small, semibold label naming a section or a form field.
#[derive(IntoElement)]
pub struct SectionLabel {
    style: StyleRefinement,
    text: SharedString,
}

impl SectionLabel {
    /// A label reading `text`.
    #[must_use]
    pub fn new(text: impl Into<SharedString>) -> Self {
        Self {
            style: StyleRefinement::default(),
            text: text.into(),
        }
    }
}

impl Styled for SectionLabel {
    fn style(&mut self) -> &mut StyleRefinement {
        &mut self.style
    }
}

impl RenderOnce for SectionLabel {
    fn render(self, _: &mut Window, cx: &mut App) -> impl IntoElement {
        let faint = CurioTheme::get(cx).text_faint;
        div()
            .text_xs()
            .font_weight(FontWeight::SEMIBOLD)
            .text_color(faint)
            .child(self.text)
            .refine_style(&self.style)
    }
}
