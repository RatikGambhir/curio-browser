import UIKit

/// About Curio.
final class AboutViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "About"
        let theme = ThemeCenter.shared.theme
        view.backgroundColor = theme.surface.uiColor
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        let name = UILabel()
        name.text = "Curio"
        name.font = CurioFont.size(22, .bold)
        name.textColor = theme.text.uiColor
        let version = UILabel()
        let number = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        version.text = "Version \(number)"
        version.font = CurioFont.sm()
        version.textColor = theme.textMuted.uiColor
        let blurb = UILabel()
        blurb.text = "A curious browser: spaces for every part of your life, and an assistant that reads along with you."
        blurb.font = CurioFont.sm()
        blurb.textColor = theme.textMuted.uiColor
        blurb.numberOfLines = 0
        blurb.textAlignment = .center
        let credit = UILabel()
        credit.text = "Built with Swift and UIKit · Pages rendered by WebKit"
        credit.font = CurioFont.xs()
        credit.textColor = theme.textFaint.uiColor
        credit.numberOfLines = 0
        credit.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [LogoView(size: 88), name, version, blurb, credit])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }
}
