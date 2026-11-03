import UIKit

/// Curio's type scale. Sizes match the desktop app at the default text size
/// and scale with Dynamic Type (capped so chrome stays usable).
enum CurioFont {
    /// 12pt
    static func xs(_ weight: UIFont.Weight = .regular) -> UIFont { scaled(12, weight) }
    /// 14pt
    static func sm(_ weight: UIFont.Weight = .regular) -> UIFont { scaled(14, weight) }
    /// 16pt
    static func base(_ weight: UIFont.Weight = .regular) -> UIFont { scaled(16, weight) }
    /// 18pt
    static func lg(_ weight: UIFont.Weight = .regular) -> UIFont { scaled(18, weight) }

    static func size(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont { scaled(size, weight) }

    static func mono(_ size: CGFloat) -> UIFont {
        UIFontMetrics.default.scaledFont(for: .monospacedSystemFont(ofSize: size, weight: .regular), maximumPointSize: size * 1.6)
    }

    private static func scaled(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: size, weight: weight), maximumPointSize: size * 1.6)
    }
}
