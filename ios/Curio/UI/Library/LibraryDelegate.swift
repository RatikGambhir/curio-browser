import Foundation

/// Library requests the browser handles.
protocol LibraryDelegate: AnyObject {
    func libraryDidClose()
    func libraryPreview(_ url: URL)
}
