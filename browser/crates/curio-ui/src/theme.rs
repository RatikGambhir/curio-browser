//! Curio's design system.
//!
//! The chrome takes its color from the active space, like Arc: each space
//! has a soft gradient theme behind the sidebar, with the page floating on
//! top as a card. The theme's tone decides whether the chrome is light or
//! dark, whatever the system appearance (web pages still follow the
//! appearance setting). [`CurioTheme`] holds the tokens derived from the
//! active space's gradient. The GPUI Kit component theme is kept in step so
//! inputs, menus and dialogs share the accent.

use curio_core::{AccentColor, SpaceGradient, Tone};
use gpui_kit::component::{Theme, ThemeMode};
use gpui_kit::{App, Global, Hsla, Rgba, Window, WindowAppearance, hsla, px};

/// Whether the UI renders light or dark.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Appearance {
    Light,
    Dark,
}

/// Derived color tokens for Curio's chrome.
#[derive(Debug, Clone, Copy)]
pub struct CurioTheme {
    pub appearance: Appearance,
    pub gradient: SpaceGradient,
    /// The pure accent, for focus rings and primary buttons.
    pub accent: Hsla,
    /// A soft accent wash for selected rows and chips.
    pub accent_soft: Hsla,
    /// Accent-tinted text that stays legible on the chrome.
    pub accent_text: Hsla,
    /// The gradient's color near the top and bottom of the sidebar, for
    /// anything that needs a flat approximation of it.
    pub chrome_top: Hsla,
    pub chrome_bottom: Hsla,
    pub text: Hsla,
    pub text_muted: Hsla,
    pub text_faint: Hsla,
    pub row_hover: Hsla,
    pub row_active: Hsla,
    pub row_active_text: Hsla,
    pub row_active_border: Hsla,
    pub divider: Hsla,
    /// The URL pill and other inputs on the chrome.
    pub field: Hsla,
    pub field_hover: Hsla,
    /// The page card.
    pub card: Hsla,
    pub card_border: Hsla,
    /// Floating surfaces: command bar, popovers, the AI panel.
    pub surface: Hsla,
    pub surface_raised: Hsla,
    pub surface_border: Hsla,
    pub scrim: Hsla,
    pub user_bubble: Hsla,
    pub user_bubble_text: Hsla,
    pub success: Hsla,
    pub danger: Hsla,
    pub warning: Hsla,
    pub find_highlight: Hsla,
}

impl Global for CurioTheme {}

/// Corner radii and sizes shared across components.
pub mod metrics {
    use gpui_kit::{Pixels, px};

    pub const CARD_RADIUS: Pixels = px(12.);
    pub const ROW_RADIUS: Pixels = px(8.);
    pub const ROW_HEIGHT: Pixels = px(34.);
    pub const FIELD_RADIUS: Pixels = px(9.);
    pub const PANEL_GAP: Pixels = px(8.);
    /// Space reserved for the macOS traffic lights in the sidebar header.
    pub const TRAFFIC_LIGHTS_WIDTH: Pixels = px(76.);
    /// Where the macOS traffic lights sit: centered on a toolbar-height row
    /// at the top of the window (the sidebar's top row, or the tab strip).
    pub const TRAFFIC_LIGHTS_X: Pixels = px(14.);
    pub const TRAFFIC_LIGHTS_Y: Pixels = px(15.);
    pub const TOOLBAR_HEIGHT: Pixels = px(44.);
}

fn hex(rgb: u32) -> Hsla {
    Rgba {
        r: ((rgb >> 16) & 0xff) as f32 / 255.0,
        g: ((rgb >> 8) & 0xff) as f32 / 255.0,
        b: (rgb & 0xff) as f32 / 255.0,
        a: 1.0,
    }
    .into()
}

fn with_alpha(color: Hsla, a: f32) -> Hsla {
    Hsla { a, ..color }
}

