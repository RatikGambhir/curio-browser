//! A pill-shaped action with an icon and a short label.

use gpui_kit::assets::IconName;
use gpui_kit::component::{Icon, Sizable, Size, StyledExt as _, h_flex};
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{
    App, Div, ElementId, FontWeight, InteractiveElement, Interactivity, IntoElement,
    ParentElement as _, RenderOnce, SharedString, Stateful, StatefulInteractiveElement,
    StyleRefinement, Styled, Window, div, px,
};

use super::style::CurioStyled as _;
use crate::theme::CurioTheme;

/// A quick action, like "Explain" over selected text or a suggested prompt.
/// It picks up the accent on hover.
///
/// Small chips (the default) sit flush in a toolbar; `.large()` chips with
/// [`outlined`](Self::outlined) stand alone as suggestions.
#[derive(IntoElement)]
pub struct Chip {
    base: Stateful<Div>,
    style: StyleRefinement,
    label: SharedString,
    icon: Option<IconName>,
    size: Size,
    outlined: bool,
}

impl Chip {
    /// A chip reading `label`.
    #[must_use]
    pub fn new(id: impl Into<ElementId>, label: impl Into<SharedString>) -> Self {
        Self {
            base: h_flex().id(id),
            style: StyleRefinement::default(),
            label: label.into(),
            icon: None,
            size: Size::Small,
            outlined: false,
        }
    }

    /// The icon before the label.
    #[must_use]
    pub fn icon(mut self, icon: IconName) -> Self {
        self.icon = Some(icon);
        self
    }

    /// Draws the chip on its own bordered surface, with an accent icon.
    #[must_use]
    pub fn outlined(mut self) -> Self {
        self.outlined = true;
        self
    }
}

impl Sizable for Chip {
    fn with_size(mut self, size: impl Into<Size>) -> Self {
        self.size = size.into();
        self
    }
}

impl Styled for Chip {
    fn style(&mut self) -> &mut StyleRefinement {
        &mut self.style
    }
}

impl InteractiveElement for Chip {
    fn interactivity(&mut self) -> &mut Interactivity {
        self.base.interactivity()
    }
}

impl StatefulInteractiveElement for Chip {}

impl RenderOnce for Chip {
    fn render(self, _: &mut Window, cx: &mut App) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let small = matches!(self.size, Size::XSmall | Size::Small);
        let outlined = self.outlined;
        let icon = self.icon.map(|icon| {
            let icon = Icon::new(icon);
            div()
                .when(outlined, |el| el.text_color(theme.accent_text))
                .child(if small { icon.xsmall() } else { icon.small() })
        });

        self.base
            .flex_shrink_0()
            .map(|el| {
                if small {
                    el.h(px(28.))
                        .px(px(9.))
                        .gap(px(6.))
                        .rounded(px(8.))
                        .text_xs()
                        .font_weight(FontWeight::MEDIUM)
                } else {
                    el.h(px(34.))
                        .px(px(12.))
                        .gap(px(8.))
                        .rounded(px(9.))
                        .text_sm()
                }
            })
            .text_color(theme.text)
            .cursor_pointer()
            .map(|el| {
                if outlined {
                    el.surface(&theme)
                        .hover(|s| s.bg(theme.accent_soft).border_color(theme.accent_soft))
                } else {
                    el.hover(|s| s.bg(theme.accent_soft).text_color(theme.accent_text))
                }
            })
            .children(icon)
            .child(self.label)
            .refine_style(&self.style)
    }
}
