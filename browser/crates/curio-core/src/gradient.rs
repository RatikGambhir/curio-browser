//! Space themes: soft, atmospheric gradients behind the window chrome.
//!
//! Each theme is a diagonal linear gradient with 4 stops, plus 2–3 large,
//! faint radial glows that add depth without reading as shapes. Colors blend
//! in OKLab, which keeps transitions even and avoids the muddy middle a
//! plain RGB blend gives. [`GradientSpec::render_rgba`] paints a theme into
//! a bitmap with light dithering so wide, low-contrast ramps don't band.
//!
//! Coordinates cover the whole window: `x` runs 0 → 1 left to right and `y`
//! 0 → 1 top to bottom. The sidebar only shows the left fifth, so each theme
//! changes mostly from top to bottom, with glows near the left edge.
//!
//! A theme's [`Tone`] decides whether the chrome on top of it is light or
//! dark, whatever the system appearance is.

use serde::{Deserialize, Serialize};

use crate::AccentColor;

/// Whether a theme is light (dark text) or dark (light text).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Tone {
    Light,
    Dark,
}

/// One color stop on the base gradient.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Stop {
    /// `0xRRGGBB`.
    pub rgb: u32,
    /// Position along the gradient, 0 to 1.
    pub at: f32,
}

/// A large, soft radial glow blended over the base gradient.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Glow {
    /// `0xRRGGBB`.
    pub rgb: u32,
    /// Center, in window coordinates (0 to 1).
    pub x: f32,
    pub y: f32,
    /// Size, as a fraction of the window height. The glow fades smoothly
    /// (Gaussian), so there is no visible edge.
    pub radius: f32,
    /// How much of the glow color shows at the center, 0 to 1.
    pub strength: f32,
}

/// Everything needed to paint a theme.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GradientSpec {
    /// Direction of the base gradient in CSS degrees (180 = top to bottom).
    pub angle: f32,
    pub stops: &'static [Stop],
    pub glows: &'static [Glow],
}

/// Mostly top to bottom, tilted slightly toward the bottom right.
const ANGLE: f32 = 162.0;

/// A space's theme. Spaces store the name.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum SpaceGradient {
    // Light
    #[default]
    LavenderBlush,
    SkyHaze,
    MintCream,
    PeachGlow,
    RoseFog,
    Aurora,
    Iris,
    Periwinkle,
    Sand,
    Citrus,
    // Dark
    MidnightIndigo,
    Forest,
    OceanDepths,
    PlumNight,
    Burgundy,
    Slate,
    TealDrift,
    BlueFlame,
    SunsetDusk,
    Ember,
}

impl SpaceGradient {
    /// The light themes, in picker order.
    pub const LIGHT: [Self; 10] = [
        Self::LavenderBlush,
        Self::SkyHaze,
        Self::MintCream,
        Self::PeachGlow,
        Self::RoseFog,
        Self::Aurora,
        Self::Iris,
        Self::Periwinkle,
        Self::Sand,
        Self::Citrus,
    ];

    /// The dark themes, in picker order.
    pub const DARK: [Self; 10] = [
        Self::MidnightIndigo,
        Self::Forest,
        Self::OceanDepths,
        Self::PlumNight,
        Self::Burgundy,
        Self::Slate,
        Self::TealDrift,
        Self::BlueFlame,
        Self::SunsetDusk,
        Self::Ember,
    ];

    /// Every theme: the light ones, then the dark ones.
    pub fn all() -> impl Iterator<Item = Self> {
        Self::LIGHT.into_iter().chain(Self::DARK)
    }

