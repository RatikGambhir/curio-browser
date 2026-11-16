import UIKit

/// While a tab is dragged from the sidebar or tab strip, the page area
/// splits into a left and a right drop zone: dropping on the left shows the
/// tab before the current page in a split view, on the right after it.
///
/// It sits on top of the page only during such a drag, so web views (which
/// take URL drops themselves) never see the tab.
final class SplitDropOverlay: UIView, UIDropInteractionDelegate, ThemeObserving {
    private let before = UIView()
    private let after = UIView()
    private var side: Bool?
    /// A tab was dropped; `before` tells which side.
    var onDrop: ((_ tab: UUID, _ before: Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        for zone in [before, after] {
            zone.isUserInteractionEnabled = false
            zone.layer.cornerRadius = Metrics.cardRadius
            zone.layer.cornerCurve = .continuous
            zone.alpha = 0
            addSubview(zone)
        }
        addInteraction(UIDropInteraction(delegate: self))
        isHidden = true
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func themeDidChange(_ theme: CurioTheme) {
        for zone in [before, after] {
            zone.backgroundColor = theme.accentSoft.uiColor
            zone.layer.borderColor = theme.accent.uiColor.cgColor
            zone.layer.borderWidth = 2
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset: CGFloat = 6
        let half = bounds.width / 2
        before.frame = CGRect(x: 0, y: 0, width: half, height: bounds.height).insetBy(dx: inset, dy: inset)
        after.frame = CGRect(x: half, y: 0, width: half, height: bounds.height).insetBy(dx: inset, dy: inset)
    }

    /// Takes drops while a tab drag is in progress.
    func setActive(_ active: Bool) {
        isHidden = !active
        if !active { highlight(nil) }
    }

    private func highlight(_ side: Bool?) {
        guard side != self.side else { return }
        self.side = side
        let changes = {
            self.before.alpha = side == true ? 1 : 0
            self.after.alpha = side == false ? 1 : 0
        }
        if ThemeCenter.shared.motionEnabled {
            UIView.animate(withDuration: 0.12, animations: changes)
        } else {
            changes()
        }
    }

    private static func tab(in session: UIDropSession) -> UUID? {
        guard let box = session.localDragSession?.items.first?.localObject as? SidebarDragBox,
              case .tab(let id) = box.drag else { return nil }
        return id
    }

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        Self.tab(in: session) != nil
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        highlight(session.location(in: self).x < bounds.midX)
        return UIDropProposal(operation: .move)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
        highlight(nil)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
        highlight(nil)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        guard let id = Self.tab(in: session) else { return }
        let before = session.location(in: self).x < bounds.midX
        highlight(nil)
        onDrop?(id, before)
    }
}
