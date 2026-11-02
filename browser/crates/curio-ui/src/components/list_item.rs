//! The row used by every list: tabs, library items, history, commands and
//! settings navigation.

use gpui_kit::component::{StyledExt as _, h_flex, v_flex};
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{
    AnyElement, App, Div, ElementId, FontWeight, InteractiveElement, Interactivity, IntoElement,
    ParentElement, Pixels, RenderOnce, SharedString, Stateful, StatefulInteractiveElement,
    StyleRefinement, Styled, Window, div, px,
};

use super::style::CurioStyled as _;
use crate::theme::{CurioTheme, metrics};

/// How a [`ListItem`] looks when selected.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum SelectedStyle {
    /// Lifted off the chrome like a card: the active tab.
    #[default]
    Raised,
    /// An accent wash with accent text: a selected navigation entry.
    Accent,
    /// An accent wash only, keeping the text color: a highlighted result.
    Subtle,
}

/// A horizontal row: an optional leading icon, a title with an optional
/// subtitle, and trailing content (its children).
///
/// One-line rows are [`metrics::ROW_HEIGHT`] tall and two-line rows
/// [`ListItem::TWO_LINE_HEIGHT`]; override with `.h(...)`.
///
/// ```ignore
/// ListItem::new(("archived", id))
///     .leading(Favicon::new(&title).url(icon))
///     .title(title)
///     .subtitle(host)
///     .on_click(...)
/// ```
#[derive(IntoElement)]
pub struct ListItem {
    base: Stateful<Div>,
    style: StyleRefinement,
    leading: Option<AnyElement>,
    title: Option<SharedString>,
    title_weight: Option<FontWeight>,
    subtitle: Option<SharedString>,
    children: Vec<AnyElement>,
    selected: bool,
    selected_style: SelectedStyle,
    muted: bool,
}

impl ListItem {
    /// The height of a row with a subtitle.
    pub const TWO_LINE_HEIGHT: Pixels = px(44.);

    /// An empty row; add content with the builder methods.
    #[must_use]
    pub fn new(id: impl Into<ElementId>) -> Self {
        Self {
            base: h_flex().id(id),
            style: StyleRefinement::default(),
            leading: None,
            title: None,
            title_weight: None,
            subtitle: None,
            children: Vec::new(),
            selected: false,
            selected_style: SelectedStyle::default(),
            muted: false,
        }
    }

    /// The icon or avatar before the title.
    #[must_use]
    pub fn leading(mut self, leading: impl IntoElement) -> Self {
        self.leading = Some(leading.into_any_element());
        self
    }

    /// The main, single-line label. It truncates to fit.
    #[must_use]
    pub fn title(mut self, title: impl Into<SharedString>) -> Self {
        self.title = Some(title.into());
        self
    }

    /// The title's weight.
    #[must_use]
    pub fn title_weight(mut self, weight: FontWeight) -> Self {
        self.title_weight = Some(weight);
        self
    }

    /// A faint second line under the title.
    #[must_use]
    pub fn subtitle(mut self, subtitle: impl Into<SharedString>) -> Self {
        self.subtitle = Some(subtitle.into());
        self
    }

    /// Marks the row as the current one.
    #[must_use]
    pub fn selected(mut self, selected: bool) -> Self {
        self.selected = selected;
        self
    }

    /// How the selected state looks.
    #[must_use]
    pub fn selected_style(mut self, style: SelectedStyle) -> Self {
        self.selected_style = style;
        self
    }

    /// Muted text that brightens on hover, for navigation on the chrome.
    #[must_use]
    pub fn muted(mut self, muted: bool) -> Self {
        self.muted = muted;
        self
    }
}

impl ParentElement for ListItem {
    fn extend(&mut self, elements: impl IntoIterator<Item = AnyElement>) {
        self.children.extend(elements);
    }
}

impl Styled for ListItem {
    fn style(&mut self) -> &mut StyleRefinement {
        &mut self.style
    }
}

impl InteractiveElement for ListItem {
    fn interactivity(&mut self) -> &mut Interactivity {
        self.base.interactivity()
    }
}

impl StatefulInteractiveElement for ListItem {}

impl RenderOnce for ListItem {
    fn render(self, _: &mut Window, cx: &mut App) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let height = if self.subtitle.is_some() {
            Self::TWO_LINE_HEIGHT
        } else {
            metrics::ROW_HEIGHT
        };
        let selected = self.selected;
        let muted = self.muted;

        let label = self.title.map(|title| {
            v_flex()
                .flex_1()
                .min_w_0()
                .child(
                    div()
                        .truncate()
                        .when_some(self.title_weight, |el, weight| el.font_weight(weight))
                        .child(title),
                )
                .when_some(self.subtitle, |el, subtitle| {
                    el.child(
                        div()
                            .text_xs()
                            .text_color(theme.text_faint)
                            .truncate()
                            .child(subtitle),
                    )
                })
        });

        self.base
            .h(height)
            .px(px(8.))
            .gap(px(10.))
            .rounded(metrics::ROW_RADIUS)
            .text_sm()
            .cursor_pointer()
            .when(muted && !selected, |el| el.text_color(theme.text_muted))
            .map(|el| match (selected, self.selected_style) {
                (true, SelectedStyle::Raised) => el.raised_row(&theme),
                (true, SelectedStyle::Accent) => {
                    el.bg(theme.accent_soft).text_color(theme.accent_text)
                }
                (true, SelectedStyle::Subtle) => el.bg(theme.accent_soft),
                (false, _) if muted => el.hover(|s| s.bg(theme.row_hover).text_color(theme.text)),
                (false, _) => el.hover(|s| s.bg(theme.row_hover)),
            })
            .when_some(self.leading, |el, leading| {
                el.child(div().flex_shrink_0().flex().items_center().child(leading))
            })
            .when_some(label, |el, label| el.child(label))
            .children(self.children)
            .refine_style(&self.style)
    }
}