    /// A display name for the picker.
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Self::LavenderBlush => "Lavender Blush",
            Self::SkyHaze => "Sky Haze",
            Self::MintCream => "Mint Cream",
            Self::PeachGlow => "Peach Glow",
            Self::RoseFog => "Rose Fog",
            Self::Aurora => "Aurora",
            Self::Iris => "Iris",
            Self::Periwinkle => "Periwinkle",
            Self::Sand => "Sand",
            Self::Citrus => "Citrus",
            Self::MidnightIndigo => "Midnight Indigo",
            Self::Forest => "Forest",
            Self::OceanDepths => "Ocean Depths",
            Self::PlumNight => "Plum Night",
            Self::Burgundy => "Burgundy",
            Self::Slate => "Slate",
            Self::TealDrift => "Teal Drift",
            Self::BlueFlame => "Blue Flame",
            Self::SunsetDusk => "Sunset Dusk",
            Self::Ember => "Ember",
        }
    }

    /// Whether the chrome on this theme is light or dark.
    #[must_use]
    pub fn tone(self) -> Tone {
        if Self::LIGHT.contains(&self) {
            Tone::Light
        } else {
            Tone::Dark
        }
    }

    /// The accent for selection, focus rings and buttons, as `0xRRGGBB`.
    /// Picked to sit with the gradient while staying legible on it.
    #[must_use]
    pub const fn accent_rgb(self) -> u32 {
        match self {
            Self::LavenderBlush => 0x7C62E8,
            Self::SkyHaze => 0x2F86E0,
            Self::MintCream => 0x2E9A6A,
            Self::PeachGlow => 0xE0694B,
            Self::RoseFog => 0xC9568F,
            Self::Aurora => 0x3C82E6,
            Self::Iris => 0x6E5BF5,
            Self::Periwinkle => 0x5B6CF0,
            Self::Sand => 0xB7803A,
            Self::Citrus => 0x6E9E2A,
            Self::MidnightIndigo => 0x8C7CF5,
            Self::Forest => 0x3FBF8F,
            Self::OceanDepths => 0x3AB0C8,
            Self::PlumNight => 0xB07CE0,
            Self::Burgundy => 0xE0628F,
            Self::Slate => 0x7F9CC8,
            Self::TealDrift => 0x3CC4A6,
            Self::BlueFlame => 0x5C82F0,
            Self::SunsetDusk => 0xF08A6E,
            Self::Ember => 0xF0904A,
        }
    }

    /// The colors to paint.
    #[must_use]
    #[rustfmt::skip]
    pub const fn spec(self) -> GradientSpec {
        let (stops, glows): (&'static [Stop], &'static [Glow]) = match self {
            // Lavender, lilac, pale pink.
            Self::LavenderBlush => (
                &[
                    Stop { rgb: 0xD8D6FB, at: 0.0 },
                    Stop { rgb: 0xE3DAFA, at: 0.38 },
                    Stop { rgb: 0xF1DEF2, at: 0.72 },
                    Stop { rgb: 0xFCE6E8, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0xCDC6FF, x: 0.04, y: 0.06, radius: 0.55, strength: 0.40 },
                    Glow { rgb: 0xFFD9E2, x: 0.12, y: 0.98, radius: 0.60, strength: 0.40 },
                    Glow { rgb: 0xE8E2FF, x: 0.92, y: 0.00, radius: 0.50, strength: 0.25 },
                ],
            ),
            // Powder blue, icy cyan, mint.
            Self::SkyHaze => (
                &[
                    Stop { rgb: 0xD2E6FF, at: 0.0 },
                    Stop { rgb: 0xDAEEFD, at: 0.38 },
                    Stop { rgb: 0xE1F6F8, at: 0.72 },
                    Stop { rgb: 0xE8FDF4, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0xC4DDFF, x: 0.04, y: 0.08, radius: 0.55, strength: 0.40 },
                    Glow { rgb: 0xD9FAEC, x: 0.15, y: 0.98, radius: 0.60, strength: 0.40 },
                    Glow { rgb: 0xD4F2FF, x: 0.88, y: 0.02, radius: 0.50, strength: 0.25 },
                ],
            ),
            // Pale mint, sage, warm ivory.
            Self::MintCream => (
                &[
                    Stop { rgb: 0xDDF8E8, at: 0.0 },
                    Stop { rgb: 0xE2F1E0, at: 0.38 },
                    Stop { rgb: 0xF1F6E0, at: 0.72 },
                    Stop { rgb: 0xFFF9DE, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0xCFEFDC, x: 0.04, y: 0.08, radius: 0.55, strength: 0.40 },
                    Glow { rgb: 0xFFF2CF, x: 0.15, y: 0.98, radius: 0.60, strength: 0.35 },
                    Glow { rgb: 0xDCEDD6, x: 0.85, y: 0.05, radius: 0.50, strength: 0.25 },
                ],
            ),
            // Soft coral, peach, cream.
            Self::PeachGlow => (
                &[
                    Stop { rgb: 0xFFDACE, at: 0.0 },
                    Stop { rgb: 0xFFE2D3, at: 0.36 },
                    Stop { rgb: 0xFFEAD9, at: 0.70 },
                    Stop { rgb: 0xFFF3E2, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0xFFCABB, x: 0.04, y: 0.04, radius: 0.55, strength: 0.40 },
                    Glow { rgb: 0xFFEFD6, x: 0.18, y: 0.98, radius: 0.60, strength: 0.35 },
                    Glow { rgb: 0xFFD6CC, x: 0.90, y: 0.00, radius: 0.45, strength: 0.25 },
                ],
            ),
            // Dusty rose, lilac, pale lavender.
            Self::RoseFog => (
                &[
                    Stop { rgb: 0xF4D4E5, at: 0.0 },
                    Stop { rgb: 0xEED8ED, at: 0.38 },
                    Stop { rgb: 0xE7DCF5, at: 0.72 },
                    Stop { rgb: 0xE2DFFC, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0xEFC8DC, x: 0.04, y: 0.06, radius: 0.55, strength: 0.40 },
                    Glow { rgb: 0xDAD6FF, x: 0.15, y: 0.98, radius: 0.60, strength: 0.40 },
                    Glow { rgb: 0xF6DCEB, x: 0.90, y: 0.02, radius: 0.45, strength: 0.20 },
                ],
            ),
            // Icy cyan into soft periwinkle.
            Self::Aurora => (
                &[
                    Stop { rgb: 0xD6EEFF, at: 0.0 },
                    Stop { rgb: 0xD9ECFB, at: 0.36 },
                    Stop { rgb: 0xD9E6FD, at: 0.70 },
                    Stop { rgb: 0xDCDFFF, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0xCDF3F5, x: 0.04, y: 0.08, radius: 0.55, strength: 0.40 },
                    Glow { rgb: 0xE1D8FF, x: 0.18, y: 0.98, radius: 0.60, strength: 0.35 },
                    Glow { rgb: 0xD3F0FF, x: 0.90, y: 0.00, radius: 0.45, strength: 0.20 },
                ],
            ),
            // Violet into orchid.
            Self::Iris => (
                &[
                    Stop { rgb: 0xCDC7FF, at: 0.0 },
                    Stop { rgb: 0xD6CDFE, at: 0.36 },
                    Stop { rgb: 0xE1D4FD, at: 0.70 },
                    Stop { rgb: 0xECDCFF, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0xC3BDFF, x: 0.04, y: 0.06, radius: 0.55, strength: 0.40 },
                    Glow { rgb: 0xF1DCFA, x: 0.15, y: 0.98, radius: 0.60, strength: 0.35 },
                    Glow { rgb: 0xD9D3FF, x: 0.90, y: 0.00, radius: 0.45, strength: 0.20 },
                ],
            ),
            // Powder blue, periwinkle, violet.
            Self::Periwinkle => (
                &[
                    Stop { rgb: 0xC2D9FF, at: 0.0 },
                    Stop { rgb: 0xC6D2FE, at: 0.38 },
                    Stop { rgb: 0xC9CAFD, at: 0.70 },
                    Stop { rgb: 0xCEC4FD, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0xB9DBFF, x: 0.04, y: 0.06, radius: 0.55, strength: 0.40 },
                    Glow { rgb: 0xD4C4FF, x: 0.15, y: 0.98, radius: 0.60, strength: 0.35 },
                    Glow { rgb: 0xC8DEFF, x: 0.90, y: 0.00, radius: 0.45, strength: 0.20 },
                ],
            ),
            // Warm sand into cream.
            Self::Sand => (
                &[
                    Stop { rgb: 0xF4E3CB, at: 0.0 },
                    Stop { rgb: 0xF7E9D5, at: 0.38 },
                    Stop { rgb: 0xFAEFDF, at: 0.70 },
                    Stop { rgb: 0xFEF5E8, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0xEFDABF, x: 0.04, y: 0.06, radius: 0.55, strength: 0.40 },
                    Glow { rgb: 0xFFEEDA, x: 0.18, y: 0.98, radius: 0.60, strength: 0.30 },
                    Glow { rgb: 0xF6E6D2, x: 0.90, y: 0.00, radius: 0.45, strength: 0.20 },
                ],
            ),
            // Pale lemon into soft lime.
            Self::Citrus => (
                &[
                    Stop { rgb: 0xFFF5C2, at: 0.0 },
                    Stop { rgb: 0xF8F8C8, at: 0.38 },
                    Stop { rgb: 0xEEFACE, at: 0.70 },
                    Stop { rgb: 0xE3FCD6, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0xFFEFB6, x: 0.04, y: 0.04, radius: 0.55, strength: 0.40 },
                    Glow { rgb: 0xDBF8D2, x: 0.18, y: 0.98, radius: 0.60, strength: 0.35 },
                    Glow { rgb: 0xFBF6CC, x: 0.90, y: 0.00, radius: 0.45, strength: 0.20 },
                ],
            ),
            // Charcoal navy, indigo, muted violet.
            Self::MidnightIndigo => (
                &[
                    Stop { rgb: 0x14182A, at: 0.0 },
                    Stop { rgb: 0x1B2040, at: 0.36 },
                    Stop { rgb: 0x282A54, at: 0.70 },
                    Stop { rgb: 0x353164, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0x4B3F8C, x: 0.10, y: 0.98, radius: 0.60, strength: 0.35 },
                    Glow { rgb: 0x232E6A, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30 },
                    Glow { rgb: 0x3A3478, x: 0.02, y: 0.55, radius: 0.40, strength: 0.15 },
                ],
            ),
            // Deep evergreen, dark teal, emerald.
            Self::Forest => (
                &[
                    Stop { rgb: 0x0D2620, at: 0.0 },
                    Stop { rgb: 0x113428, at: 0.36 },
                    Stop { rgb: 0x164537, at: 0.70 },
                    Stop { rgb: 0x1C5F50, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0x2A8466, x: 0.12, y: 0.98, radius: 0.60, strength: 0.30 },
                    Glow { rgb: 0x0F3A3A, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30 },
                    Glow { rgb: 0x1D5A48, x: 0.02, y: 0.50, radius: 0.40, strength: 0.15 },
                ],
            ),
            // Midnight blue, petrol blue, muted cyan.
            Self::OceanDepths => (
                &[
                    Stop { rgb: 0x0C2036, at: 0.0 },
                    Stop { rgb: 0x0F2E48, at: 0.36 },
                    Stop { rgb: 0x14435B, at: 0.70 },
                    Stop { rgb: 0x1A5768, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0x27788A, x: 0.12, y: 0.98, radius: 0.60, strength: 0.30 },
                    Glow { rgb: 0x113866, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30 },
                    Glow { rgb: 0x165065, x: 0.02, y: 0.50, radius: 0.40, strength: 0.15 },
                ],
            ),
            // Near-black purple, plum, dusty violet.
            Self::PlumNight => (
                &[
                    Stop { rgb: 0x1C1127, at: 0.0 },
                    Stop { rgb: 0x281938, at: 0.36 },
                    Stop { rgb: 0x37234D, at: 0.70 },
                    Stop { rgb: 0x452960, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0x664084, x: 0.12, y: 0.98, radius: 0.60, strength: 0.30 },
                    Glow { rgb: 0x321F4A, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30 },
                    Glow { rgb: 0x4A2E66, x: 0.02, y: 0.50, radius: 0.40, strength: 0.15 },
                ],
            ),
            // Deep wine, burgundy, muted raspberry.
            Self::Burgundy => (
                &[
                    Stop { rgb: 0x240F1A, at: 0.0 },
                    Stop { rgb: 0x341424, at: 0.36 },
                    Stop { rgb: 0x46192F, at: 0.70 },
                    Stop { rgb: 0x561D38, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0x7A2D50, x: 0.12, y: 0.98, radius: 0.55, strength: 0.30 },
                    Glow { rgb: 0x3A142E, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30 },
                    Glow { rgb: 0x5A2040, x: 0.02, y: 0.50, radius: 0.40, strength: 0.15 },
                ],
            ),
            // Blue-gray charcoal.
            Self::Slate => (
                &[
                    Stop { rgb: 0x0E141D, at: 0.0 },
                    Stop { rgb: 0x151F2B, at: 0.36 },
                    Stop { rgb: 0x202B3B, at: 0.70 },
                    Stop { rgb: 0x2C384C, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0x3D4D66, x: 0.12, y: 0.98, radius: 0.60, strength: 0.30 },
                    Glow { rgb: 0x1A2636, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30 },
                    Glow { rgb: 0x2A3A50, x: 0.02, y: 0.50, radius: 0.40, strength: 0.12 },
                ],
            ),
            // Dark teal, turquoise, desaturated jade.
            Self::TealDrift => (
                &[
                    Stop { rgb: 0x0D2E36, at: 0.0 },
                    Stop { rgb: 0x103D3E, at: 0.36 },
                    Stop { rgb: 0x13483F, at: 0.70 },
                    Stop { rgb: 0x164E43, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0x1F6656, x: 0.12, y: 0.98, radius: 0.55, strength: 0.25 },
                    Glow { rgb: 0x11444E, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30 },
                    Glow { rgb: 0x1A5B58, x: 0.02, y: 0.50, radius: 0.40, strength: 0.15 },
                ],
            ),
            // Deep navy into cobalt.
            Self::BlueFlame => (
                &[
                    Stop { rgb: 0x161B43, at: 0.0 },
                    Stop { rgb: 0x1C2557, at: 0.36 },
                    Stop { rgb: 0x24357A, at: 0.70 },
                    Stop { rgb: 0x2C4596, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0x3A5EC0, x: 0.12, y: 0.98, radius: 0.55, strength: 0.30 },
                    Glow { rgb: 0x221D58, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30 },
                    Glow { rgb: 0x2A3C88, x: 0.02, y: 0.50, radius: 0.40, strength: 0.15 },
                ],
            ),
            // Dark plum, dusty rose, warm coral.
            Self::SunsetDusk => (
                &[
                    Stop { rgb: 0x23132B, at: 0.0 },
                    Stop { rgb: 0x381B37, at: 0.36 },
                    Stop { rgb: 0x552741, at: 0.70 },
                    Stop { rgb: 0x763647, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0xA4504C, x: 0.12, y: 1.0, radius: 0.55, strength: 0.35 },
                    Glow { rgb: 0x381C42, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30 },
                    Glow { rgb: 0x5E2C48, x: 0.02, y: 0.50, radius: 0.40, strength: 0.15 },
                ],
            ),
            // Dark espresso, burnt orange, copper.
            Self::Ember => (
                &[
                    Stop { rgb: 0x21120A, at: 0.0 },
                    Stop { rgb: 0x31180D, at: 0.36 },
                    Stop { rgb: 0x522610, at: 0.70 },
                    Stop { rgb: 0x763512, at: 1.0 },
                ],
                &[
                    Glow { rgb: 0xA24E1A, x: 0.12, y: 1.0, radius: 0.55, strength: 0.30 },
                    Glow { rgb: 0x2E1A10, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30 },
                    Glow { rgb: 0x5A2C14, x: 0.02, y: 0.50, radius: 0.40, strength: 0.15 },
                ],
            ),
        };
        GradientSpec {
            angle: ANGLE,
            stops,
            glows,
        }
    }

    /// The next theme with the same tone, wrapping around. New spaces take
    /// the theme after the last space's, so each starts out different.
    #[must_use]
    pub fn next(self) -> Self {
        let group = match self.tone() {
            Tone::Light => &Self::LIGHT,
            Tone::Dark => &Self::DARK,
        };
        let index = group.iter().position(|g| *g == self).unwrap_or(0);
        group[(index + 1) % group.len()]
    }

    /// The theme for a space saved before themes existed, from its accent.
    #[must_use]
    pub const fn from_accent(accent: AccentColor) -> Self {
        match accent {
            AccentColor::Iris => Self::Iris,
            AccentColor::Ocean => Self::SkyHaze,
            AccentColor::Lagoon | AccentColor::Graphite => Self::Aurora,
            AccentColor::Sage => Self::MintCream,
            AccentColor::Citrine => Self::Citrus,
            AccentColor::Amber => Self::Sand,
            AccentColor::Coral => Self::PeachGlow,
            AccentColor::Rose => Self::RoseFog,
            AccentColor::Plum => Self::LavenderBlush,
        }
    }

    /// The closest accent, for places that still store one (and older builds
    /// reading the database).
    #[must_use]
    pub const fn legacy_accent(self) -> AccentColor {
        match self {
            Self::LavenderBlush | Self::PlumNight => AccentColor::Plum,
            Self::SkyHaze | Self::Periwinkle | Self::BlueFlame => AccentColor::Ocean,
            Self::MintCream | Self::Forest => AccentColor::Sage,
            Self::PeachGlow | Self::SunsetDusk => AccentColor::Coral,
            Self::RoseFog | Self::Burgundy => AccentColor::Rose,
            Self::Aurora | Self::OceanDepths | Self::TealDrift => AccentColor::Lagoon,
            Self::Iris | Self::MidnightIndigo => AccentColor::Iris,
            Self::Sand | Self::Ember => AccentColor::Amber,
            Self::Citrus => AccentColor::Citrine,
            Self::Slate => AccentColor::Graphite,
        }
    }
}

