//! Site icons and Curio's logo.

use gpui_kit::component::Sizable as _;
use gpui_kit::component::spinner::Spinner;
use gpui_kit::{
    App, FontWeight, Hsla, IntoElement, ParentElement as _, Pixels, RenderOnce, SharedString,
    Styled as _, StyledImage as _, Window, div, img, px,
};

use crate::theme::CurioTheme;

/// A site's favicon. Falls back to a colored letter while the image loads or
/// when there is none, and shows a spinner while the page is loading.
///
/// ```ignore
/// Favicon::new(&title).url(tab.favicon_url.as_deref()).loading(state.loading)
/// ```
#[derive(IntoElement)]
pub struct Favicon {
    label: SharedString,
    url: Option<SharedString>,
    size: Pixels,
    loading: bool,
}

impl Favicon {
    /// The default edge length, matching a list row's icon.
    pub const DEFAULT_SIZE: Pixels = px(16.);

    /// A favicon for a site named `label`; its first letter is the fallback.
    #[must_use]
    pub fn new(label: impl Into<SharedString>) -> Self {
        Self {
            label: label.into(),
            url: None,
            size: Self::DEFAULT_SIZE,
            loading: false,
        }
    }

    /// The icon's image URL. Empty or missing URLs show the letter.
    #[must_use]
    pub fn url<S: Into<SharedString>>(mut self, url: Option<S>) -> Self {
        self.url = url.map(Into::into).filter(|u| !u.is_empty());
        self
    }

    /// The edge length.
    #[must_use]
    pub fn size(mut self, size: Pixels) -> Self {
        self.size = size;
        self
    }

    /// Shows a spinner in place of the icon.
    #[must_use]
    pub fn loading(mut self, loading: bool) -> Self {
        self.loading = loading;
        self
    }
}

impl RenderOnce for Favicon {
    fn render(self, _: &mut Window, cx: &mut App) -> impl IntoElement {
        let size = self.size;
        if self.loading {
            let accent = CurioTheme::get(cx).accent;
            return div()
                .size(size)
                .flex()
                .items_center()
                .justify_center()
                .child(Spinner::new().xsmall().color(accent))
                .into_any_element();
        }
        let letter: SharedString = initial(&self.label).into();
        let color = letter_color(&self.label);
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
        match self.url {
            Some(url) => img(url)
                .size(size)
                .rounded(px(3.))
                .with_fallback(fallback.clone())
                .with_loading(fallback)
                .into_any_element(),
            None => fallback(),
        }
    }
}

/// The full-color Curio logo.
#[must_use]
pub fn logo_mark(size: Pixels) -> impl IntoElement {
    img(crate::assets::LOGO).size(size)
}

/// The letter shown for a site without an icon.
fn initial(label: &str) -> String {
    label
        .chars()
        .find(|c| c.is_alphanumeric())
        .map_or_else(|| "•".to_owned(), |c| c.to_uppercase().collect())
}

/// A deterministic soft color for a site's letter avatar.
fn letter_color(seed: &str) -> Hsla {
    let hash = seed
        .bytes()
        .fold(0u32, |h, b| h.wrapping_mul(31).wrapping_add(u32::from(b)));
    // `hash % 360` is exact in f32.
    let hue = (hash % 360) as f32 / 360.0;
    gpui_kit::hsla(hue, 0.55, 0.55, 1.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn initial_skips_punctuation_and_uppercases() {
        assert_eq!(initial("github.com"), "G");
        assert_eq!(initial("  (rust)"), "R");
        assert_eq!(initial("…"), "•");
    }

    #[test]
    fn letter_color_is_stable_per_label() {
        assert_eq!(letter_color("curio"), letter_color("curio"));
        assert!(letter_color("a").h >= 0.0 && letter_color("a").h < 1.0);
    }
}
