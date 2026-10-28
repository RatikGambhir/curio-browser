//! Accent colors shared by spaces and tab groups.

use serde::{Deserialize, Serialize};

/// A curated accent palette. Spaces and groups store the name, and the UI
/// layer derives tints for light and dark appearance from [`AccentColor::rgb`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum AccentColor {
    /// Curio's signature violet.
    #[default]
    Iris,
    Ocean,
    Lagoon,
    Sage,
    Citrine,
    Amber,
    Coral,
    Rose,
    Plum,
    Graphite,
}

impl AccentColor {
    /// Every accent, in palette order.
    pub const ALL: [Self; 10] = [
        Self::Iris,
        Self::Ocean,
        Self::Lagoon,
        Self::Sage,
        Self::Citrine,
        Self::Amber,
        Self::Coral,
        Self::Rose,
        Self::Plum,
        Self::Graphite,
    ];

    /// The base color as `0xRRGGBB`.
    #[must_use]
    pub const fn rgb(self) -> u32 {
        match self {
            Self::Iris => 0x6E5BF5,
            Self::Ocean => 0x2F7CF6,
            Self::Lagoon => 0x12A5B5,
            Self::Sage => 0x3E9E6B,
            Self::Citrine => 0xC9A317,
            Self::Amber => 0xE58A1F,
            Self::Coral => 0xEC5F4E,
            Self::Rose => 0xDF4A86,
            Self::Plum => 0x9A4BD0,
            Self::Graphite => 0x5E6673,
        }
    }

    /// A display name for menus and settings.
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Self::Iris => "Iris",
            Self::Ocean => "Ocean",
            Self::Lagoon => "Lagoon",
            Self::Sage => "Sage",
            Self::Citrine => "Citrine",
            Self::Amber => "Amber",
            Self::Coral => "Coral",
            Self::Rose => "Rose",
            Self::Plum => "Plum",
            Self::Graphite => "Graphite",
        }
    }

    /// The accent following `self` in palette order, wrapping around. Used to
    /// give each newly created space a different color.
    #[must_use]
    pub fn next(self) -> Self {
        let index = Self::ALL.iter().position(|c| *c == self).unwrap_or(0);
        Self::ALL[(index + 1) % Self::ALL.len()]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn next_cycles_through_every_accent() {
        let mut color = AccentColor::Iris;
        for _ in 0..AccentColor::ALL.len() {
            color = color.next();
        }
        assert_eq!(color, AccentColor::Iris);
    }
}