// ----- Painting ----------------------------------------------------------

/// A color in OKLab.
#[derive(Debug, Clone, Copy, PartialEq)]
struct Lab {
    l: f32,
    a: f32,
    b: f32,
}

impl Lab {
    fn lerp(self, other: Self, t: f32) -> Self {
        Self {
            l: self.l + (other.l - self.l) * t,
            a: self.a + (other.a - self.a) * t,
            b: self.b + (other.b - self.b) * t,
        }
    }
}

fn srgb_to_linear(c: f32) -> f32 {
    if c <= 0.040_45 {
        c / 12.92
    } else {
        ((c + 0.055) / 1.055).powf(2.4)
    }
}

fn linear_to_srgb(c: f32) -> f32 {
    let c = c.clamp(0.0, 1.0);
    if c <= 0.003_130_8 {
        c * 12.92
    } else {
        1.055 * c.powf(1.0 / 2.4) - 0.055
    }
}

/// `0xRRGGBB` as sRGB components, 0 to 1.
#[must_use]
pub fn rgb_components(rgb: u32) -> [f32; 3] {
    [
        ((rgb >> 16) & 0xff) as f32 / 255.0,
        ((rgb >> 8) & 0xff) as f32 / 255.0,
        (rgb & 0xff) as f32 / 255.0,
    ]
}

