import Foundation

/// The live state of a tab's page.
struct PageState: Equatable {
    var url: String
    var title: String
    var favicon: String?
    var themeColor: String?
    var loading = false
    /// The load took too long or failed.
    var stalled = false
    var canGoBack = false
    var canGoForward = false
    var secure = false
    var zoom: Double = 1
    /// Selected text, when there is any.
    var selection: String?
}