/// Linear blend in HSL space (good enough for close colors).
#[must_use]
pub fn mix(a: Hsla, b: Hsla, t: f32) -> Hsla {
    let t = t.clamp(0.0, 1.0);
    // Interpolate hue along the shortest path.
    let mut dh = b.h - a.h;
    if dh > 0.5 {
        dh -= 1.0;
    } else if dh < -0.5 {
        dh += 1.0;
    }
    Hsla {
        h: (a.h + dh * t).rem_euclid(1.0),
        s: a.s + (b.s - a.s) * t,
        l: a.l + (b.l - a.l) * t,
        a: a.a + (b.a - a.a) * t,
    }
}

impl CurioTheme {
    /// Computes tokens for a space gradient. Its tone sets the appearance.
    #[must_use]
    pub fn new(gradient: SpaceGradient) -> Self {
        let accent = hex(gradient.accent_rgb());
        let h = accent.h;
        // Slate is intentionally almost neutral.
        let tint = if gradient == SpaceGradient::Slate {
            0.3
        } else {
            1.0
        };
        let spec = gradient.spec();
        let sample = |y: f32| {
            let [r, g, b] = spec.sample(0.08, y, 1.6);
            Hsla::from(Rgba { r, g, b, a: 1.0 })
        };
        let (chrome_top, chrome_bottom) = (sample(0.04), sample(0.96));
        let appearance = match gradient.tone() {
            Tone::Light => Appearance::Light,
            Tone::Dark => Appearance::Dark,
        };
        match appearance {
            Appearance::Light => Self {
                appearance,
                gradient,
                accent,
                accent_soft: with_alpha(accent, 0.14),
                accent_text: hsla(h, (accent.s * 0.9).min(0.85), 0.36, 1.0),
                chrome_top,
                chrome_bottom,
                text: hsla(h, 0.12 * tint, 0.13, 1.0),
                text_muted: hsla(h, 0.10 * tint, 0.13, 0.80),
                text_faint: hsla(h, 0.10 * tint, 0.13, 0.55),
                row_hover: hsla(0.0, 0.0, 1.0, 0.38),
                row_active: hsla(0.0, 0.0, 1.0, 0.86),
                row_active_text: hsla(h, 0.15 * tint, 0.10, 1.0),
                row_active_border: hsla(h, 0.30 * tint, 0.30, 0.10),
                divider: hsla(h, 0.20 * tint, 0.20, 0.10),
                field: hsla(0.0, 0.0, 1.0, 0.50),
                field_hover: hsla(0.0, 0.0, 1.0, 0.72),
                card: hsla(0.0, 0.0, 1.0, 1.0),
                card_border: hsla(h, 0.25 * tint, 0.25, 0.10),
                surface: hsla(h, 0.18 * tint, 0.985, 1.0),
                surface_raised: hsla(0.0, 0.0, 1.0, 1.0),
                surface_border: hsla(h, 0.25 * tint, 0.25, 0.12),
                scrim: hsla(h, 0.30 * tint, 0.12, 0.18),
                user_bubble: hsla(h, 0.55 * tint, 0.93, 1.0),
                user_bubble_text: hsla(h, 0.25 * tint, 0.14, 1.0),
                success: hex(0x2E9E5B),
                danger: hex(0xD8434E),
                warning: hex(0xD98A12),
                find_highlight: hex(0xFFB020),
            },
            Appearance::Dark => Self {
                appearance,
                gradient,
                accent: hsla(h, accent.s.min(0.85), accent.l.max(0.62), 1.0),
                accent_soft: hsla(h, accent.s, 0.62, 0.20),
                accent_text: hsla(h, (accent.s * 0.9).min(0.85), 0.78, 1.0),
                chrome_top,
                chrome_bottom,
                text: hsla(h, 0.10 * tint, 0.93, 1.0),
                text_muted: hsla(h, 0.08 * tint, 0.93, 0.78),
                text_faint: hsla(h, 0.08 * tint, 0.93, 0.52),
                row_hover: hsla(0.0, 0.0, 1.0, 0.06),
                row_active: hsla(0.0, 0.0, 1.0, 0.13),
                row_active_text: hsla(0.0, 0.0, 1.0, 1.0),
                row_active_border: hsla(0.0, 0.0, 1.0, 0.06),
                divider: hsla(0.0, 0.0, 1.0, 0.08),
                field: hsla(0.0, 0.0, 1.0, 0.07),
                field_hover: hsla(0.0, 0.0, 1.0, 0.11),
                card: hsla(h, 0.08 * tint, 0.105, 1.0),
                card_border: hsla(0.0, 0.0, 1.0, 0.08),
                surface: hsla(h, 0.14 * tint, 0.135, 1.0),
                surface_raised: hsla(h, 0.14 * tint, 0.165, 1.0),
                surface_border: hsla(0.0, 0.0, 1.0, 0.10),
                scrim: hsla(0.0, 0.0, 0.0, 0.40),
                user_bubble: hsla(h, 0.30 * tint, 0.24, 1.0),
                user_bubble_text: hsla(h, 0.10 * tint, 0.95, 1.0),
                success: hex(0x4CC27E),
                danger: hex(0xF0646E),
                warning: hex(0xF2A93B),
                find_highlight: hex(0xFFB020),
            },
        }
    }

