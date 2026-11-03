import UIKit

/// Reports pointer hover (iPad trackpad or mouse) on a view. The recognizer
/// adds itself to the view, which keeps it alive.
final class HoverTracker: UIHoverGestureRecognizer {
    private let onChange: (Bool) -> Void

    @discardableResult
    init(_ view: UIView, onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(hovered))
        // Hover only observes; it must never steal taps from the view.
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        view.addGestureRecognizer(self)
    }

    @objc private func hovered() {
        switch state {
        case .began, .changed: onChange(true)
        default: onChange(false)
        }
    }
}
