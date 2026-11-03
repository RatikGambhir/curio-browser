import Foundation

/// The active page's navigation and address state.
struct PageNav: Equatable {
    var canGoBack = false
    var canGoForward = false
    var loading = false
    var secure = false
    var zoom: Double = 1
    /// The address and title, or `nil` on the new tab page.
    var page: PageInfo?

    struct PageInfo: Equatable {
        var url: String
        var host: String
        var title: String
    }

    /// The icon before the address: search, a lock or a globe.
    var addressIcon: Icon {
        guard page != nil else { return .search }
        return secure ? .lock : .globe
    }

    /// "125%" when zoomed, otherwise `nil`.
    var zoomLabel: String? {
        abs(zoom - 1) > 0.01 ? "\(Int((zoom * 100).rounded()))%" : nil
    }
}