fn to_lab(rgb: u32) -> Lab {
    let [r, g, b] = rgb_components(rgb).map(srgb_to_linear);
    let l = (0.412_221_46 * r + 0.536_332_55 * g + 0.051_445_995 * b).cbrt();
    let m = (0.211_903_5 * r + 0.680_699_5 * g + 0.107_396_96 * b).cbrt();
    let s = (0.088_302_46 * r + 0.281_718_85 * g + 0.629_978_7 * b).cbrt();
    Lab {
        l: 0.210_454_26 * l + 0.793_617_8 * m - 0.004_072_047 * s,
        a: 1.977_998_5 * l - 2.428_592_2 * m + 0.450_593_7 * s,
        b: 0.025_904_037 * l + 0.782_771_77 * m - 0.808_675_77 * s,
    }
}

fn to_srgb(lab: Lab) -> [f32; 3] {
    let l = (lab.l + 0.396_337_78 * lab.a + 0.215_803_76 * lab.b).powi(3);
    let m = (lab.l - 0.105_561_346 * lab.a - 0.063_854_17 * lab.b).powi(3);
    let s = (lab.l - 0.089_484_18 * lab.a - 1.291_485_5 * lab.b).powi(3);
    [
        4.076_741_7 * l - 3.307_711_6 * m + 0.230_969_94 * s,
        -1.268_438 * l + 2.609_757_4 * m - 0.341_319_38 * s,
        -0.004_196_086_3 * l - 0.703_418_6 * m + 1.707_614_7 * s,
    ]
    .map(linear_to_srgb)
}

