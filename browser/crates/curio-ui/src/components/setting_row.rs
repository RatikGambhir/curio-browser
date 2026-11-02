//! A labeled control in a settings form.

use gpui_kit::component::{StyledExt as _, h_flex, v_flex};
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{
    AnyElement, App, FontWeight, IntoElement, ParentElement as _, RenderOnce, SharedString,
    StyleRefinement, Styled, Window, div, px,
};

use crate::theme::CurioTheme;

/// A settings row: a label with an optional description on the left and its
/// control on the right, over a divider.
#[derive(IntoElement)]
pub struct SettingRow {
    style: StyleRefinement,
    label: SharedString,
    description: Option<SharedString>,
    control: AnyElement,
}

impl SettingRow {
    /// A row labeled `label` holding `control`.
    #[must_use]
    pub fn new(label: impl Into<SharedString>, control: impl IntoElement) -> Self {
        Self {
            style: StyleRefinement::default(),
            label: label.into(),
            description: None,
            control: control.into_any_element(),
        }
    }

    /// Faint help text under the label.
    #[must_use]
    pub fn description(mut self, description: impl Into<SharedString>) -> Self {
        self.description = Some(description.into());
        self
    }
}

impl Styled for SettingRow {
    fn style(&mut self) -> &mut StyleRefinement {
        &mut self.style
    }
}

impl RenderOnce for SettingRow {
    fn render(self, _: &mut Window, cx: &mut App) -> impl IntoElement {
        let theme = CurioTheme::get(cx);
        h_flex()
            .w_full()
            .py(px(10.))
            .gap(px(16.))
            .border_b_1()
            .border_color(theme.divider)
            .child(
                v_flex()
                    .flex_1()
                    .min_w_0()
                    .gap(px(2.))
                    .child(
                        div()
                            .text_sm()
                            .font_weight(FontWeight::MEDIUM)
                            .text_color(theme.text)
                            .child(self.label),
                    )
                    .when_some(self.description, |el, description| {
                        el.child(
                            div()
                                .text_xs()
                                .text_color(theme.text_faint)
                                .child(description),
                        )
                    }),
            )
            .child(div().flex_shrink_0().child(self.control))
            .refine_style(&self.style)
    }
}
