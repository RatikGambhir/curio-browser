import UIKit

extension NSLayoutConstraint {
    /// Returns the constraint with a different priority, for inline use.
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
