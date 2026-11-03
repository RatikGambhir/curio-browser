import UIKit

/// Wraps a `SidebarDrag` so it can travel as a drag item's local object.
final class SidebarDragBox {
    let drag: SidebarDrag
    init(_ drag: SidebarDrag) { self.drag = drag }
}