    /// The global theme.
    #[must_use]
    pub fn get(cx: &App) -> &Self {
        cx.global::<Self>()
    }

    /// Installs tokens for `gradient`, and keeps the component library theme
    /// in step.
    pub fn apply(gradient: SpaceGradient, window: Option<&mut Window>, cx: &mut App) {
        let tokens = Self::new(gradient);
        let appearance = tokens.appearance;
        let mode = match appearance {
            Appearance::Light => ThemeMode::Light,
            Appearance::Dark => ThemeMode::Dark,
        };
        let mode_changed = cx
            .try_global::<Self>()
            .is_none_or(|current| current.appearance != appearance);
        cx.set_global(tokens);
        if mode_changed {
            Theme::change(mode, window, cx);
        }
        Theme::update(cx, |theme| {
            theme.radius = px(7.);
            theme.radius_lg = px(12.);
            theme.font_size = px(14.);
            theme.shadow = true;
            theme.primary = tokens.accent;
            theme.primary_hover = mix(tokens.accent, hsla(0., 0., 1., 1.), 0.08);
            theme.primary_active = mix(tokens.accent, hsla(0., 0., 0., 1.), 0.08);
            theme.primary_foreground = hsla(0., 0., 1., 1.);
            theme.button_primary = theme.primary;
            theme.button_primary_hover = theme.primary_hover;
            theme.button_primary_active = theme.primary_active;
            theme.button_primary_foreground = theme.primary_foreground;
            theme.ring = with_alpha(tokens.accent, 0.55);
            theme.caret = tokens.accent;
            theme.selection = with_alpha(tokens.accent, 0.28);
            theme.link = tokens.accent_text;
            theme.link_hover = tokens.accent;
            theme.popover = tokens.surface_raised;
            // Dialogs and sheets sit on the background color; keep dark mode
            // in Curio's tinted surface instead of near-black.
            if appearance == Appearance::Dark {
                theme.background = tokens.surface;
            }
            theme.popover_foreground = tokens.text;
            theme.list_active = tokens.accent_soft;
            theme.list_active_border = with_alpha(tokens.accent, 0.0);
            theme.switch = with_alpha(tokens.text, 0.18);
            theme.slider_bar = tokens.accent;
            theme.slider_thumb = hsla(0., 0., 1., 1.);
            theme.progress_bar = tokens.accent;
        });
    }

