//! Site icons and Curio's logo.

use std::{future::Future, sync::Arc, time::Duration};

use gpui_kit::component::Sizable as _;
use gpui_kit::component::spinner::Spinner;
use gpui_kit::{
    App, Asset, FontWeight, Hsla, ImageAssetLoader, ImageSource, IntoElement, ParentElement as _,
    Pixels, RenderImage, RenderOnce, Resource, SharedString, Styled as _, Window, div, img, px,
};
use url::Url;

use crate::theme::CurioTheme;

/// A site's favicon. Falls back to a colored letter while the image loads or
/// when the site has no usable icon, and shows a spinner while the page is loading.
///
/// ```ignore
/// Favicon::new(&title).url(tab.favicon_url.as_deref()).page_url(&tab.url).loading(state.loading)
/// ```
#[derive(IntoElement)]
pub struct Favicon {
    label: SharedString,
    url: Option<SharedString>,
    page_icon: Option<String>,
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
            page_icon: None,
            size: Self::DEFAULT_SIZE,
            loading: false,
        }
    }

    /// The icon URL declared by the page.
    #[must_use]
    pub fn url<S: Into<SharedString>>(mut self, url: Option<S>) -> Self {
        self.url = url.map(Into::into).filter(|u| !u.is_empty());
        self
    }

    /// Try the page's conventional favicon when its declared icon is unavailable.
    #[must_use]
    pub fn page_url(mut self, page_url: &str) -> Self {
        self.page_icon = default_icon_url(page_url);
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
    fn render(self, window: &mut Window, cx: &mut App) -> impl IntoElement {
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
        for url in icon_candidates(self.url.as_deref(), self.page_icon.as_deref()) {
            let ImageSource::Resource(source) = ImageSource::from(url) else {
                continue;
            };
            match window.use_asset::<FaviconImage>(&source, cx) {
                Some(Some(image)) => {
                    return img(image).size(size).rounded(px(3.)).into_any_element();
                }
                Some(None) => continue,
                None => return fallback(),
            }
        }
        fallback()
    }
}

fn default_icon_url(page_url: &str) -> Option<String> {
    let url = Url::parse(page_url).ok()?;
    match url.origin() {
        origin @ url::Origin::Tuple(..) if matches!(url.scheme(), "http" | "https") => {
            Some(format!("{}/favicon.ico", origin.ascii_serialization()))
        }
        _ => None,
    }
}

fn icon_candidates<'a>(
    declared: Option<&'a str>,
    conventional: Option<&'a str>,
) -> impl Iterator<Item = &'a str> {
    declared
        .into_iter()
        .chain(conventional.filter(move |url| Some(*url) != declared))
}

enum FaviconImage {}

impl Asset for FaviconImage {
    type Source = Resource;
    type Output = Option<Arc<RenderImage>>;

    fn load(source: Resource, cx: &mut App) -> impl Future<Output = Self::Output> + Send + 'static {
        let timeout = cx.background_executor().timer(Duration::from_secs(5));
        let image = ImageAssetLoader::load(source.clone(), cx);
        futures_lite::future::race(
            async move {
                image
                    .await
                    .inspect_err(|error| tracing::debug!(?source, %error, "could not load favicon"))
                    .ok()
            },
            async move {
                timeout.await;
                None
            },
        )
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
    fn default_icon_uses_the_page_origin() {
        assert_eq!(
            default_icon_url("https://user:secret@example.com:8443/path?q=1#here").as_deref(),
            Some("https://example.com:8443/favicon.ico")
        );
        assert_eq!(default_icon_url("file:///tmp/index.html"), None);
        assert_eq!(default_icon_url("blob:https://example.com/opaque-id"), None);
    }

    #[test]
    fn icon_candidates_prefer_declared_icon_and_skip_duplicates() {
        let default = "https://example.com/favicon.ico";
        assert_eq!(
            icon_candidates(Some("https://cdn.example.com/icon.svg"), Some(default))
                .collect::<Vec<_>>(),
            ["https://cdn.example.com/icon.svg", default]
        );
        assert_eq!(
            icon_candidates(Some(default), Some(default)).collect::<Vec<_>>(),
            [default]
        );
        assert_eq!(
            icon_candidates(None, Some(default)).collect::<Vec<_>>(),
            [default]
        );
    }

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
