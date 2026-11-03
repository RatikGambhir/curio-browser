//! A space gradient painted behind an element.
//!
//! GPUI only draws two-stop linear gradients, so Curio paints each theme
//! (4 stops plus soft radial glows, see [`curio_core::gradient`]) into a small
//! bitmap once and stretches it to fit. The gradients are low-frequency and
//! dithered, so scaling keeps them smooth at any size.

use std::collections::HashMap;
use std::sync::Arc;

use curio_core::SpaceGradient;
use gpui_kit::{
    App, Global, IntoElement, ObjectFit, RenderImage, RenderOnce, Styled as _, StyledImage as _,
    Window, img,
};

/// Bitmap sizes. `Window` is window-shaped (16:10) for the chrome;
/// `Swatch` is for small previews such as the picker.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum GradientSize {
    Window,
    Swatch,
}

impl GradientSize {
    fn pixels(self) -> (u32, u32) {
        match self {
            Self::Window => (480, 300),
            Self::Swatch => (96, 60),
        }
    }
}

/// Painted gradients, kept for the life of the app (20 themes at most, about
/// 600 KB each at window size).
#[derive(Default)]
struct GradientImages(HashMap<(SpaceGradient, GradientSize), Arc<RenderImage>>);

impl Global for GradientImages {}

/// The painted bitmap for `gradient`, painting it on first use.
pub fn gradient_image(
    gradient: SpaceGradient,
    size: GradientSize,
    cx: &mut App,
) -> Arc<RenderImage> {
    cx.default_global::<GradientImages>()
        .0
        .entry((gradient, size))
        .or_insert_with(|| {
            let (width, height) = size.pixels();
            let mut pixels = gradient.spec().render_rgba(width, height);
            // GPUI draws BGRA.
            for pixel in pixels.as_chunks_mut::<4>().0 {
                pixel.swap(0, 2);
            }
            let frame = image::RgbaImage::from_raw(width, height, pixels)
                .map(image::Frame::new)
                .unwrap_or_else(|| image::Frame::new(image::RgbaImage::new(1, 1)));
            Arc::new(RenderImage::new(vec![frame]))
        })
        .clone()
}

/// Fills its parent with a space gradient. Put it first inside a `relative`
/// element with `overflow_hidden`; later children draw on top.
#[derive(IntoElement)]
pub struct GradientBackdrop {
    gradient: SpaceGradient,
    size: GradientSize,
}

impl GradientBackdrop {
    #[must_use]
    pub fn new(gradient: SpaceGradient) -> Self {
        Self {
            gradient,
            size: GradientSize::Window,
        }
    }

    /// Uses the small bitmap, for previews.
    #[must_use]
    pub fn swatch(mut self) -> Self {
        self.size = GradientSize::Swatch;
        self
    }
}

impl RenderOnce for GradientBackdrop {
    fn render(self, _: &mut Window, cx: &mut App) -> impl IntoElement {
        img(gradient_image(self.gradient, self.size, cx))
            .absolute()
            .top_0()
            .left_0()
            .size_full()
            .object_fit(ObjectFit::Fill)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bitmaps_are_the_expected_size() {
        for size in [GradientSize::Window, GradientSize::Swatch] {
            let (w, h) = size.pixels();
            let pixels = SpaceGradient::Ember.spec().render_rgba(w, h);
            assert_eq!(pixels.len(), (w * h * 4) as usize);
        }
    }
}
