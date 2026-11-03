import UIKit

/// A color in HSL space with alpha, all components in 0...1. Curio's palette
/// is derived in HSL so light and dark tints of any accent stay consistent.
nonisolated struct HSLA: Equatable, Sendable {
    var h: Double
    var s: Double
    var l: Double
    var a: Double

    init(_ h: Double, _ s: Double, _ l: Double, _ a: Double = 1) {
        self.h = h
        self.s = s
        self.l = l
        self.a = a
    }

    /// Converts `0xRRGGBB`.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let l = (maxC + minC) / 2
        var h = 0.0
        var s = 0.0
        if maxC != minC {
            let d = maxC - minC
            s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC)
            if maxC == r {
                h = (g - b) / d + (g < b ? 6 : 0)
            } else if maxC == g {
                h = (b - r) / d + 2
            } else {
                h = (r - g) / d + 4
            }
            h /= 6
        }
        self.init(h, s, l, 1)
    }

    func withAlpha(_ a: Double) -> HSLA { HSLA(h, s, l, a) }

    var uiColor: UIColor {
        func hue(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        let s = min(max(s, 0), 1)
        let l = min(max(l, 0), 1)
        guard s > 0 else { return UIColor(red: l, green: l, blue: l, alpha: a) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return UIColor(red: hue(p, q, h + 1 / 3), green: hue(p, q, h), blue: hue(p, q, h - 1 / 3), alpha: a)
    }

    /// Linear blend that takes the shortest way around the hue circle.
    static func mix(_ a: HSLA, _ b: HSLA, _ t: Double) -> HSLA {
        let t = min(max(t, 0), 1)
        var dh = b.h - a.h
        if dh > 0.5 { dh -= 1 } else if dh < -0.5 { dh += 1 }
        var h = (a.h + dh * t).truncatingRemainder(dividingBy: 1)
        if h < 0 { h += 1 }
        return HSLA(h, a.s + (b.s - a.s) * t, a.l + (b.l - a.l) * t, a.a + (b.a - a.a) * t)
    }
}
