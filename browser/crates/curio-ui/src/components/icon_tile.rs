//! A square, selectable tile holding an icon.

use gpui_kit::component::StyledExt as _;
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{
    AnyElement, App, Div, ElementId, InteractiveElement, Interactivity, IntoElement, ParentElement,
    RenderOnce, Stateful, StatefulInteractiveElement, StyleRefinement, Styled, Window, div, px,
};

use crate::theme::CurioTheme;

/// A 30px square holding an icon, e.g. a pinned tab or a favorite. The
/// selected tile is lifted onto the chrome.
///
/// [`filled`](Self::filled) tiles sit on the field color even when idle, so
/// a row of them reads as a set of buttons.
#[derive(IntoElement)]
pub struct IconTile {
    base: Stateful<Div>,
    style: StyleRefinement,
    content: AnyElement,
    selected: bool,
    filled: bool,
    children: Vec<AnyElement>,
}

impl IconTile {
    /// A tile showing `content`, centered.
    #[must_use]
    pub fn new(id: impl Into<ElementId>, content: impl IntoElement) -> Self {
        Self {
            base: div().id(id),
            style: StyleRefinement::default(),
            content: content.into_any_element(),
            selected: false,
            filled: false,
            children: Vec::new(),
        }
    }

    /// Marks the tile as the current one.
    #[must_use]
    pub fn selected(mut self, selected: bool) -> Self {
        self.selected = selected;
        self
    }

    /// Gives the idle tile a field background.
    #[must_use]
    pub fn filled(mut self, filled: bool) -> Self {
        self.filled = filled;
        self
    }
}

/// Children are drawn after the content, e.g. a badge.
impl ParentElement for IconTile {
    fn extend(&mut self, elements: impl IntoIterator<Item = AnyElement>) {
        self.children.extend(elements);
    }
}

impl Styled for IconTile {
    fn style(&mut self) -> &mut StyleRefinement {
        &mut self.style
    }
}

impl InteractiveElement for IconTile {
    fn interactivity(&mut self) -> &mut Interactivity {
        self.base.interactivity()
    }
}

impl StatefulInteractiveElement for IconTile {}

impl RenderOnce for IconTile {
    fn render(self, _: &mut Window, cx: &mut App) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let (selected, filled) = (self.selected, self.filled);
        self.base
            .size(px(30.))
            .flex_shrink_0()
            .rounded(px(8.))
            .flex()
            .items_center()
            .justify_center()
            .cursor_pointer()
            .map(|el| match (selected, filled) {
                (true, true) => el
                    .bg(theme.row_active)
                    .shadow_sm()
                    .hover(|s| s.bg(theme.field_hover)),
                (true, false) => el.bg(theme.row_active).shadow_xs(),
                (false, true) => el.bg(theme.field).hover(|s| s.bg(theme.field_hover)),
                (false, false) => el.hover(|s| s.bg(theme.row_hover)),
            })
            .child(self.content)
            .children(self.children)
            .refine_style(&self.style)
    }
}
