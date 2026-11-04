import Foundation

/// Space themes: soft, atmospheric gradients behind the window chrome.
///
/// Each theme is a diagonal linear gradient with 4 stops, plus 2–3 large,
/// faint radial glows that add depth without reading as shapes. Colors blend
/// in OKLab, which keeps transitions even and avoids the muddy middle a plain
/// RGB blend gives. `GradientSpec.renderRGBA` paints a theme into a bitmap
/// with light dithering so wide, low-contrast ramps don't band.
///
/// Coordinates cover the whole window: `x` runs 0 → 1 left to right and `y`
/// 0 → 1 top to bottom. The sidebar only shows the left fifth, so each theme
/// changes mostly from top to bottom, with glows near the left edge.
///
/// A theme's `Tone` decides whether the chrome on top of it is light or dark,
/// whatever the system appearance is. Ported from `curio-core/src/gradient.rs`;
/// the colors there are the source of truth.
nonisolated enum SpaceGradient: String, Codable, CaseIterable, Sendable {
    // Light
    case lavenderBlush = "lavender_blush"
    case skyHaze = "sky_haze"
    case mintCream = "mint_cream"
    case peachGlow = "peach_glow"
    case roseFog = "rose_fog"
    case aurora
    case iris
    case periwinkle
    case sand
    case citrus
    // Dark
    case midnightIndigo = "midnight_indigo"
    case forest
    case oceanDepths = "ocean_depths"
    case plumNight = "plum_night"
    case burgundy
    case slate
    case tealDrift = "teal_drift"
    case blueFlame = "blue_flame"
    case sunsetDusk = "sunset_dusk"
    case ember

    /// Whether a theme is light (dark text) or dark (light text).
    enum Tone: Sendable {
        case light
        case dark
    }

    static let `default` = SpaceGradient.lavenderBlush

    /// The light themes, in picker order.
    static let light: [SpaceGradient] = [
        .lavenderBlush, .skyHaze, .mintCream, .peachGlow, .roseFog, .aurora, .iris, .periwinkle, .sand, .citrus,
    ]

    /// The dark themes, in picker order.
    static let dark: [SpaceGradient] = [
        .midnightIndigo, .forest, .oceanDepths, .plumNight, .burgundy, .slate, .tealDrift, .blueFlame, .sunsetDusk, .ember,
    ]

    /// A display name for the picker.
    var label: String {
        switch self {
        case .lavenderBlush: "Lavender Blush"
        case .skyHaze: "Sky Haze"
        case .mintCream: "Mint Cream"
        case .peachGlow: "Peach Glow"
        case .roseFog: "Rose Fog"
        case .aurora: "Aurora"
        case .iris: "Iris"
        case .periwinkle: "Periwinkle"
        case .sand: "Sand"
        case .citrus: "Citrus"
        case .midnightIndigo: "Midnight Indigo"
        case .forest: "Forest"
        case .oceanDepths: "Ocean Depths"
        case .plumNight: "Plum Night"
        case .burgundy: "Burgundy"
        case .slate: "Slate"
        case .tealDrift: "Teal Drift"
        case .blueFlame: "Blue Flame"
        case .sunsetDusk: "Sunset Dusk"
        case .ember: "Ember"
        }
    }

    /// Whether the chrome on this theme is light or dark.
    var tone: Tone { Self.light.contains(self) ? .light : .dark }

    /// The accent for selection, focus rings and buttons, as `0xRRGGBB`.
    /// Picked to sit with the gradient while staying legible on it.
    var accentRGB: UInt32 {
        switch self {
        case .lavenderBlush: 0x7C62E8
        case .skyHaze: 0x2F86E0
        case .mintCream: 0x2E9A6A
        case .peachGlow: 0xE0694B
        case .roseFog: 0xC9568F
        case .aurora: 0x3C82E6
        case .iris: 0x6E5BF5
        case .periwinkle: 0x5B6CF0
        case .sand: 0xB7803A
        case .citrus: 0x6E9E2A
        case .midnightIndigo: 0x8C7CF5
        case .forest: 0x3FBF8F
        case .oceanDepths: 0x3AB0C8
        case .plumNight: 0xB07CE0
        case .burgundy: 0xE0628F
        case .slate: 0x7F9CC8
        case .tealDrift: 0x3CC4A6
        case .blueFlame: 0x5C82F0
        case .sunsetDusk: 0xF08A6E
        case .ember: 0xF0904A
        }
    }

    /// The next theme with the same tone, wrapping around. New spaces take
    /// the theme after the last space's, so each starts out different.
    var next: SpaceGradient {
        let group = tone == .light ? Self.light : Self.dark
        let index = group.firstIndex(of: self) ?? 0
        return group[(index + 1) % group.count]
    }

    /// The theme for a space saved before themes existed, from its accent.
    /// Every result is light, so nobody's chrome suddenly goes dark.
    static func from(accent: AccentColor) -> SpaceGradient {
        switch accent {
        case .iris: .iris
        case .ocean: .skyHaze
        case .lagoon, .graphite: .aurora
        case .sage: .mintCream
        case .citrine: .citrus
        case .amber: .sand
        case .coral: .peachGlow
        case .rose: .roseFog
        case .plum: .lavenderBlush
        }
    }

    /// The closest accent, still written to storage for older builds.
    var legacyAccent: AccentColor {
        switch self {
        case .lavenderBlush, .plumNight: .plum
        case .skyHaze, .periwinkle, .blueFlame: .ocean
        case .mintCream, .forest: .sage
        case .peachGlow, .sunsetDusk: .coral
        case .roseFog, .burgundy: .rose
        case .aurora, .oceanDepths, .tealDrift: .lagoon
        case .iris, .midnightIndigo: .iris
        case .sand, .ember: .amber
        case .citrus: .citrine
        case .slate: .graphite
        }
    }

    /// The colors to paint.
    var spec: GradientSpec {
        typealias S = GradientSpec.Stop
        typealias G = GradientSpec.Glow
        let stops: [S]
        let glows: [G]
        switch self {
        // Lavender, lilac, pale pink.
        case .lavenderBlush:
            stops = [S(0xD8D6FB, 0.0), S(0xE3DAFA, 0.38), S(0xF1DEF2, 0.72), S(0xFCE6E8, 1.0)]
            glows = [
                G(0xCDC6FF, x: 0.04, y: 0.06, radius: 0.55, strength: 0.40),
                G(0xFFD9E2, x: 0.12, y: 0.98, radius: 0.60, strength: 0.40),
                G(0xE8E2FF, x: 0.92, y: 0.00, radius: 0.50, strength: 0.25),
            ]
        // Powder blue, icy cyan, mint.
        case .skyHaze:
            stops = [S(0xD2E6FF, 0.0), S(0xDAEEFD, 0.38), S(0xE1F6F8, 0.72), S(0xE8FDF4, 1.0)]
            glows = [
                G(0xC4DDFF, x: 0.04, y: 0.08, radius: 0.55, strength: 0.40),
                G(0xD9FAEC, x: 0.15, y: 0.98, radius: 0.60, strength: 0.40),
                G(0xD4F2FF, x: 0.88, y: 0.02, radius: 0.50, strength: 0.25),
            ]
        // Pale mint, sage, warm ivory.
        case .mintCream:
            stops = [S(0xDDF8E8, 0.0), S(0xE2F1E0, 0.38), S(0xF1F6E0, 0.72), S(0xFFF9DE, 1.0)]
            glows = [
                G(0xCFEFDC, x: 0.04, y: 0.08, radius: 0.55, strength: 0.40),
                G(0xFFF2CF, x: 0.15, y: 0.98, radius: 0.60, strength: 0.35),
                G(0xDCEDD6, x: 0.85, y: 0.05, radius: 0.50, strength: 0.25),
            ]
        // Soft coral, peach, cream.
        case .peachGlow:
            stops = [S(0xFFDACE, 0.0), S(0xFFE2D3, 0.36), S(0xFFEAD9, 0.70), S(0xFFF3E2, 1.0)]
            glows = [
                G(0xFFCABB, x: 0.04, y: 0.04, radius: 0.55, strength: 0.40),
                G(0xFFEFD6, x: 0.18, y: 0.98, radius: 0.60, strength: 0.35),
                G(0xFFD6CC, x: 0.90, y: 0.00, radius: 0.45, strength: 0.25),
            ]
        // Dusty rose, lilac, pale lavender.
        case .roseFog:
            stops = [S(0xF4D4E5, 0.0), S(0xEED8ED, 0.38), S(0xE7DCF5, 0.72), S(0xE2DFFC, 1.0)]
            glows = [
                G(0xEFC8DC, x: 0.04, y: 0.06, radius: 0.55, strength: 0.40),
                G(0xDAD6FF, x: 0.15, y: 0.98, radius: 0.60, strength: 0.40),
                G(0xF6DCEB, x: 0.90, y: 0.02, radius: 0.45, strength: 0.20),
            ]
        // Icy cyan into soft periwinkle.
        case .aurora:
            stops = [S(0xD6EEFF, 0.0), S(0xD9ECFB, 0.36), S(0xD9E6FD, 0.70), S(0xDCDFFF, 1.0)]
            glows = [
                G(0xCDF3F5, x: 0.04, y: 0.08, radius: 0.55, strength: 0.40),
                G(0xE1D8FF, x: 0.18, y: 0.98, radius: 0.60, strength: 0.35),
                G(0xD3F0FF, x: 0.90, y: 0.00, radius: 0.45, strength: 0.20),
            ]
        // Violet into orchid.
        case .iris:
            stops = [S(0xCDC7FF, 0.0), S(0xD6CDFE, 0.36), S(0xE1D4FD, 0.70), S(0xECDCFF, 1.0)]
            glows = [
                G(0xC3BDFF, x: 0.04, y: 0.06, radius: 0.55, strength: 0.40),
                G(0xF1DCFA, x: 0.15, y: 0.98, radius: 0.60, strength: 0.35),
                G(0xD9D3FF, x: 0.90, y: 0.00, radius: 0.45, strength: 0.20),
            ]
        // Powder blue, periwinkle, violet.
        case .periwinkle:
            stops = [S(0xC2D9FF, 0.0), S(0xC6D2FE, 0.38), S(0xC9CAFD, 0.70), S(0xCEC4FD, 1.0)]
            glows = [
                G(0xB9DBFF, x: 0.04, y: 0.06, radius: 0.55, strength: 0.40),
                G(0xD4C4FF, x: 0.15, y: 0.98, radius: 0.60, strength: 0.35),
                G(0xC8DEFF, x: 0.90, y: 0.00, radius: 0.45, strength: 0.20),
            ]
        // Warm sand into cream.
        case .sand:
            stops = [S(0xF4E3CB, 0.0), S(0xF7E9D5, 0.38), S(0xFAEFDF, 0.70), S(0xFEF5E8, 1.0)]
            glows = [
                G(0xEFDABF, x: 0.04, y: 0.06, radius: 0.55, strength: 0.40),
                G(0xFFEEDA, x: 0.18, y: 0.98, radius: 0.60, strength: 0.30),
                G(0xF6E6D2, x: 0.90, y: 0.00, radius: 0.45, strength: 0.20),
            ]
        // Pale lemon into soft lime.
        case .citrus:
            stops = [S(0xFFF5C2, 0.0), S(0xF8F8C8, 0.38), S(0xEEFACE, 0.70), S(0xE3FCD6, 1.0)]
            glows = [
                G(0xFFEFB6, x: 0.04, y: 0.04, radius: 0.55, strength: 0.40),
                G(0xDBF8D2, x: 0.18, y: 0.98, radius: 0.60, strength: 0.35),
                G(0xFBF6CC, x: 0.90, y: 0.00, radius: 0.45, strength: 0.20),
            ]
        // Charcoal navy, indigo, muted violet.
        case .midnightIndigo:
            stops = [S(0x14182A, 0.0), S(0x1B2040, 0.36), S(0x282A54, 0.70), S(0x353164, 1.0)]
            glows = [
                G(0x4B3F8C, x: 0.10, y: 0.98, radius: 0.60, strength: 0.35),
                G(0x232E6A, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30),
                G(0x3A3478, x: 0.02, y: 0.55, radius: 0.40, strength: 0.15),
            ]
        // Deep evergreen, dark teal, emerald.
        case .forest:
            stops = [S(0x0D2620, 0.0), S(0x113428, 0.36), S(0x164537, 0.70), S(0x1C5F50, 1.0)]
            glows = [
                G(0x2A8466, x: 0.12, y: 0.98, radius: 0.60, strength: 0.30),
                G(0x0F3A3A, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30),
                G(0x1D5A48, x: 0.02, y: 0.50, radius: 0.40, strength: 0.15),
            ]
        // Midnight blue, petrol blue, muted cyan.
        case .oceanDepths:
            stops = [S(0x0C2036, 0.0), S(0x0F2E48, 0.36), S(0x14435B, 0.70), S(0x1A5768, 1.0)]
            glows = [
                G(0x27788A, x: 0.12, y: 0.98, radius: 0.60, strength: 0.30),
                G(0x113866, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30),
                G(0x165065, x: 0.02, y: 0.50, radius: 0.40, strength: 0.15),
            ]
        // Near-black purple, plum, dusty violet.
        case .plumNight:
            stops = [S(0x1C1127, 0.0), S(0x281938, 0.36), S(0x37234D, 0.70), S(0x452960, 1.0)]
            glows = [
                G(0x664084, x: 0.12, y: 0.98, radius: 0.60, strength: 0.30),
                G(0x321F4A, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30),
                G(0x4A2E66, x: 0.02, y: 0.50, radius: 0.40, strength: 0.15),
            ]
        // Deep wine, burgundy, muted raspberry.
        case .burgundy:
            stops = [S(0x240F1A, 0.0), S(0x341424, 0.36), S(0x46192F, 0.70), S(0x561D38, 1.0)]
            glows = [
                G(0x7A2D50, x: 0.12, y: 0.98, radius: 0.55, strength: 0.30),
                G(0x3A142E, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30),
                G(0x5A2040, x: 0.02, y: 0.50, radius: 0.40, strength: 0.15),
            ]
        // Blue-gray charcoal.
        case .slate:
            stops = [S(0x0E141D, 0.0), S(0x151F2B, 0.36), S(0x202B3B, 0.70), S(0x2C384C, 1.0)]
            glows = [
                G(0x3D4D66, x: 0.12, y: 0.98, radius: 0.60, strength: 0.30),
                G(0x1A2636, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30),
                G(0x2A3A50, x: 0.02, y: 0.50, radius: 0.40, strength: 0.12),
            ]
        // Dark teal, turquoise, desaturated jade.
        case .tealDrift:
            stops = [S(0x0D2E36, 0.0), S(0x103D3E, 0.36), S(0x13483F, 0.70), S(0x164E43, 1.0)]
            glows = [
                G(0x1F6656, x: 0.12, y: 0.98, radius: 0.55, strength: 0.25),
                G(0x11444E, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30),
                G(0x1A5B58, x: 0.02, y: 0.50, radius: 0.40, strength: 0.15),
            ]
        // Deep navy into cobalt.
        case .blueFlame:
            stops = [S(0x161B43, 0.0), S(0x1C2557, 0.36), S(0x24357A, 0.70), S(0x2C4596, 1.0)]
            glows = [
                G(0x3A5EC0, x: 0.12, y: 0.98, radius: 0.55, strength: 0.30),
                G(0x221D58, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30),
                G(0x2A3C88, x: 0.02, y: 0.50, radius: 0.40, strength: 0.15),
            ]
        // Dark plum, dusty rose, warm coral.
        case .sunsetDusk:
            stops = [S(0x23132B, 0.0), S(0x381B37, 0.36), S(0x552741, 0.70), S(0x763647, 1.0)]
            glows = [
                G(0xA4504C, x: 0.12, y: 1.0, radius: 0.55, strength: 0.35),
                G(0x381C42, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30),
                G(0x5E2C48, x: 0.02, y: 0.50, radius: 0.40, strength: 0.15),
            ]
        // Dark espresso, burnt orange, copper.
        case .ember:
            stops = [S(0x21120A, 0.0), S(0x31180D, 0.36), S(0x522610, 0.70), S(0x763512, 1.0)]
            glows = [
                G(0xA24E1A, x: 0.12, y: 1.0, radius: 0.55, strength: 0.30),
                G(0x2E1A10, x: 0.90, y: 0.02, radius: 0.50, strength: 0.30),
                G(0x5A2C14, x: 0.02, y: 0.50, radius: 0.40, strength: 0.15),
            ]
        }
        return GradientSpec(angle: GradientSpec.defaultAngle, stops: stops, glows: glows)
    }
}

