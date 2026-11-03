import Foundation

/// A weak reference to any object.
final class WeakBox {
    weak var value: AnyObject?
    init(_ value: AnyObject) { self.value = value }
}
