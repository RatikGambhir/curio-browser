import UIKit

/// A downloaded image or video in the library's media grid.
final class MediaTileView: TapControl {
    init(name: String, url: URL, image: Bool, action: UIAction) {
        super.init(frame: .zero)
        let theme = ThemeCenter.shared.theme
        let box = UIView()
        box.layer.cornerRadius = 10
        box.layer.cornerCurve = .continuous
        box.layer.borderWidth = 1
        box.layer.borderColor = theme.surfaceBorder.uiColor.cgColor
        box.backgroundColor = theme.surfaceRaised.uiColor
        box.clipsToBounds = true
        box.isUserInteractionEnabled = false
        let preview = UIImageView()
        preview.contentMode = image ? .scaleAspectFill : .center
        preview.tintColor = theme.textFaint.uiColor
        preview.image = (image ? Icon.photo : Icon.film).image(24, weight: .light)
        preview.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(preview)
        let label = UILabel()
        label.text = name
        label.font = CurioFont.xs()
        label.textColor = theme.textMuted.uiColor
        label.lineBreakMode = .byTruncatingMiddle
        let stack = UIStackView(arrangedSubviews: [box, label])
        stack.axis = .vertical
        stack.spacing = 4
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            box.heightAnchor.constraint(equalToConstant: 96),
            preview.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            preview.topAnchor.constraint(equalTo: box.topAnchor),
            preview.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        addAction(action, for: .primaryActionTriggered)
        isAccessibilityElement = true
        accessibilityLabel = name
        accessibilityTraits = .button
        if image {
            Task { [weak preview] in
                if let thumbnail = await Self.thumbnail(url) { preview?.image = thumbnail }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Reads and downsamples the image off the main thread.
    @concurrent
    private nonisolated static func thumbnail(_ url: URL) async -> UIImage? {
        UIImage(contentsOfFile: url.path(percentEncoded: false))?.preparingThumbnail(of: CGSize(width: 240, height: 240))
    }
}
