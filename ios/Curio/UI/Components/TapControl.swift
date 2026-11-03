import UIKit

/// A control that fires `.primaryActionTriggered` when tapped (plain
/// `UIControl`s don't), when activated with VoiceOver, and when pressed with
/// a keyboard while focused.
class TapControl: UIControl {
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        if let touch, bounds.insetBy(dx: -8, dy: -8).contains(touch.location(in: self)) {
            sendActions(for: .primaryActionTriggered)
        }
    }

    override func accessibilityActivate() -> Bool {
        sendActions(for: .primaryActionTriggered)
        return true
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if isFocused, presses.contains(where: { $0.key?.keyCode == .keyboardReturnOrEnter || $0.key?.keyCode == .keyboardSpacebar }) {
            sendActions(for: .primaryActionTriggered)
        } else {
            super.pressesEnded(presses, with: event)
        }
    }
}
