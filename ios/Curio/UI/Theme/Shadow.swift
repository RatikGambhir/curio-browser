import UIKit

/// The desktop's shadow scale, applied to a layer. Callers set
/// `shadowPath` in `layoutSubviews` so shadows are cheap to render.
enum Shadow {
    case xs, sm, md, lg, xl, xxl

    func apply(to layer: CALayer, dark: Bool) {
        let (radius, y, opacity): (CGFloat, CGFloat, Float) = switch self {
        case .xs: (1, 1, 0.05)
        case .sm: (2, 1, 0.10)
        case .md: (4, 3, 0.10)
        case .lg: (8, 6, 0.12)
        case .xl: (14, 12, 0.14)
        case .xxl: (26, 18, 0.25)
        }
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = radius
        layer.shadowOffset = CGSize(width: 0, height: y)
        layer.shadowOpacity = dark ? min(opacity * 2.2, 0.6) : opacity
    }
}
