import UIKit
import XCTest
@testable import Curio

/// Ports of the desktop tests in `curio-core/src/gradient.rs`,
/// `curio-ui/src/theme.rs` and `curio-storage/src/database.rs`, plus checks
/// for the iPhone and iPad layouts.
final class SpaceGradientTests: XCTestCase {
    // MARK: - Themes

    func testTwentyThemesSplitEvenlyByTone() {
        XCTAssertEqual(SpaceGradient.allCases.count, 20)
        XCTAssertEqual(SpaceGradient.light + SpaceGradient.dark, SpaceGradient.allCases)
        XCTAssertTrue(SpaceGradient.light.allSatisfy { $0.tone == .light })
        XCTAssertTrue(SpaceGradient.dark.allSatisfy { $0.tone == .dark })
    }

    func testNamesAndPickerOrder() {
        XCTAssertEqual(SpaceGradient.light.map(\.label), [
            "Lavender Blush", "Sky Haze", "Mint Cream", "Peach Glow", "Rose Fog", "Aurora", "Iris", "Periwinkle", "Sand", "Citrus",
        ])
        XCTAssertEqual(SpaceGradient.dark.map(\.label), [
            "Midnight Indigo", "Forest", "Ocean Depths", "Plum Night", "Burgundy", "Slate", "Teal Drift", "Blue Flame", "Sunset Dusk", "Ember",
        ])
    }

    func testSpecsHaveThreeToFiveOrderedStops() {
        for gradient in SpaceGradient.allCases {
            let spec = gradient.spec
            XCTAssertEqual(spec.angle, 162)
            XCTAssertTrue((3 ... 5).contains(spec.stops.count), "\(gradient)")
            XCTAssertTrue(zip(spec.stops, spec.stops.dropFirst()).allSatisfy { $0.at < $1.at }, "\(gradient)")
            XCTAssertTrue((1 ... 3).contains(spec.glows.count), "\(gradient)")
            // Glows stay subtle: no hard spots.
            XCTAssertTrue(spec.glows.allSatisfy { $0.strength <= 0.4 && $0.radius >= 0.4 }, "\(gradient)")
        }
    }

    func testLightThemesStayLightAndDarkThemesStayDark() {
        for gradient in SpaceGradient.allCases {
            let spec = gradient.spec
            for i in 0 ... 10 {
                for j in 0 ... 10 {
                    let c = spec.sample(x: Float(i) / 10, y: Float(j) / 10, aspect: 1.6)
                    let l = Self.luminance(Double(c.x), Double(c.y), Double(c.z))
                    switch gradient.tone {
                    case .light: XCTAssertGreaterThan(l, 0.5, "\(gradient) too dark")
                    case .dark: XCTAssertLessThan(l, 0.12, "\(gradient) too bright")
                    }
                }
            }
        }
    }

    func testOKLabRoundTrips() {
        for rgb: UInt32 in [0x000000, 0xFFFFFF, 0x7C62E8, 0x1C5F50, 0xFCE6E8] {
            let back = OKLab(rgb: rgb).srgb
            let expected = OKLab.components(rgb)
            for c in 0 ..< 3 {
                XCTAssertEqual(back[c], expected[c], accuracy: 0.002, String(format: "%06x", rgb))
            }
        }
    }

    func testRenderingIsSmoothWithNoHardEdges() {
        for gradient in SpaceGradient.allCases {
            let (w, h) = (48, 300)
            let pixels = gradient.spec.renderRGBA(width: w, height: h)
            XCTAssertEqual(pixels.count, w * h * 4)
            var worst = 0
            for y in 1 ..< h {
                for x in 0 ..< w {
                    let i = (y * w + x) * 4
                    let above = i - w * 4
                    for c in 0 ..< 3 {
                        worst = max(worst, abs(Int(pixels[i + c]) - Int(pixels[above + c])))
                    }
                    XCTAssertEqual(pixels[i + 3], 255)
                }
            }
            // Dithering adds ±1; the gradient itself moves slowly.
            XCTAssertLessThanOrEqual(worst, 4, "\(gradient)")
        }
    }

