//! Curio's design system.
//!
//! The chrome takes its color from the active space, like Arc: a soft tinted
//! gradient behind the sidebar with the page floating on top as a card.
//! [`CurioTheme`] holds the derived tokens and is recomputed when the space
//! accent or the light/dark appearance changes. The GPUI Kit component theme
//! is kept in step so inputs, menus and dialogs share the accent.

use curio_core::AccentColor;
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
    pub accent_color: AccentColor,
    /// The pure accent, for focus rings and primary buttons.
    pub accent: Hsla,
    /// A soft accent wash for selected rows and chips.
    pub accent_soft: Hsla,
    /// Accent-tinted text that stays legible on the chrome.
    pub accent_text: Hsla,
    /// Window chrome gradient (top and bottom).
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

    pub const CARD_RADIUS: Pixels = px(10.);
    pub const ROW_RADIUS: Pixels = px(8.);
    pub const ROW_HEIGHT: Pixels = px(34.);
    pub const FIELD_RADIUS: Pixels = px(9.);
    pub const PANEL_GAP: Pixels = px(8.);
    /// Space reserved for the macOS traffic lights in the sidebar header.
    pub const TRAFFIC_LIGHTS_WIDTH: Pixels = px(76.);
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
    /// Computes tokens for an accent and appearance.
    #[must_use]
    pub fn new(accent_color: AccentColor, appearance: Appearance) -> Self {
        let accent = hex(accent_color.rgb());
        let h = accent.h;
        // Graphite is intentionally almost neutral.
        let tint = if accent_color == AccentColor::Graphite {
            0.06
        } else {
            1.0
        };
        match appearance {
            Appearance::Light => Self {
                appearance,
                accent_color,
                accent,
                accent_soft: with_alpha(accent, 0.14),
                accent_text: hsla(h, (accent.s * 0.9).min(0.85), 0.36, 1.0),
                chrome_top: hsla(h, 0.55 * tint, 0.905, 1.0),
                chrome_bottom: hsla((h + 0.03).rem_euclid(1.0), 0.48 * tint, 0.855, 1.0),
                text: hsla(h, 0.12 * tint, 0.13, 1.0),
                text_muted: hsla(h, 0.10 * tint, 0.13, 0.62),
                text_faint: hsla(h, 0.10 * tint, 0.13, 0.40),
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
                accent_color,
                accent: hsla(h, accent.s.min(0.85), accent.l.max(0.62), 1.0),
                accent_soft: hsla(h, accent.s, 0.62, 0.20),
                accent_text: hsla(h, (accent.s * 0.9).min(0.85), 0.78, 1.0),
                chrome_top: hsla(h, 0.24 * tint, 0.155, 1.0),
                chrome_bottom: hsla((h + 0.03).rem_euclid(1.0), 0.20 * tint, 0.115, 1.0),
                text: hsla(h, 0.10 * tint, 0.93, 1.0),
                text_muted: hsla(h, 0.08 * tint, 0.93, 0.62),
                text_faint: hsla(h, 0.08 * tint, 0.93, 0.38),
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

    /// Installs tokens for `accent` and `appearance`, and keeps the component
    /// library theme in step.
    pub fn apply(accent: AccentColor, appearance: Appearance, window: Option<&mut Window>, cx: &mut App) {
        let tokens = Self::new(accent, appearance);
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
            theme.ring = with_alpha(tokens.accent, 0.55);
            theme.caret = tokens.accent;
            theme.selection = with_alpha(tokens.accent, 0.28);
            theme.link = tokens.accent_text;
            theme.link_hover = tokens.accent;
            theme.popover = tokens.surface_raised;
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
    /// appearance.
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

    #[test]
    fn light_and_dark_text_contrast_with_chrome() {
        for accent in AccentColor::ALL {
            let light = CurioTheme::new(accent, Appearance::Light);
            assert!(light.chrome_top.l - light.text.l > 0.6);
            let dark = CurioTheme::new(accent, Appearance::Dark);
            assert!(dark.text.l - dark.chrome_top.l > 0.6);
        }
    }
}
