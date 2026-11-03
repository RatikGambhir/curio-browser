import UIKit

/// "Tabs you open in this space appear here…"
final class EmptyHintCell: UICollectionViewListCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundConfiguration = .clear()
        let hint = EmptyStateView(title: "Tabs you open in this space appear here. Drag tabs above the line to pin them.", compact: true)
        hint.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hint.topAnchor.constraint(equalTo: contentView.topAnchor),
            hint.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
