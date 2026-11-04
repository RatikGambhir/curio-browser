import UIKit

/// Curio's design tokens. The chrome takes its color from the active space,
/// like Arc: each space has a soft gradient theme behind the chrome, with the
/// page floating on top as a card. The theme's tone decides whether the
/// chrome is light or dark, whatever the system appearance (web pages still
/// follow the Theme setting). Values match the desktop app exactly.
nonisolated struct CurioTheme: Equatable, Sendable {
    let appearance: Appearance
    let gradient: SpaceGradient
    /// The pure accent, for focus rings and primary buttons.
    let accent: HSLA
    /// A soft accent wash for selected rows and chips.
    let accentSoft: HSLA
    /// Accent-tinted text that stays legible on the chrome.
    let accentText: HSLA
    /// The gradient's color near the top and bottom of the sidebar, for
    /// anything that needs a flat approximation of it.
    let chromeTop: HSLA
    let chromeBottom: HSLA
    /// iOS only: a wash behind the phone's bottom bar. The bar sits on the
    /// brightest part of a dark theme, so it is deepened with the theme's own
    /// top color to keep the address and icons readable. Clear on light
    /// themes.
    let bottomBarShade: HSLA
    let text: HSLA
    let textMuted: HSLA
    let textFaint: HSLA
    let rowHover: HSLA
    let rowActive: HSLA
    let rowActiveText: HSLA
    let rowActiveBorder: HSLA
    let divider: HSLA
    let field: HSLA
    let fieldHover: HSLA
    let card: HSLA
    let cardBorder: HSLA
    let surface: HSLA
    let surfaceRaised: HSLA
    let surfaceBorder: HSLA
    let scrim: HSLA
    let userBubble: HSLA
    let userBubbleText: HSLA
    let success: HSLA
    let danger: HSLA
    let warning: HSLA

    /// Computes tokens for a space theme. Its tone sets the appearance.
    init(gradient: SpaceGradient) {
        self.gradient = gradient
        let base = HSLA(hex: gradient.accentRGB)
        let h = base.h
        // Slate is intentionally almost neutral.
        let tint = gradient == .slate ? 0.3 : 1.0
        let spec = gradient.spec
        func sample(_ y: Float) -> HSLA {
            let c = spec.sample(x: 0.08, y: y, aspect: 1.6)
            return HSLA(r: Double(c.x), g: Double(c.y), b: Double(c.z))
        }
        chromeTop = sample(0.04)
        chromeBottom = sample(0.96)
        appearance = gradient.tone == .light ? .light : .dark
        bottomBarShade = appearance == .dark ? chromeTop.withAlpha(0.45) : HSLA(0, 0, 0, 0)
        switch appearance {
        case .light:
            accent = base
            accentSoft = base.withAlpha(0.14)
            accentText = HSLA(h, min(base.s * 0.9, 0.85), 0.36)
            text = HSLA(h, 0.12 * tint, 0.13)
            textMuted = HSLA(h, 0.10 * tint, 0.13, 0.80)
            textFaint = HSLA(h, 0.10 * tint, 0.13, 0.55)
            rowHover = HSLA(0, 0, 1, 0.38)
            rowActive = HSLA(0, 0, 1, 0.86)
            rowActiveText = HSLA(h, 0.15 * tint, 0.10)
            rowActiveBorder = HSLA(h, 0.30 * tint, 0.30, 0.10)
            divider = HSLA(h, 0.20 * tint, 0.20, 0.10)
            field = HSLA(0, 0, 1, 0.50)
            fieldHover = HSLA(0, 0, 1, 0.72)
            card = HSLA(0, 0, 1)
            cardBorder = HSLA(h, 0.25 * tint, 0.25, 0.10)
            surface = HSLA(h, 0.18 * tint, 0.985)
            surfaceRaised = HSLA(0, 0, 1)
            surfaceBorder = HSLA(h, 0.25 * tint, 0.25, 0.12)
            scrim = HSLA(h, 0.30 * tint, 0.12, 0.18)
            userBubble = HSLA(h, 0.55 * tint, 0.93)
            userBubbleText = HSLA(h, 0.25 * tint, 0.14)
            success = HSLA(hex: 0x2E9E5B)
            danger = HSLA(hex: 0xD8434E)
            warning = HSLA(hex: 0xD98A12)
        case .dark:
            accent = HSLA(h, min(base.s, 0.85), max(base.l, 0.62))
            accentSoft = HSLA(h, base.s, 0.62, 0.20)
            accentText = HSLA(h, min(base.s * 0.9, 0.85), 0.78)
            text = HSLA(h, 0.10 * tint, 0.93)
            textMuted = HSLA(h, 0.08 * tint, 0.93, 0.78)
            textFaint = HSLA(h, 0.08 * tint, 0.93, 0.52)
            rowHover = HSLA(0, 0, 1, 0.06)
            rowActive = HSLA(0, 0, 1, 0.13)
            rowActiveText = HSLA(0, 0, 1)
            rowActiveBorder = HSLA(0, 0, 1, 0.06)
            divider = HSLA(0, 0, 1, 0.08)
            field = HSLA(0, 0, 1, 0.07)
            fieldHover = HSLA(0, 0, 1, 0.11)
            card = HSLA(h, 0.08 * tint, 0.105)
            cardBorder = HSLA(0, 0, 1, 0.08)
            surface = HSLA(h, 0.14 * tint, 0.135)
            surfaceRaised = HSLA(h, 0.14 * tint, 0.165)
            surfaceBorder = HSLA(0, 0, 1, 0.10)
            scrim = HSLA(0, 0, 0, 0.40)
            userBubble = HSLA(h, 0.30 * tint, 0.24)
            userBubbleText = HSLA(h, 0.10 * tint, 0.95)
            success = HSLA(hex: 0x4CC27E)
            danger = HSLA(hex: 0xF0646E)
            warning = HSLA(hex: 0xF2A93B)
        }
    }

    /// The base color of an accent, for swatches.
    static func swatch(_ color: AccentColor) -> UIColor { HSLA(hex: color.rgb).uiColor }

    /// A theme's accent, for the small dots that stand for a space.
    static func swatch(_ gradient: SpaceGradient) -> UIColor { HSLA(hex: gradient.accentRGB).uiColor }
}
