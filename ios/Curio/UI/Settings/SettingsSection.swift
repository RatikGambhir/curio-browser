import Foundation

/// Settings sections.
enum SettingsSection: CaseIterable {
    case general, appearance, ai, privacy, shortcuts

    var label: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .ai: "AI Assistant"
        case .privacy: "Privacy"
        case .shortcuts: "Shortcuts"
        }
    }

    var icon: Icon {
        switch self {
        case .general: .sliders
        case .appearance: .palette
        case .ai: .sparkles
        case .privacy: .shield
        case .shortcuts: .keyboard
        }
    }
}
