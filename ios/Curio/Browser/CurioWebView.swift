import UIKit
import WebKit

/// A web view that adds Curio's assistant actions to the text selection menu.
final class CurioWebView: WKWebView {
    /// Called with an action (or `nil` for "Ask…") on the current selection.
    var onAskAboutSelection: ((QuickAction?) -> Void)?

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard onAskAboutSelection != nil else { return }
        let item = { (title: String, symbol: String, action: QuickAction?) in
            UIAction(title: title, image: UIImage(systemName: symbol)) { [weak self] _ in
                self?.onAskAboutSelection?(action)
            }
        }
        let menu = UIMenu(title: "Ask Curio", image: UIImage(systemName: "sparkles"), children: [
            item("Explain", "lightbulb", .explainSelection),
            item("Summarize", "doc.text", .summarizeSelection),
            item("Translate", "translate", .translateSelection(language: "")),
            item("Ask…", "bubble.left", nil),
        ])
        builder.insertSibling(menu, afterMenu: .standardEdit)
    }
}