/// Everything needed to paint a theme. The math uses `Float`, like the
/// desktop app, so both produce the same pixels.
nonisolated struct GradientSpec: Equatable, Sendable {
    /// One color stop on the base gradient.
    struct Stop: Equatable, Sendable {
        /// `0xRRGGBB`.
        var rgb: UInt32
        /// Position along the gradient, 0 to 1.
        var at: Float

        init(_ rgb: UInt32, _ at: Float) {
            self.rgb = rgb
            self.at = at
        }
    }

    /// A large, soft radial glow blended over the base gradient.
    struct Glow: Equatable, Sendable {
        /// `0xRRGGBB`.
        var rgb: UInt32
        /// Center, in window coordinates (0 to 1).
        var x: Float
        var y: Float
        /// Size, as a fraction of the window height. The glow fades smoothly
        /// (Gaussian), so there is no visible edge.
        var radius: Float
        /// How much of the glow color shows at the center, 0 to 1.
        var strength: Float

        init(_ rgb: UInt32, x: Float, y: Float, radius: Float, strength: Float) {
            self.rgb = rgb
            self.x = x
            self.y = y
            self.radius = radius
            self.strength = strength
        }
    }

    /// Mostly top to bottom, tilted slightly toward the bottom right.
    static let defaultAngle: Float = 162

    /// Direction of the base gradient in CSS degrees (180 = top to bottom).
    var angle: Float
    var stops: [Stop]
    var glows: [Glow]

    /// The sRGB color (0 to 1) at window coordinates `x`, `y` for a window
    /// `aspect` (width / height) wide.
    func sample(x: Float, y: Float, aspect: Float) -> SIMD3<Float> {
        Prepared(self).sample(x: x, y: y, aspect: aspect)
    }

    /// Paints the theme into a `width` × `height` RGBA bitmap (alpha always
    /// 255), dithered so it stays smooth when scaled up.
    func renderRGBA(width: Int, height: Int) -> [UInt8] {
        let prepared = Prepared(self)
        let aspect = Float(width) / Float(max(height, 1))
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        pixels.withUnsafeMutableBufferPointer { buffer in
            var i = 0
            for py in 0 ..< height {
                let y = (Float(py) + 0.5) / Float(height)
                for px in 0 ..< width {
                    let x = (Float(px) + 0.5) / Float(width)
                    let color = prepared.sample(x: x, y: y, aspect: aspect)
                    let noise = Self.dither(UInt32(px), UInt32(py))
                    for c in 0 ..< 3 {
                        let value = (color[c] * 255 + noise).rounded().clamped(0, 255)
                        buffer[i + c] = UInt8(value)
                    }
                    i += 4
                }
            }
        }
        return pixels
    }

    /// Triangular noise of ±1 level, the same for a pixel every time.
    static func dither(_ x: UInt32, _ y: UInt32) -> Float {
        func hash(_ n: UInt32) -> Float {
            var n = n
            n ^= n >> 16
            n = n &* 0x7FEB_352D
            n ^= n >> 15
            n = n &* 0x846C_A68B
            n ^= n >> 16
            return Float(n & 0xFFFF) / 65_535
        }
        let seed = (x &* 1_973) &+ (y &* 9_277)
        return hash(seed) - hash(seed ^ 0x9E37_79B9)
    }

    /// A spec with its colors converted once, ready to sample many times.
    private struct Prepared {
        /// Unit direction of the base gradient, in window pixels.
        let dx: Float
        let dy: Float
        let stops: [(at: Float, lab: OKLab)]
        let glows: [(glow: Glow, lab: OKLab)]

        init(_ spec: GradientSpec) {
            let radians = spec.angle * .pi / 180
            // CSS angles: 0° points up, 90° right, 180° down (y grows down).
            dx = sin(radians)
            dy = -cos(radians)
            stops = spec.stops.map { ($0.at, OKLab(rgb: $0.rgb)) }
            glows = spec.glows.map { ($0, OKLab(rgb: $0.rgb)) }
        }

        func sample(x: Float, y: Float, aspect: Float) -> SIMD3<Float> {
            // Project onto the gradient line, CSS style: the line is just long
            // enough for both ends to touch opposite corners.
            let length = abs(aspect * dx) + abs(dy)
            let t = (((x - 0.5) * aspect * dx + (y - 0.5) * dy) / length + 0.5).clamped(0, 1)
            var color = base(t)
            for (glow, lab) in glows {
                let gx = (x - glow.x) * aspect
                let gy = y - glow.y
                let d2 = (gx * gx + gy * gy) / (glow.radius * glow.radius)
                let amount = glow.strength * exp(-2 * d2)
                color = color.lerp(lab, amount)
            }
            return color.srgb
        }

        private func base(_ t: Float) -> OKLab {
            guard let first = stops.first else { return OKLab(l: 0, a: 0, b: 0) }
            if t <= first.at { return first.lab }
            for index in 1 ..< stops.count {
                let (a, b) = (stops[index - 1], stops[index])
                if t <= b.at {
                    let span = max(b.at - a.at, .ulpOfOne)
                    return a.lab.lerp(b.lab, (t - a.at) / span)
                }
            }
            return stops[stops.count - 1].lab
        }
    }
}