    /// Resolves the appearance for a theme setting and the window's system
    /// appearance. Web pages use this; the chrome follows the space.
    #[must_use]
    pub fn resolve(mode: curio_settings::ThemeMode, system: WindowAppearance) -> Appearance {
        match mode {
            curio_settings::ThemeMode::Light => Appearance::Light,
            curio_settings::ThemeMode::Dark => Appearance::Dark,
            curio_settings::ThemeMode::System => match system {
                WindowAppearance::Dark | WindowAppearance::VibrantDark => Appearance::Dark,
                _ => Appearance::Light,
            },
        }
    }

    /// The base color of an accent, for swatches.
    #[must_use]
    pub fn swatch(color: AccentColor) -> Hsla {
        hex(color.rgb())
    }

    /// A gradient's accent, for the small dots that stand for a space.
    #[must_use]
    pub fn gradient_swatch(gradient: SpaceGradient) -> Hsla {
        hex(gradient.accent_rgb())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mix_takes_shortest_hue_path() {
        let a = hsla(0.95, 0.5, 0.5, 1.0);
        let b = hsla(0.05, 0.5, 0.5, 1.0);
        let m = mix(a, b, 0.5);
        assert!(m.h < 0.01 || m.h > 0.99, "{}", m.h);
    }

    fn luminance(color: Hsla) -> f32 {
        let rgba = Rgba::from(color);
        let linear = |c: f32| {
            if c <= 0.040_45 {
                c / 12.92
            } else {
                ((c + 0.055) / 1.055).powf(2.4)
            }
        };
        0.2126 * linear(rgba.r) + 0.7152 * linear(rgba.g) + 0.0722 * linear(rgba.b)
    }

    /// `top` (which may be translucent) drawn over the opaque `bottom`.
    fn over(top: Hsla, bottom: Hsla) -> Hsla {
        let (t, b) = (Rgba::from(top), Rgba::from(bottom));
        let a = t.a;
        Hsla::from(Rgba {
            r: t.r * a + b.r * (1.0 - a),
            g: t.g * a + b.g * (1.0 - a),
            b: t.b * a + b.b * (1.0 - a),
            a: 1.0,
        })
    }

    fn contrast(a: Hsla, b: Hsla) -> f32 {
        let (la, lb) = (luminance(a), luminance(b));
        (la.max(lb) + 0.05) / (la.min(lb) + 0.05)
    }

    /// Every point of the sidebar (the left fifth of the window), for every
    /// theme, keeps text readable: AAA for titles, AA for secondary text,
    /// and AA for the selected row's text on its raised background.
    #[test]
    fn text_stays_readable_on_every_gradient() {
        for gradient in SpaceGradient::all() {
            let theme = CurioTheme::new(gradient);
            let spec = gradient.spec();
            for i in 0..=8 {
                for j in 0..=20 {
                    let (x, y) = (i as f32 * 0.025, j as f32 / 20.0);
                    let [r, g, b] = spec.sample(x, y, 1.6);
                    let bg = Hsla::from(Rgba { r, g, b, a: 1.0 });
                    let text = contrast(over(theme.text, bg), bg);
                    let muted = contrast(over(theme.text_muted, bg), bg);
                    let selected_bg = over(theme.row_active, bg);
                    let selected = contrast(over(theme.row_active_text, selected_bg), selected_bg);
                    assert!(text >= 7.0, "{gradient:?} text {text:.1} at {x},{y}");
                    assert!(muted >= 4.5, "{gradient:?} muted {muted:.1} at {x},{y}");
                    assert!(
                        selected >= 4.5,
                        "{gradient:?} selected {selected:.1} at {x},{y}"
                    );
                }
            }
        }
    }

    #[test]
    fn tone_sets_the_appearance() {
        assert_eq!(
            CurioTheme::new(SpaceGradient::LavenderBlush).appearance,
            Appearance::Light
        );
        assert_eq!(
            CurioTheme::new(SpaceGradient::Forest).appearance,
            Appearance::Dark
        );
    }
}
