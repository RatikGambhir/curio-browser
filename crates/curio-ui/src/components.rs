//! Small building blocks shared across Curio's views.

use gpui_kit::component::{Icon, Sizable as _, h_flex};
use gpui_kit::assets::IconName;
use gpui_kit::{
    AnyElement, App, Div, FontWeight, Hsla, InteractiveElement as _, IntoElement,
    ParentElement as _, Pixels, SharedString, Stateful, StatefulInteractiveElement as _,
    Styled as _, StyledImage as _, div, img, px, svg,
};

use crate::theme::CurioTheme;

/// A deterministic soft color for a site's letter avatar.
fn letter_color(seed: &str) -> Hsla {
    let hash = seed.bytes().fold(0u32, |h, b| h.wrapping_mul(31).wrapping_add(u32::from(b)));
    gpui_kit::hsla((hash % 360) as f32 / 360.0, 0.55, 0.55, 1.0)
}

/// A site's favicon, falling back to a colored letter.
pub fn favicon(url: Option<&str>, label: &str, size: Pixels) -> AnyElement {
    let letter: SharedString = label
        .chars()
        .find(|c| c.is_alphanumeric())
        .map_or_else(|| "•".to_owned(), |c| c.to_uppercase().collect())
        .into();
    let color = letter_color(label);
    let fallback = move || {
        div()
            .size(size)
            .rounded(size * 0.28)
            .bg(color)
            .flex()
            .items_center()
            .justify_center()
            .text_color(gpui_kit::white())
            .text_size(size * 0.62)
            .font_weight(FontWeight::BOLD)
            .child(letter.clone())
            .into_any_element()
    };
    match url {
        Some(url) if !url.is_empty() => img(SharedString::from(url.to_owned()))
            .size(size)
            .rounded(px(3.))
            .with_fallback(fallback.clone())
            .with_loading(fallback)
            .into_any_element(),
        _ => fallback(),
    }
}

/// The Curio logo mark tinted with `color`.
pub fn logo_mark(size: Pixels, color: Hsla) -> impl IntoElement {
    svg().path(crate::assets::MARK).size(size).text_color(color)
}

/// A compact icon button for the chrome (sidebar, toolbars).
pub fn chrome_button(
    id: impl Into<gpui_kit::ElementId>,
    icon: IconName,
    cx: &App,
) -> Stateful<Div> {
    let theme = CurioTheme::get(cx);
    div()
        .id(id)
        .size(px(28.))
        .flex()
        .items_center()
        .justify_center()
        .rounded(px(7.))
        .text_color(theme.text_muted)
        .cursor_pointer()
        .hover(|s| s.bg(theme.row_hover).text_color(theme.text))
        .active(|s| s.opacity(0.7))
        .child(Icon::new(icon).small())
}

/// A keyboard shortcut hint, e.g. "⌘T".
pub fn shortcut_hint(text: &str, cx: &App) -> impl IntoElement {
    let theme = CurioTheme::get(cx);
    div()
        .px(px(5.))
        .py(px(1.))
        .rounded(px(4.))
        .bg(theme.row_hover)
        .text_xs()
        .text_color(theme.text_faint)
        .child(SharedString::from(text.to_owned()))
}

/// A small pill label.
pub fn pill(text: impl Into<SharedString>, bg: Hsla, fg: Hsla) -> impl IntoElement {
    h_flex()
        .px(px(7.))
        .h(px(20.))
        .rounded_full()
        .bg(bg)
        .text_color(fg)
        .text_xs()
        .child(text.into())
}
