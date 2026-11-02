//! A text field framed for searching.

use gpui_kit::assets::IconName;
use gpui_kit::component::input::{Input, InputState};
use gpui_kit::component::{Icon, Sizable as _, StyledExt as _, h_flex};
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{
    AnyElement, App, ElementId, Entity, InteractiveElement as _, IntoElement, ParentElement,
    RenderOnce, StyleRefinement, Styled, Window, div, px,
};

use super::style::CurioStyled as _;
use crate::theme::{CurioTheme, metrics};

/// A borderless input in a rounded field, with a leading icon and optional
/// trailing controls (its children).
///
/// By default it sits on the chrome like the address pill.
/// [`floating`](Self::floating) puts it on a raised surface over content,
/// like the find bar.
#[derive(IntoElement)]
pub struct SearchField {
    id: ElementId,
    style: StyleRefinement,
    input: Entity<InputState>,
    icon: IconName,
    cleanable: bool,
    floating: bool,
    children: Vec<AnyElement>,
}

impl SearchField {
    /// A field editing `input`.
    #[must_use]
    pub fn new(id: impl Into<ElementId>, input: &Entity<InputState>) -> Self {
        Self {
            id: id.into(),
            style: StyleRefinement::default(),
            input: input.clone(),
            icon: IconName::Search,
            cleanable: false,
            floating: false,
            children: Vec::new(),
        }
    }

    /// The icon before the text (a magnifier by default).
    #[must_use]
    pub fn icon(mut self, icon: IconName) -> Self {
        self.icon = icon;
        self
    }

    /// Shows a clear button while there is text.
    #[must_use]
    pub fn cleanable(mut self, cleanable: bool) -> Self {
        self.cleanable = cleanable;
        self
    }

    /// Draws the field on a raised, shadowed surface.
    #[must_use]
    pub fn floating(mut self) -> Self {
        self.floating = true;
        self
    }
}

impl ParentElement for SearchField {
    fn extend(&mut self, elements: impl IntoIterator<Item = AnyElement>) {
        self.children.extend(elements);
    }
}

impl Styled for SearchField {
    fn style(&mut self) -> &mut StyleRefinement {
        &mut self.style
    }
}

impl RenderOnce for SearchField {
    fn render(self, _: &mut Window, cx: &mut App) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        h_flex()
            .id(self.id)
            .min_w_0()
            .px(px(10.))
            .map(|el| {
                if self.floating {
                    el.h(px(42.))
                        .gap(px(6.))
                        .rounded(px(12.))
                        .surface(&theme)
                        .shadow_lg()
                } else {
                    el.h(px(34.))
                        .gap(px(8.))
                        .rounded(metrics::FIELD_RADIUS)
                        .bg(theme.field)
                        .hover(|s| s.bg(theme.field_hover))
                }
            })
            .child(
                div()
                    .text_color(theme.text_faint)
                    .child(Icon::new(self.icon).small()),
            )
            .child(
                div().flex_1().min_w_0().child(
                    Input::new(&self.input)
                        .appearance(false)
                        .small()
                        .cleanable(self.cleanable),
                ),
            )
            .children(self.children)
            .refine_style(&self.style)
    }
}