/// A spec with its colors converted once, ready to sample many times.
struct Prepared {
    /// Unit direction of the base gradient, in window pixels.
    dir: (f32, f32),
    stops: Vec<(f32, Lab)>,
    glows: Vec<(Glow, Lab)>,
}

impl GradientSpec {
    fn prepare(&self) -> Prepared {
        let radians = self.angle.to_radians();
        Prepared {
            // CSS angles: 0° points up, 90° right, 180° down (y grows down).
            dir: (radians.sin(), -radians.cos()),
            stops: self.stops.iter().map(|s| (s.at, to_lab(s.rgb))).collect(),
            glows: self.glows.iter().map(|g| (*g, to_lab(g.rgb))).collect(),
        }
    }

    /// The sRGB color (0 to 1) at window coordinates `x`, `y` for a window
    /// `aspect` (width / height) wide.
    #[must_use]
    pub fn sample(&self, x: f32, y: f32, aspect: f32) -> [f32; 3] {
        self.prepare().sample(x, y, aspect)
    }

    /// Paints the theme into a `width` × `height` RGBA bitmap, dithered so
    /// it stays smooth when scaled up.
    #[must_use]
    pub fn render_rgba(&self, width: u32, height: u32) -> Vec<u8> {
        let prepared = self.prepare();
        let aspect = width as f32 / height.max(1) as f32;
        let mut pixels = Vec::with_capacity(width as usize * height as usize * 4);
        for py in 0..height {
            for px in 0..width {
                let x = (px as f32 + 0.5) / width as f32;
                let y = (py as f32 + 0.5) / height as f32;
                let color = prepared.sample(x, y, aspect);
                let noise = dither(px, py);
                for c in color {
                    let value = (c * 255.0 + noise).round().clamp(0.0, 255.0);
                    pixels.push(value as u8);
                }
                pixels.push(255);
            }
        }
        pixels
    }
}