/// A color in OKLab, where straight-line blends look even to the eye.
nonisolated struct OKLab: Equatable, Sendable {
    var l: Float
    var a: Float
    var b: Float

    init(l: Float, a: Float, b: Float) {
        self.l = l
        self.a = a
        self.b = b
    }

    /// Converts `0xRRGGBB` (sRGB).
    init(rgb: UInt32) {
        let c = OKLab.components(rgb)
        let (r, g, b) = (OKLab.toLinear(c.x), OKLab.toLinear(c.y), OKLab.toLinear(c.z))
        let l = cbrt(0.412_221_46 * r + 0.536_332_55 * g + 0.051_445_995 * b)
        let m = cbrt(0.211_903_5 * r + 0.680_699_5 * g + 0.107_396_96 * b)
        let s = cbrt(0.088_302_46 * r + 0.281_718_85 * g + 0.629_978_7 * b)
        self.l = 0.210_454_26 * l + 0.793_617_8 * m - 0.004_072_047 * s
        a = 1.977_998_5 * l - 2.428_592_2 * m + 0.450_593_7 * s
        self.b = 0.025_904_037 * l + 0.782_771_77 * m - 0.808_675_77 * s
    }

    func lerp(_ other: OKLab, _ t: Float) -> OKLab {
        OKLab(l: l + (other.l - l) * t, a: a + (other.a - a) * t, b: b + (other.b - b) * t)
    }

    /// Back to sRGB components, 0 to 1 (clamped).
    var srgb: SIMD3<Float> {
        let lc = l + 0.396_337_78 * a + 0.215_803_76 * b
        let mc = l - 0.105_561_346 * a - 0.063_854_17 * b
        let sc = l - 0.089_484_18 * a - 1.291_485_5 * b
        let (l3, m3, s3) = (lc * lc * lc, mc * mc * mc, sc * sc * sc)
        return SIMD3(
            OKLab.toSRGB(4.076_741_7 * l3 - 3.307_711_6 * m3 + 0.230_969_94 * s3),
            OKLab.toSRGB(-1.268_438 * l3 + 2.609_757_4 * m3 - 0.341_319_38 * s3),
            OKLab.toSRGB(-0.004_196_086_3 * l3 - 0.703_418_6 * m3 + 1.707_614_7 * s3)
        )
    }

    /// `0xRRGGBB` as sRGB components, 0 to 1.
    static func components(_ rgb: UInt32) -> SIMD3<Float> {
        SIMD3(Float((rgb >> 16) & 0xFF) / 255, Float((rgb >> 8) & 0xFF) / 255, Float(rgb & 0xFF) / 255)
    }

    static func toLinear(_ c: Float) -> Float {
        c <= 0.040_45 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func toSRGB(_ c: Float) -> Float {
        let c = c.clamped(0, 1)
        return c <= 0.003_130_8 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }
}

private extension Float {
    nonisolated func clamped(_ low: Float, _ high: Float) -> Float { Swift.min(Swift.max(self, low), high) }
}