    /// The same pixels as the desktop's `render_rgba(48, 30)`: the corners
    /// and center, within one level, and the whole bitmap's FNV-1a hash.
    func testRenderingMatchesTheDesktop() {
        let reference: [(SpaceGradient, UInt64, [UInt32])] = [
            (.lavenderBlush, 0x8211_8944_8A13_1E8C, [0xD3CFFC, 0xE9DCF7, 0xFBE5E8]),
            (.skyHaze, 0xCCE0_B224_F4D0_93E8, [0xCCE2FE, 0xDDF2FB, 0xE7FDF4]),
            (.mintCream, 0x2DB1_C71A_4E85_49E0, [0xD7F3E2, 0xE9F3E0, 0xFEF9DE]),
            (.peachGlow, 0xE45E_BCD9_1874_6BB0, [0xFED3C6, 0xFFE6D6, 0xFFF2E1]),
            (.roseFog, 0xA6DF_397D_0B84_0C4F, [0xF1CFE1, 0xEBDAF1, 0xE2DFFC]),
            (.aurora, 0xBBE6_BC98_E5BD_7691, [0xD2EFFA, 0xDAE9FC, 0xDCDFFF]),
            (.iris, 0x7C06_A637_A742_434B, [0xC8C2FE, 0xDCD1FE, 0xEBDBFF]),
            (.periwinkle, 0x5D16_CC44_DBFC_A17E, [0xBED9FE, 0xC8CFFE, 0xCEC4FD]),
            (.sand, 0x8F09_D7C2_575C_467C, [0xF1DFC6, 0xF9ECDA, 0xFEF5E7]),
            (.citrus, 0x5C32_43A1_B097_2E20, [0xFEF2BD, 0xF4F9CB, 0xE3FCD5]),
            (.midnightIndigo, 0x6053_D00E_D64A_9EB4, [0x14182A, 0x22254A, 0x343163]),
            (.forest, 0x70AD_B8B6_ACE5_6CB2, [0x0C2620, 0x143D30, 0x1C5E4F]),
            (.oceanDepths, 0x01B9_B45B_5707_6DED, [0x0B2036, 0x123852, 0x1A5667]),
            (.plumNight, 0x14D2_7B3A_172B_99E0, [0x1C1127, 0x301E42, 0x44295F]),
            (.burgundy, 0x16F6_58AD_5EFB_16AD, [0x240E1A, 0x3D172A, 0x551D37]),
            (.slate, 0xE85A_445B_D88C_57C7, [0x0E141D, 0x1B2533, 0x2B374B]),
            (.tealDrift, 0x6AAC_B764_284A_249F, [0x0C2E36, 0x12433F, 0x164E43]),
            (.blueFlame, 0xDF47_47D2_26E4_C134, [0x161B43, 0x202D67, 0x2B4494]),
            (.sunsetDusk, 0x8F56_8DB1_23B1_F571, [0x23132B, 0x46213C, 0x743547]),
            (.ember, 0xA854_A493_2C6E_4061, [0x211209, 0x401F0F, 0x743412]),
        ]
        XCTAssertEqual(reference.map(\.0), SpaceGradient.allCases)
        for (gradient, hash, colors) in reference {
            let pixels = gradient.spec.renderRGBA(width: 48, height: 30)
            for ((x, y), expected) in zip([(0, 0), (24, 15), (47, 29)], colors) {
                let i = (y * 48 + x) * 4
                let channels = [expected >> 16 & 0xFF, expected >> 8 & 0xFF, expected & 0xFF]
                for c in 0 ..< 3 {
                    XCTAssertLessThanOrEqual(abs(Int(pixels[i + c]) - Int(channels[c])), 1, "\(gradient) at \(x),\(y)")
                }
            }
            var fnv: UInt64 = 0xCBF2_9CE4_8422_2325
            for byte in pixels {
                fnv ^= UInt64(byte)
                fnv = fnv &* 0x100_0000_01B3
            }
            XCTAssertEqual(fnv, hash, "\(gradient) differs from the desktop bitmap")
        }
    }

