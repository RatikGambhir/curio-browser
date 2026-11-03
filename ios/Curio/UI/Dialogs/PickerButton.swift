import UIKit

/// A fixed-size square button for icon and color pickers.
final class PickerButton: UIButton {
    private let side: CGFloat

    init(size: CGFloat) {
        side = size
        super.init(frame: .zero)
        isPointerInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: CGSize { CGSize(width: side, height: side) }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -4, dy: -4).contains(point)
    }
}
