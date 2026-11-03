import UIKit

/// Short notifications ("Bookmarked", "Download complete") shown over the
/// browser for a few seconds.
final class ToastPresenter {
    enum Kind { case info, success, error }

    private weak var host: UIView?
    private var current: UIView?
    private var dismissTask: Task<Void, Never>?
    /// Distance from the bottom edge of the safe area (above bottom bars).
    var bottomInset: CGFloat = 16

    init(host: UIView) {
        self.host = host
    }

    func show(_ message: String, title: String? = nil, kind: Kind = .info) {
        guard let host else { return }
        current?.removeFromSuperview()
        dismissTask?.cancel()
        let theme = ThemeCenter.shared.theme
        let toast = UIView()
        toast.backgroundColor = theme.surfaceRaised.uiColor
        toast.layer.cornerRadius = 12
        toast.layer.cornerCurve = .continuous
        toast.layer.borderWidth = 1
        toast.layer.borderColor = theme.surfaceBorder.uiColor.cgColor
        Shadow.xl.apply(to: toast.layer, dark: theme.appearance == .dark)
        let icon = UIImageView(image: (kind == .error ? Icon.xCircle : kind == .success ? Icon.checkCircle : Icon.info).image(15))
        icon.tintColor = kind == .error ? theme.danger.uiColor : kind == .success ? theme.success.uiColor : theme.accentText.uiColor
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = CurioFont.sm(.semibold)
        titleLabel.textColor = theme.text.uiColor
        titleLabel.isHidden = title == nil
        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.font = CurioFont.sm()
        messageLabel.textColor = title == nil ? theme.text.uiColor : theme.textMuted.uiColor
        messageLabel.numberOfLines = 2
        let labels = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        labels.axis = .vertical
        labels.spacing = 1
        let stack = UIStackView(arrangedSubviews: [icon, labels])
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        toast.addSubview(stack)
        toast.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(toast)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: toast.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: toast.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: toast.topAnchor, constant: 11),
            stack.bottomAnchor.constraint(equalTo: toast.bottomAnchor, constant: -11),
            toast.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            toast.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: host.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            toast.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -bottomInset),
        ])
        current = toast
        host.layoutIfNeeded()
        toast.layer.shadowPath = UIBezierPath(roundedRect: toast.bounds, cornerRadius: 12).cgPath
        UIAccessibility.post(notification: .announcement, argument: [title, message].compactMap(\.self).joined(separator: ". "))
        toast.alpha = 0
        toast.transform = CGAffineTransform(translationX: 0, y: 12)
        UIView.animate(withDuration: ThemeCenter.shared.motionEnabled ? 0.2 : 0) {
            toast.alpha = 1
            toast.transform = .identity
        }
        dismissTask = Task { [weak self, weak toast] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled, let toast else { return }
            UIView.animate(withDuration: 0.2, animations: { toast.alpha = 0 }, completion: { _ in
                toast.removeFromSuperview()
                if self?.current === toast { self?.current = nil }
            })
        }
    }
}