    func testNextStaysWithinTheTone() {
        var gradient = SpaceGradient.forest
        for _ in SpaceGradient.dark {
            gradient = gradient.next
            XCTAssertEqual(gradient.tone, .dark)
        }
        XCTAssertEqual(gradient, .forest)
        XCTAssertEqual(SpaceGradient.citrus.next, .lavenderBlush)
    }

    func testOldAccentsMapToLightThemes() {
        let expected: [AccentColor: SpaceGradient] = [
            .iris: .iris, .ocean: .skyHaze, .lagoon: .aurora, .sage: .mintCream, .citrine: .citrus,
            .amber: .sand, .coral: .peachGlow, .rose: .roseFog, .plum: .lavenderBlush, .graphite: .aurora,
        ]
        for accent in AccentColor.allCases {
            XCTAssertEqual(SpaceGradient.from(accent: accent), expected[accent])
            XCTAssertEqual(SpaceGradient.from(accent: accent).tone, .light)
        }
    }

    func testNamesAreStableForStorage() throws {
        let data = try JSONEncoder().encode([SpaceGradient.midnightIndigo, .lavenderBlush, .ember])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["midnight_indigo","lavender_blush","ember"]"#)
    }

    // MARK: - Storage

    func testSpaceGradientsRoundTripAndOldSpacesGetOne() throws {
        let space = Space(name: "Night", icon: "☾", gradient: .forest)
        let data = try JSONEncoder().encode(space)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["gradient"] as? String, "forest")
        // Older builds still find an accent.
        XCTAssertEqual(json["color"] as? String, "sage")
        XCTAssertEqual(try JSONDecoder().decode(Space.self, from: data).gradient, .forest)

