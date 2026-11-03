import UIKit

/// Curio's design tokens. The chrome takes its color from the active space,
/// like Arc: a soft tinted gradient with the page floating on top as a card.
/// Values match the desktop app exactly.
nonisolated struct CurioTheme: Equatable, Sendable {
    let appearance: Appearance
    let accentColor: AccentColor
    /// The pure accent, for focus rings and primary buttons.
    let accent: HSLA
    /// A soft accent wash for selected rows and chips.
    let accentSoft: HSLA
    /// Accent-tinted text that stays legible on the chrome.
    let accentText: HSLA
    let chromeTop: HSLA
    let chromeBottom: HSLA
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

    init(accent accentColor: AccentColor, appearance: Appearance) {
        self.appearance = appearance
        self.accentColor = accentColor
        let base = HSLA(hex: accentColor.rgb)
        let h = base.h
        // Graphite is intentionally almost neutral.
        let tint = accentColor == .graphite ? 0.06 : 1.0
        switch appearance {
        case .light:
            accent = base
            accentSoft = base.withAlpha(0.14)
            accentText = HSLA(h, min(base.s * 0.9, 0.85), 0.36)
            chromeTop = HSLA(h, 0.55 * tint, 0.905)
            chromeBottom = HSLA((h + 0.03).truncatingRemainder(dividingBy: 1), 0.48 * tint, 0.855)
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
            chromeTop = HSLA(h, 0.24 * tint, 0.155)
            chromeBottom = HSLA((h + 0.03).truncatingRemainder(dividingBy: 1), 0.20 * tint, 0.115)
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
}
