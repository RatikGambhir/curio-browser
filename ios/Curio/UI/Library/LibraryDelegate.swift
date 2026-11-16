import Foundation

/// Library requests the browser handles.
protocol LibraryDelegate: AnyObject {
    func libraryDidClose()
    func librarySheetDidSelect(_ section: LibrarySection)
    func libraryPreview(_ url: URL, retaining export: MediaExport?)
}

extension LibraryDelegate {
    func libraryPreview(_ url: URL) {
        libraryPreview(url, retaining: nil)
    }
}
