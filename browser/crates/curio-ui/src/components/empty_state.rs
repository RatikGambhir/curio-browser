//! What a list or pane shows when it has nothing in it.

use gpui_kit::assets::IconName;
use gpui_kit::component::{Icon, StyledExt as _, v_flex};
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{
    AnyElement, App, FontWeight, IntoElement, ParentElement, RenderOnce, SharedString,
    StyleRefinement, Styled, Window, div, px,
};

use crate::theme::CurioTheme;

/// A centered message for an empty list: an optional icon, a title, an
/// optional description, and optional actions (its children).
///
/// Use [`compact`](Self::compact) inside dialogs, where a single faint line
/// reads better than a large illustration.
#[derive(IntoElement)]
pub struct EmptyState {
    style: StyleRefinement,
    icon: Option<IconName>,
    title: SharedString,
    description: Option<SharedString>,
    compact: bool,
    children: Vec<AnyElement>,
}

impl EmptyState {
    /// An empty state headed by `title`.
    #[must_use]
    pub fn new(title: impl Into<SharedString>) -> Self {
        Self {
            style: StyleRefinement::default(),
            icon: None,
            title: title.into(),
            description: None,
            compact: false,
            children: Vec::new(),
        }
    }

    /// A large faint icon above the title.
    #[must_use]
    pub fn icon(mut self, icon: IconName) -> Self {
        self.icon = Some(icon);
        self
    }

    /// Explains what will appear here, or what to try.
    #[must_use]
    pub fn description(mut self, description: impl Into<SharedString>) -> Self {
        self.description = Some(description.into());
        self
    }

    /// A single faint line, left-aligned.
    #[must_use]
    pub fn compact(mut self) -> Self {
        self.compact = true;
        self
    }
}

impl ParentElement for EmptyState {
    fn extend(&mut self, elements: impl IntoIterator<Item = AnyElement>) {
        self.children.extend(elements);
    }
}

impl Styled for EmptyState {
    fn style(&mut self) -> &mut StyleRefinement {
        &mut self.style
    }
}

impl RenderOnce for EmptyState {
    fn render(self, _: &mut Window, cx: &mut App) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        if self.compact {
            return div()
                .p(px(20.))
                .text_sm()
                .text_color(theme.text_faint)
                .child(self.title)
                .children(self.children)
                .refine_style(&self.style)
                .into_any_element();
        }
        v_flex()
            .flex_1()
            .items_center()
            .justify_center()
            .gap(px(8.))
            .px(px(20.))
            .pb(px(44.))
            .when_some(self.icon, |el, icon| {
                el.child(
                    div()
                        .text_color(theme.text_faint)
                        .child(Icon::new(icon).size(px(40.))),
                )
            })
            .child(
                div()
                    .text_base()
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_color(theme.text)
                    .child(self.title),
            )
            .when_some(self.description, |el, description| {
                el.child(
                    div()
                        .text_sm()
                        .text_center()
                        .text_color(theme.text_muted)
                        .child(description),
                )
            })
            .children(self.children)
            .refine_style(&self.style)
            .into_any_element()
    }
}
