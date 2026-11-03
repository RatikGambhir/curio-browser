import UIKit

/// A thin indeterminate progress bar: an accent segment sweeping across.
final class LoadingBarView: UIView, ThemeObserving {
    private let bar = CALayer()
    private let fraction: CGFloat
    private let period: CFTimeInterval

    init(fraction: CGFloat = 0.3, period: CFTimeInterval = 1.2) {
        self.fraction = fraction
        self.period = period
        super.init(frame: .zero)
        clipsToBounds = true
        isUserInteractionEnabled = false
        layer.addSublayer(bar)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 2).isActive = true
        isAccessibilityElement = true
        accessibilityLabel = "Loading"
        accessibilityTraits = .updatesFrequently
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func themeDidChange(_ theme: CurioTheme) {
        bar.backgroundColor = theme.accent.uiColor.cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width * fraction
        bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        bar.cornerRadius = bounds.height / 2
        bar.position = CGPoint(x: -width / 2, y: bounds.midY)
        restart()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        restart()
    }

    private func restart() {
        bar.removeAllAnimations()
        guard window != nil, !isHidden, bounds.width > 0 else { return }
        let width = bounds.width * fraction
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = -width / 2
        animation.toValue = bounds.width + width / 2
        animation.duration = period
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bar.add(animation, forKey: "sweep")
    }

    override var isHidden: Bool {
        didSet { restart() }
    }
}
