import UIKit

/// The icons Curio uses, as SF Symbols (the desktop uses the matching Lucide
/// icons).
enum Icon: String {
    case back = "arrow.left"
    case forward = "arrow.right"
    case reload = "arrow.clockwise"
    case close = "xmark"
    case sparkles
    case download = "arrow.down"
    case downloadCircle = "arrow.down.circle"
    case settings = "gearshape"
    case sidebar = "sidebar.left"
    case sidebarRight = "sidebar.right"
    case plus
    case minus
    case ellipsis
    case star
    case heart
    case copy = "doc.on.doc"
    case link
    case folder
    case folderFill = "folder.fill"
    case folderPlus = "folder.badge.plus"
    case folderMinus = "folder.badge.minus"
    case xCircle = "xmark.circle"
    case undo = "arrow.uturn.backward"
    case trash
    case palette = "paintpalette"
    case chevronLeft = "chevron.left"
    case chevronRight = "chevron.right"
    case chevronDown = "chevron.down"
    case chevronUp = "chevron.up"
    case pencil
    case lock = "lock.fill"
    case globe
    case search = "magnifyingglass"
    case warning = "exclamationmark.triangle"
    case history = "clock.arrow.circlepath"
    case lightbulb
    case fileText = "doc.text"
    case translate
    case message = "bubble.left"
    case bot = "bubble.left.and.text.bubble.right"
    case library = "books.vertical"
    case layout = "rectangle.split.3x1"
    case book
    case terminal
    case maximize = "arrow.up.left.and.arrow.down.right"
    case command
    case returnKey = "return"
    case compose = "square.and.pencil"
    case list = "list.bullet"
    case columns = "rectangle.split.2x1"
    case paperclip
    case stop = "stop.fill"
    case arrowUp = "arrow.up"
    case checkCircle = "checkmark.circle"
    case sliders = "slider.horizontal.3"
    case shield
    case keyboard
    case media = "photo.on.rectangle"
    case notes = "note.text"
    case layers = "square.3.layers.3d"
    case calendar
    case archive = "archivebox"
    case clipboard = "list.clipboard"
    case at
    case inbox = "tray"
    case photo
    case film
    case share = "square.and.arrow.up"
    case printer
    case textMagnify = "text.magnifyingglass"
    case info = "info.circle"
    case squareStack = "square.on.square"

    func image(_ size: CGFloat = 14, weight: UIImage.SymbolWeight = .medium) -> UIImage? {
        UIImage(systemName: rawValue, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: weight))
    }
}