impl Prepared {
    fn sample(&self, x: f32, y: f32, aspect: f32) -> [f32; 3] {
        // Project onto the gradient line, CSS style: the line is just long
        // enough for both ends to touch opposite corners.
        let (dx, dy) = self.dir;
        let length = (aspect * dx).abs() + dy.abs();
        let t = (((x - 0.5) * aspect * dx + (y - 0.5) * dy) / length + 0.5).clamp(0.0, 1.0);
        let mut color = self.base(t);
        for (glow, lab) in &self.glows {
            let gx = (x - glow.x) * aspect;
            let gy = y - glow.y;
            let d2 = (gx * gx + gy * gy) / (glow.radius * glow.radius);
            let amount = glow.strength * (-2.0 * d2).exp();
            color = color.lerp(*lab, amount);
        }
        to_srgb(color)
    }

    fn base(&self, t: f32) -> Lab {
        let Some(&(first_at, first)) = self.stops.first() else {
            return Lab {
                l: 0.0,
                a: 0.0,
                b: 0.0,
            };
        };
        if t <= first_at {
            return first;
        }
        for pair in self.stops.windows(2) {
            let ((a_at, a), (b_at, b)) = (pair[0], pair[1]);
            if t <= b_at {
                let span = (b_at - a_at).max(f32::EPSILON);
                return a.lerp(b, (t - a_at) / span);
            }
        }
        self.stops.last().map_or(first, |&(_, last)| last)
    }
}

