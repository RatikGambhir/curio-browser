//! A vertical navigation entry: an icon over a label.

use gpui_kit::assets::IconName;
use gpui_kit::component::{Icon, StyledExt as _, v_flex};
use gpui_kit::{
    App, Div, ElementId, FontWeight, InteractiveElement, Interactivity, IntoElement,
    ParentElement as _, RenderOnce, SharedString, Stateful, StatefulInteractiveElement,
    StyleRefinement, Styled, Window, div, prelude::FluentBuilder as _, px,
};

use super::style::CurioStyled as _;
use crate::theme::CurioTheme;

/// An entry in a narrow navigation rail, like the library's sections.
#[derive(IntoElement)]
pub struct RailItem {
    base: Stateful<Div>,
    style: StyleRefinement,
    icon: IconName,
    label: SharedString,
    selected: bool,
}

impl RailItem {
    /// An entry showing `icon` above `label`.
    #[must_use]
    pub fn new(id: impl Into<ElementId>, icon: IconName, label: impl Into<SharedString>) -> Self {
        Self {
            base: v_flex().id(id),
            style: StyleRefinement::default(),
            icon,
            label: label.into(),
            selected: false,
        }
    }

    /// Marks the entry as the current one.
    #[must_use]
    pub fn selected(mut self, selected: bool) -> Self {
        self.selected = selected;
        self
    }
}

impl Styled for RailItem {
    fn style(&mut self) -> &mut StyleRefinement {
        &mut self.style
    }
}

impl InteractiveElement for RailItem {
    fn interactivity(&mut self) -> &mut Interactivity {
        self.base.interactivity()
    }
}

impl StatefulInteractiveElement for RailItem {}

impl RenderOnce for RailItem {
    fn render(self, _: &mut Window, cx: &mut App) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        self.base
            .w_full()
            .items_center()
            .gap(px(5.))
            .py(px(10.))
            .rounded(px(10.))
            .cursor_pointer()
            .text_xs()
            .font_weight(FontWeight::MEDIUM)
            .map(|el| {
                if self.selected {
                    el.raised_row(&theme)
                } else {
                    el.text_color(theme.text_muted)
                        .hover(|s| s.bg(theme.row_hover).text_color(theme.text))
                }
            })
            .child(
                div()
                    .text_color(theme.accent_text)
                    .child(Icon::new(self.icon).size(px(22.))),
            )
            .child(div().text_center().child(self.label))
            .refine_style(&self.style)
    }
}
