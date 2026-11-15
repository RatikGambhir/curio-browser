import UIKit

/// Lays out the page area's panes: one pane filling it, or the panes of a
/// split view side by side (or stacked) with an 8pt gap. Each gap holds a
/// divider that resizes its neighbors when dragged (its touch target is 44pt
/// although the gap is 8pt) and makes every pane equal when double-tapped.
final class SplitContainerView: UIView {
    private(set) var panes: [UIView] = []
    private var dividers: [SplitDividerView] = []
    private(set) var sizes: [Double] = [1]
    private(set) var orientation: SplitOrientation = .horizontal
    /// The boundary (cumulative share) before the dragged divider, when the
    /// drag began.
    private var dragStart: Double = 0

    /// Asks to move divider `index` by a share of the split; returns the new
    /// sizes when anything moved.
    var onResize: ((_ divider: Int, _ delta: Double) -> [Double]?)?
    var onEqualize: (() -> Void)?

    /// Shows `panes` with their shares. Panes already shown keep their place
    /// in the view hierarchy, so their web views are never re-parented.
    func show(_ panes: [UIView], sizes: [Double], orientation: SplitOrientation) {
        for old in self.panes where !panes.contains(where: { $0 === old }) {
            old.removeFromSuperview()
        }
        for pane in panes where pane.superview !== self {
            pane.translatesAutoresizingMaskIntoConstraints = true
            addSubview(pane)
        }
        self.panes = panes
        self.sizes = sizes.count == panes.count ? sizes : Array(repeating: 1 / Double(max(panes.count, 1)), count: panes.count)
        self.orientation = orientation
        let needed = max(panes.count - 1, 0)
        while dividers.count > needed { dividers.removeLast().removeFromSuperview() }
        while dividers.count < needed { dividers.append(makeDivider()) }
        for (index, divider) in dividers.enumerated() {
            divider.index = index
            divider.orientation = orientation
            bringSubviewToFront(divider)
        }
        setNeedsLayout()
    }

    /// Updates pane shares during a drag without touching the hierarchy.
    func update(sizes: [Double]) {
        guard sizes.count == panes.count else { return }
        self.sizes = sizes
        setNeedsLayout()
        layoutIfNeeded()
    }

    private var horizontal: Bool { orientation == .horizontal }
    private var length: CGFloat { horizontal ? bounds.width : bounds.height }
    private var room: CGFloat { max(length - SplitRoom.gap * CGFloat(max(panes.count - 1, 0)), 0) }

    override func layoutSubviews() {
        super.layoutSubviews()
        var offset: CGFloat = 0
        for (index, pane) in panes.enumerated() {
            // The last pane takes what is left, so rounding never leaves a seam.
            let extent = index == panes.count - 1 ? length - offset : (room * sizes[index]).rounded()
            pane.frame = horizontal
                ? CGRect(x: offset, y: 0, width: max(extent, 0), height: bounds.height)
                : CGRect(x: 0, y: offset, width: bounds.width, height: max(extent, 0))
            offset += extent
            if index < dividers.count {
                let touch = Metrics.minTouch
                let center = offset + SplitRoom.gap / 2
                dividers[index].frame = horizontal
                    ? CGRect(x: center - touch / 2, y: 0, width: touch, height: bounds.height)
                    : CGRect(x: 0, y: center - touch / 2, width: bounds.width, height: touch)
                offset += SplitRoom.gap
            }
        }
    }

    // MARK: - Dividers

    private func makeDivider() -> SplitDividerView {
        let divider = SplitDividerView()
        addSubview(divider)
        divider.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dividerPan(_:))))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(dividerDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        divider.addGestureRecognizer(doubleTap)
        divider.onAccessibilityAdjust = { [weak self, weak divider] step in
            guard let self, let divider, let sizes = onResize?(divider.index, step) else { return }
            update(sizes: sizes)
        }
        divider.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Equal Pane Sizes") { [weak self] _ in
            self?.onEqualize?()
            return true
        }]
        return divider
    }

    @objc private func dividerPan(_ pan: UIPanGestureRecognizer) {
        guard let divider = pan.view as? SplitDividerView, divider.index + 1 < sizes.count else { return }
        let index = divider.index
        switch pan.state {
        case .began:
            dragStart = sizes.prefix(index + 1).reduce(0, +)
            divider.dragging = true
        case .changed:
            let translation = pan.translation(in: self)
            let moved = horizontal ? translation.x : translation.y
            // Where the divider's center now is, as a share of the panes' room.
            let startCenter = room * dragStart + SplitRoom.gap * CGFloat(index) + SplitRoom.gap / 2
            guard let target = SplitRoom.dividerFraction(pointer: startCenter + moved, length: length, panes: panes.count, divider: index) else { return }
            let boundary = sizes.prefix(index + 1).reduce(0, +)
            if let sizes = onResize?(index, target - boundary) { update(sizes: sizes) }
        default:
            divider.dragging = false
        }
    }

    @objc private func dividerDoubleTap(_ tap: UITapGestureRecognizer) {
        if tap.state == .ended { onEqualize?() }
    }
}

/// The grab area in a split view's gap: a short line that shows while the
/// pointer is over it or it is dragged.
final class SplitDividerView: UIView, ThemeObserving {
    var index = 0
    var orientation: SplitOrientation = .horizontal {
        didSet { setNeedsLayout() }
    }
    var dragging = false { didSet { restyle() } }
    var onAccessibilityAdjust: ((Double) -> Void)?
    private let line = UIView()
    private var hovered = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        line.isUserInteractionEnabled = false
        line.layer.cornerRadius = 1
        addSubview(line)
        HoverTracker(self) { [weak self] in
            self?.hovered = $0
            self?.restyle()
        }
        isAccessibilityElement = true
        accessibilityLabel = "Pane Divider"
        accessibilityTraits = .adjustable
        accessibilityHint = "Swipe up or down to resize the panes beside it."
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func themeDidChange(_ theme: CurioTheme) { restyle() }

    private func restyle() {
        let theme = ThemeCenter.shared.theme
        // Touch has no hover, so a faint line always shows where to grab.
        let touchOnly = !HoverTracker.pointerSeen
        line.backgroundColor = dragging ? theme.accent.uiColor : theme.textFaint.uiColor
        line.alpha = dragging || hovered ? 1 : (touchOnly ? 0.45 : 0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let long: CGFloat = 36
        line.frame = orientation == .horizontal
            ? CGRect(x: bounds.midX - 1, y: bounds.midY - long / 2, width: 2, height: long)
            : CGRect(x: bounds.midX - long / 2, y: bounds.midY - 1, width: long, height: 2)
        restyle()
    }

    override func accessibilityIncrement() { onAccessibilityAdjust?(0.05) }
    override func accessibilityDecrement() { onAccessibilityAdjust?(-0.05) }
}
