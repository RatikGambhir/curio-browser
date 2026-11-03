import UIKit

/// Corner radii and sizes shared across components (matching the desktop
/// app, with rows a little taller for touch).
enum Metrics {
    static let cardRadius: CGFloat = 12
    static let rowRadius: CGFloat = 8
    static let fieldRadius: CGFloat = 9
    static let panelGap: CGFloat = 8
    static let toolbarHeight: CGFloat = 44
    /// Minimum hit target for touch.
    static let minTouch: CGFloat = 44

    /// Sidebar and list row height: 34pt like the desktop on iPad with a
    /// pointer, 40pt on phones.
    static func rowHeight(compact: Bool) -> CGFloat {
        UIFontMetrics.default.scaledValue(for: compact ? 40 : 36)
    }

    /// The fastest-settling ease-out curve the desktop uses for slides.
    static let easeOutQuint = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.22, y: 1), controlPoint2: CGPoint(x: 0.36, y: 1))
}
