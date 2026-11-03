import UIKit

/// A small filled circle in an accent color.
final class ColorDotView: UIView {
    private var sizeConstraints: [NSLayoutConstraint] = []

    init(color: UIColor, diameter: CGFloat = 8) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = color
        isUserInteractionEnabled = false
        setDiameter(diameter)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setDiameter(_ diameter: CGFloat) {
        NSLayoutConstraint.deactivate(sizeConstraints)
        sizeConstraints = [widthAnchor.constraint(equalToConstant: diameter), heightAnchor.constraint(equalToConstant: diameter)]
        NSLayoutConstraint.activate(sizeConstraints)
        layer.cornerRadius = diameter / 2
    }
}
