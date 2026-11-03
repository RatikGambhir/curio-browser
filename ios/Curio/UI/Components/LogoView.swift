import UIKit

/// Curio's logo mark.
final class LogoView: UIImageView {
    init(size: CGFloat) {
        super.init(image: UIImage(named: "Logo"))
        contentMode = .scaleAspectFit
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