        let old = Data(#"{"name":"Old","icon":"✦","color":"coral"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(Space.self, from: old).gradient, .peachGlow)
        let bare = Data(#"{"name":"Bare"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(Space.self, from: bare).gradient, .lavenderBlush)
        let unknown = Data(#"{"name":"New","gradient":"neon","color":"rose"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(Space.self, from: unknown).gradient, .roseFog)
    }

    // MARK: - Theme tokens

    func testToneSetsTheAppearance() {
        XCTAssertEqual(CurioTheme(gradient: .lavenderBlush).appearance, .light)
        XCTAssertEqual(CurioTheme(gradient: .forest).appearance, .dark)
        for gradient in SpaceGradient.allCases {
            XCTAssertEqual(CurioTheme(gradient: gradient).appearance == .light, gradient.tone == .light)
        }
    }

    /// Every point of the sidebar (the left fifth of the window), for every
    /// theme, keeps text readable: AAA for titles, AA for secondary text, and
    /// AA for the selected row's text on its raised background.
    func testTextStaysReadableOnEveryGradient() {
        for gradient in SpaceGradient.allCases {
            let theme = CurioTheme(gradient: gradient)
            for i in 0 ... 8 {
                for j in 0 ... 20 {
                    let (x, y) = (Float(i) * 0.025, Float(j) / 20)
                    let bg = Self.background(gradient, x: x, y: y, aspect: 1.6)
                    XCTAssertGreaterThanOrEqual(Self.contrast(theme.text, on: bg), 7, "\(gradient) text at \(x),\(y)")
                    XCTAssertGreaterThanOrEqual(Self.contrast(theme.textMuted, on: bg), 4.5, "\(gradient) muted at \(x),\(y)")
                    let selected = Self.over(theme.rowActive, bg)
                    XCTAssertGreaterThanOrEqual(Self.contrast(theme.rowActiveText, on: selected), 4.5, "\(gradient) selected at \(x),\(y)")
                }
            }
        }
    }

    /// The phone's bottom bar spans the bottom tenth of the window, the
    /// brightest part of a dark theme, in portrait and landscape. With its
    /// shade, the address (on the field) and the icons stay readable.
    func testBottomBarStaysReadableOnEveryGradient() {
        for gradient in SpaceGradient.allCases {
            let theme = CurioTheme(gradient: gradient)
            for aspect: Float in [0.46, 2.17] {
                for i in 0 ... 20 {
                    for j in 0 ... 10 {
                        let (x, y) = (Float(i) / 20, 0.9 + Float(j) / 100)
                        let bg = Self.over(theme.bottomBarShade, Self.background(gradient, x: x, y: y, aspect: aspect))
                        Self.assertReadable(theme, on: [bg, Self.over(theme.field, bg)], "\(gradient) bottom bar at \(x),\(y) aspect \(aspect)")
                    }
                }
            }
        }
    }

    /// On iPad the toolbar runs along the top of the window, beside the
    /// sidebar, in landscape and portrait.
    func testToolbarStaysReadableOnEveryGradient() {
        for gradient in SpaceGradient.allCases {
            let theme = CurioTheme(gradient: gradient)
            for aspect: Float in [1.6, 0.75] {
                for i in 0 ... 20 {
                    for j in 0 ... 8 {
                        let (x, y) = (Float(i) / 20, Float(j) / 100)
                        let bg = Self.background(gradient, x: x, y: y, aspect: aspect)
                        Self.assertReadable(theme, on: [bg, Self.over(theme.field, bg)], "\(gradient) toolbar at \(x),\(y) aspect \(aspect)")
                    }
                }
            }
        }
    }

    /// The tabs drawer shows the same slice of the gradient as the desktop
    /// sidebar (checked above), not the whole window squeezed to fit.
    @MainActor
    func testDrawerShowsTheSidebarSlice() throws {
        let window = try XCTUnwrap(GradientImages.image(.forest, .landscape).cgImage)
        let slice = try XCTUnwrap(GradientImages.image(.forest, .sidebar).cgImage)
        XCTAssertEqual(slice.width * 5, window.width)
        XCTAssertEqual(slice.height, window.height)
        let portrait = try XCTUnwrap(GradientImages.image(.forest, .portrait).cgImage)
        XCTAssertEqual([portrait.width, portrait.height], [300, 480])
    }

    private static func assertReadable(_ theme: CurioTheme, on surfaces: [RGB], _ message: String, line: UInt = #line) {
        for surface in surfaces {
            XCTAssertGreaterThanOrEqual(contrast(theme.text, on: surface), 7, "text: \(message)", line: line)
            XCTAssertGreaterThanOrEqual(contrast(theme.textMuted, on: surface), 4.5, "muted: \(message)", line: line)
        }
    }

    // MARK: - Helpers

    private typealias RGB = (r: Double, g: Double, b: Double)

    private static func background(_ gradient: SpaceGradient, x: Float, y: Float, aspect: Float) -> RGB {
        let c = gradient.spec.sample(x: x, y: y, aspect: aspect)
        return (Double(c.x), Double(c.y), Double(c.z))
    }

    private static func rgba(_ color: HSLA) -> (RGB, Double) {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        color.uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return ((Double(r), Double(g), Double(b)), Double(a))
    }

    /// `top` (which may be translucent) drawn over the opaque `bottom`.
    private static func over(_ top: HSLA, _ bottom: RGB) -> RGB {
        let (t, a) = rgba(top)
        return (t.r * a + bottom.r * (1 - a), t.g * a + bottom.g * (1 - a), t.b * a + bottom.b * (1 - a))
    }

    private static func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.040_45 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private static func contrast(_ text: HSLA, on bg: RGB) -> Double {
        let fg = over(text, bg)
        let (la, lb) = (luminance(fg.r, fg.g, fg.b), luminance(bg.r, bg.g, bg.b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
