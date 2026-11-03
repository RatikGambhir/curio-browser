import UIKit

/// A draggable divider between columns (the sidebar and the assistant).
/// Shows a line on hover and an accent line while dragging.
final class ResizeHandleView: UIView {
    private let line = UIView()
    private var startValue: CGFloat = 0
    /// Returns the current width when a drag starts.
    var currentValue: (() -> CGFloat)?
    /// Called with the new width as the drag moves (`translation` is applied
    /// by the caller's sign).
    var onChange: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    /// +1 when dragging right widens, -1 when dragging left widens.
    var direction: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        line.translatesAutoresizingMaskIntoConstraints = false
        line.layer.cornerRadius = 1
        addSubview(line)
        NSLayoutConstraint.activate([
            line.centerXAnchor.constraint(equalTo: centerXAnchor),
            line.widthAnchor.constraint(equalToConstant: 2),
            line.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            line.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
        HoverTracker(self) { [weak self] inside in
            self?.line.backgroundColor = inside ? ThemeCenter.shared.theme.divider.uiColor : .clear
        }
        addInteraction(UIPointerInteraction(delegate: self))
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func pan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            startValue = currentValue?() ?? 0
            line.backgroundColor = ThemeCenter.shared.theme.accent.uiColor
        case .changed:
            onChange?(startValue + recognizer.translation(in: superview).x * direction)
        default:
            line.backgroundColor = .clear
            onEnd?()
        }
    }

    /// Widens the touch target beyond the 6pt visual handle.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -8, dy: 0).contains(point)
    }
}

extension ResizeHandleView: UIPointerInteractionDelegate {
    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        UIPointerStyle(shape: .verticalBeam(length: 28), constrainedAxes: .vertical)
    }
}
