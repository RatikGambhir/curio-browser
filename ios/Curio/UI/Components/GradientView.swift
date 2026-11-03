import UIKit

/// A view backed by a vertical `CAGradientLayer`.
final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    private var gradient: CAGradientLayer { layer as? CAGradientLayer ?? CAGradientLayer() }

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Sets the colors, cross-fading over `duration` when it is positive.
    func setColors(_ top: UIColor, _ bottom: UIColor, duration: TimeInterval = 0) {
        let colors = [top.cgColor, bottom.cgColor]
        if duration > 0 {
            let animation = CABasicAnimation(keyPath: "colors")
            animation.fromValue = gradient.presentation()?.colors ?? gradient.colors
            animation.toValue = colors
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            gradient.add(animation, forKey: "colors")
        }
        gradient.colors = colors
    }
}
