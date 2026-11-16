import UIKit

final class MediaTileCell: UICollectionViewCell, ThemeObserving {
    private let box = UIView()
    private let preview = UIImageView()
    private let name = UILabel()
    private let folder = UILabel()
    private weak var thumbnails: MediaThumbnails?
    private var requestID: UUID?
    private(set) var item: MediaItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        box.layer.cornerRadius = 10
        box.layer.cornerCurve = .continuous
        box.layer.borderWidth = 1
        box.clipsToBounds = true
        preview.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(preview)

        name.font = .preferredFont(forTextStyle: .footnote)
        name.adjustsFontForContentSizeCategory = true
        name.lineBreakMode = .byTruncatingMiddle
        name.numberOfLines = 2
        folder.font = .preferredFont(forTextStyle: .caption2)
        folder.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [box, name, folder])
        stack.axis = .vertical
        stack.spacing = 2
        stack.setCustomSpacing(5, after: box)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            box.heightAnchor.constraint(equalToConstant: 140),
            preview.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            preview.topAnchor.constraint(equalTo: box.topAnchor),
            preview.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Opens a preview"
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func prepareForReuse() {
        super.prepareForReuse()
        stopThumbnail()
        item = nil
    }

    func configure(_ item: MediaItem) {
        stopThumbnail()
        self.item = item
        name.text = item.name
        folder.text = item.folder
        accessibilityLabel = "\(item.name), \(item.folder)"
    }

    func loadThumbnail(using thumbnails: MediaThumbnails) {
        guard let item else { return }
        stopThumbnail()
        self.thumbnails = thumbnails
        requestID = thumbnails.request(item) { [weak self] image in
            guard let self, self.item == item else { return }
            requestID = nil
            preview.contentMode = image == nil ? .center : .scaleAspectFill
            preview.image = image ?? (item.kind == .video ? Icon.film : Icon.photo).image(24, weight: .light)
        }
    }

    func stopThumbnail() {
        if let requestID { thumbnails?.cancel(requestID) }
        requestID = nil
        preview.image = nil
    }

    func themeDidChange(_ theme: CurioTheme) {
        box.layer.borderColor = theme.surfaceBorder.uiColor.cgColor
        box.backgroundColor = theme.surfaceRaised.uiColor
        name.textColor = theme.text.uiColor
        folder.textColor = theme.textMuted.uiColor
        preview.tintColor = theme.textFaint.uiColor
    }
}
