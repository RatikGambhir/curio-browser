import UIKit

/// Lays out its subviews in centered rows that wrap, like CSS `flex-wrap`.
/// Subviews report their size through `intrinsicContentSize`.
final class FlowLayoutView: UIView {
    var spacing: CGFloat = 6 { didSet { setNeedsLayout() } }
    var lineSpacing: CGFloat = 6 { didSet { setNeedsLayout() } }
    var centered = true
    private var lastHeight: CGFloat = 0

    func setItems(_ views: [UIView]) {
        subviews.forEach { $0.removeFromSuperview() }
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = true
            addSubview($0)
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func rows(for width: CGFloat) -> [[UIView]] {
        var rows: [[UIView]] = [[]]
        var x: CGFloat = 0
        for view in subviews {
            let size = view.intrinsicContentSize
            if x > 0 && x + size.width > width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(view)
            x += size.width + spacing
        }
        return rows.filter { !$0.isEmpty }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var y: CGFloat = 0
        for row in rows(for: bounds.width) {
            let widths = row.map(\.intrinsicContentSize.width)
            let height = row.map(\.intrinsicContentSize.height).max() ?? 0
            let total = widths.reduce(0, +) + spacing * CGFloat(row.count - 1)
            var x = centered ? max(0, (bounds.width - total) / 2) : 0
            for (view, width) in zip(row, widths) {
                view.frame = CGRect(x: x, y: y, width: width, height: view.intrinsicContentSize.height)
                x += width + spacing
            }
            y += height + lineSpacing
        }
        let height = max(0, y - lineSpacing)
        if height != lastHeight {
            lastHeight = height
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: lastHeight)
    }
}
