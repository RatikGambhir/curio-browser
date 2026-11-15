//! A compact, borderless icon button for the window chrome.

use gpui_kit::assets::IconName;
use gpui_kit::component::{Icon, Sizable, Size, StyledExt as _};
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{
    Action, AnyElement, App, Div, ElementId, InteractiveElement, Interactivity, IntoElement,
    ParentElement, RenderOnce, SharedString, Stateful, StatefulInteractiveElement, StyleRefinement,
    Styled, Window, div, px,
};

use super::style::TooltipExt as _;
use crate::theme::CurioTheme;

/// An icon-only button: muted until hovered, used across the toolbar,
/// sidebar and rows.
///
/// Give it an [`action`](Self::action) and a click dispatches it, and the
/// tooltip shows its shortcut. For custom behavior use `on_click` instead.
///
/// ```ignore
/// IconButton::new("reload", IconName::RotateCw)
///     .tooltip("Reload")
///     .action(actions::Reload)
/// ```
#[derive(IntoElement)]
pub struct IconButton {
    base: Stateful<Div>,
    style: StyleRefinement,
    icon: IconName,
    size: Size,
    tooltip: Option<SharedString>,
    action: Option<Box<dyn Action>>,
    selected: bool,
    disabled: bool,
    reveal_group: Option<SharedString>,
    force_visible: bool,
    children: Vec<AnyElement>,
}

impl IconButton {
    /// A small (28px) button showing `icon`.
    #[must_use]
    pub fn new(id: impl Into<ElementId>, icon: IconName) -> Self {
        Self {
            base: div().id(id),
            style: StyleRefinement::default(),
            icon,
            size: Size::Small,
            tooltip: None,
            action: None,
            selected: false,
            disabled: false,
            reveal_group: None,
            force_visible: false,
            children: Vec::new(),
        }
    }

    /// The hover label. With an [`action`](Self::action) it also shows the
    /// action's shortcut.
    #[must_use]
    pub fn tooltip(mut self, tooltip: impl Into<SharedString>) -> Self {
        self.tooltip = Some(tooltip.into());
        self
    }

    /// Dispatches `action` on click.
    #[must_use]
    pub fn action(mut self, action: impl Action) -> Self {
        self.action = Some(Box::new(action));
        self
    }

    /// Shows the button as switched on (e.g. an open panel).
    #[must_use]
    pub fn selected(mut self, selected: bool) -> Self {
        self.selected = selected;
        self
    }

    /// Dims the button and stops it dispatching its action.
    #[must_use]
    pub fn disabled(mut self, disabled: bool) -> Self {
        self.disabled = disabled;
        self
    }

    /// Hides the button until the pointer is over the ancestor marked with
    /// `.group(group)`, like a row's close button.
    #[must_use]
    pub fn reveal_on_hover(mut self, group: impl Into<SharedString>) -> Self {
        self.reveal_group = Some(group.into());
        self
    }

    /// Keeps a [`reveal_on_hover`](Self::reveal_on_hover) button visible,
    /// e.g. on the selected row.
    #[must_use]
    pub fn force_visible(mut self, visible: bool) -> Self {
        self.force_visible = visible;
        self
    }
}

impl Sizable for IconButton {
    fn with_size(mut self, size: impl Into<Size>) -> Self {
        self.size = size.into();
        self
    }
}

/// Children are drawn after the icon, e.g. a badge.
impl ParentElement for IconButton {
    fn extend(&mut self, elements: impl IntoIterator<Item = AnyElement>) {
        self.children.extend(elements);
    }
}

impl Styled for IconButton {
    fn style(&mut self) -> &mut StyleRefinement {
        &mut self.style
    }
}

impl InteractiveElement for IconButton {
    fn interactivity(&mut self) -> &mut Interactivity {
        self.base.interactivity()
    }
}

impl StatefulInteractiveElement for IconButton {}

impl RenderOnce for IconButton {
    fn render(self, _: &mut Window, cx: &mut App) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let (edge, radius) = match self.size {
            Size::XSmall => (px(22.), px(6.)),
            Size::Small => (px(28.), px(7.)),
            Size::Medium => (px(32.), px(8.)),
            Size::Large => (px(36.), px(9.)),
            Size::Size(edge) => (edge, edge * 0.25),
        };
        let icon_size = match self.size {
            Size::Size(_) => Size::Small,
            size => size,
        };
        let hidden = self.reveal_group.is_some() && !self.force_visible;
        let action = self.action.filter(|_| !self.disabled);

        self.base
            .flex_shrink_0()
            .size(edge)
            .flex()
            .items_center()
            .justify_center()
            .rounded(radius)
            .text_color(theme.text_muted)
            .child(Icon::new(self.icon).with_size(icon_size))
            .children(self.children)
            .when(self.selected, |el| {
                el.text_color(theme.accent_text).bg(theme.row_hover)
            })
            .map(|el| {
                if self.disabled {
                    el.opacity(0.35)
                } else {
                    el.cursor_pointer()
                        .hover(|s| s.bg(theme.row_hover).text_color(theme.text))
                        .active(|s| s.opacity(0.7))
                }
            })
            .when_some(self.reveal_group.filter(|_| hidden), |el, group| {
                el.invisible().group_hover(group, |s| s.visible())
            })
            .when_some(self.tooltip, |el, tooltip| match &action {
                Some(action) => el.tooltip_action(tooltip, action.as_ref()),
                None => el.tooltip_text(tooltip),
            })
            .when_some(action, |el, action| {
                el.on_click(move |_, window, cx| window.dispatch_action(action.boxed_clone(), cx))
            })
            .refine_style(&self.style)
    }
}

impl gpui_kit::component::Selectable for IconButton {
    fn selected(mut self, selected: bool) -> Self {
        self.selected = selected;
        self
    }

    fn is_selected(&self) -> bool {
        self.selected
    }
}

/// Lets an icon button open a menu on click (shown as selected while open).
impl gpui_kit::component::menu::DropdownMenu for IconButton {}