/// Triangular noise of ±1 level, the same for a pixel every time.
fn dither(x: u32, y: u32) -> f32 {
    fn hash(mut n: u32) -> f32 {
        n ^= n >> 16;
        n = n.wrapping_mul(0x7feb_352d);
        n ^= n >> 15;
        n = n.wrapping_mul(0x846c_a68b);
        n ^= n >> 16;
        (n & 0xffff) as f32 / 65_535.0
    }
    let seed = x.wrapping_mul(1_973).wrapping_add(y.wrapping_mul(9_277));
    hash(seed) - hash(seed ^ 0x9e37_79b9)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn luminance([r, g, b]: [f32; 3]) -> f32 {
        let [r, g, b] = [r, g, b].map(srgb_to_linear);
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    #[test]
    fn twenty_themes_split_evenly_by_tone() {
        assert_eq!(SpaceGradient::all().count(), 20);
        assert!(SpaceGradient::LIGHT.iter().all(|g| g.tone() == Tone::Light));
        assert!(SpaceGradient::DARK.iter().all(|g| g.tone() == Tone::Dark));
    }

    #[test]
    fn specs_have_three_to_five_ordered_stops() {
        for gradient in SpaceGradient::all() {
            let spec = gradient.spec();
            assert!((3..=5).contains(&spec.stops.len()), "{gradient:?}");
            assert!(spec.stops.windows(2).all(|p| p[0].at < p[1].at));
            assert!((1..=3).contains(&spec.glows.len()), "{gradient:?}");
            // Glows stay subtle: no hard spots.
            assert!(
                spec.glows
                    .iter()
                    .all(|g| g.strength <= 0.4 && g.radius >= 0.4)
            );
        }
    }

    #[test]
    fn light_themes_stay_light_and_dark_themes_stay_dark() {
        for gradient in SpaceGradient::all() {
            let spec = gradient.spec();
            for i in 0..=10 {
                for j in 0..=10 {
                    let l = luminance(spec.sample(i as f32 / 10.0, j as f32 / 10.0, 1.6));
                    match gradient.tone() {
                        Tone::Light => assert!(l > 0.5, "{gradient:?} too dark: {l}"),
                        Tone::Dark => assert!(l < 0.12, "{gradient:?} too bright: {l}"),
                    }
                }
            }
        }
    }

    #[test]
    fn oklab_round_trips() {
        for rgb in [0x000000, 0xFFFFFF, 0x7C62E8, 0x1C5F50, 0xFCE6E8] {
            let back = to_srgb(to_lab(rgb));
            let expected = rgb_components(rgb);
            for (a, b) in back.iter().zip(expected) {
                assert!((a - b).abs() < 0.002, "{rgb:06x}: {back:?} vs {expected:?}");
            }
        }
    }

    #[test]
    fn rendering_is_smooth_with_no_hard_edges() {
        for gradient in SpaceGradient::all() {
            let (w, h) = (48, 300);
            let pixels = gradient.spec().render_rgba(w, h);
            assert_eq!(pixels.len(), (w * h * 4) as usize);
            for y in 1..h {
                for x in 0..w {
                    let i = ((y * w + x) * 4) as usize;
                    let above = i - (w * 4) as usize;
                    for c in 0..3 {
                        let step = (i32::from(pixels[i + c]) - i32::from(pixels[above + c])).abs();
                        // Dithering adds ±1; the gradient itself moves slowly.
                        assert!(step <= 4, "{gradient:?} jumps {step} at {x},{y}");
                    }
                }
            }
        }
    }

    #[test]
    fn next_stays_within_the_tone() {
        let mut gradient = SpaceGradient::Forest;
        for _ in 0..SpaceGradient::DARK.len() {
            gradient = gradient.next();
            assert_eq!(gradient.tone(), Tone::Dark);
        }
        assert_eq!(gradient, SpaceGradient::Forest);
    }

    #[test]
    fn old_accents_map_to_light_themes() {
        for accent in AccentColor::ALL {
            assert_eq!(SpaceGradient::from_accent(accent).tone(), Tone::Light);
        }
    }

    #[test]
    fn names_are_stable_for_storage() {
        assert_eq!(
            serde_json::to_string(&SpaceGradient::MidnightIndigo).ok(),
            Some("\"midnight_indigo\"".to_owned())
        );
    }
}
