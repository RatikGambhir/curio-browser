import QuickLook
import UIKit

/// How a download row looks: a status icon, the file name and status.
enum DownloadRowStyle {
    static func configure(_ cell: PageRowCell, record: DownloadRecord) {
        let theme = ThemeCenter.shared.theme
        let (icon, color, status): (Icon, UIColor, String) = switch record.state {
        case .completed: (.checkCircle, theme.success.uiColor, "Completed")
        case .failed: (.xCircle, theme.danger.uiColor, "Failed")
        case .inProgress: (.download, theme.accent.uiColor, "Downloading…")
        }
        cell.configure(title: record.displayName, subtitle: "\(status) · \(Curio.displayHost(record.url))",
                       faviconLabel: record.displayName, favicon: nil, icon: icon, iconColor: color)
    }
}
