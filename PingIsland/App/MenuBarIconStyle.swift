import AppKit

// The menu bar status item icon, user-switchable in Settings. Each case maps to a
// template imageset in Assets.xcassets (monochrome vector, system-tinted). Raw values
// are persisted in AppSettings, so keep them stable.
enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case notchDots
    case notchDotsHollow
    case codeSpark
    case commandBubble
    case cursorSpark

    static let `default`: MenuBarIconStyle = .notchDots

    var id: String { rawValue }

    private var assetName: String {
        switch self {
        case .notchDots: return "MenuBarNotchDots"
        case .notchDotsHollow: return "MenuBarNotchDotsHollow"
        case .codeSpark: return "MenuBarCodeSpark"
        case .commandBubble: return "MenuBarCommandBubble"
        case .cursorSpark: return "MenuBarCursorSpark"
        }
    }

    /// Localization key (Simplified identifier); resolved to a Traditional value at the UI boundary.
    var titleKey: String {
        switch self {
        case .notchDots: return "刘海胶囊三点"
        case .notchDotsHollow: return "实心岛三点镂空"
        case .codeSpark: return "代码火花"
        case .commandBubble: return "指令气泡"
        case .cursorSpark: return "光标火花"
        }
    }

    /// A template NSImage sized for the menu bar. Copies the cached asset so per-call size /
    /// isTemplate tweaks never mutate the shared instance. Falls back to an SF Symbol if the
    /// asset is missing.
    @MainActor
    func templateImage(pointSize: CGFloat = 18) -> NSImage {
        let base = NSImage(named: assetName)
            ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Ping Island")
            ?? NSImage()
        let image = (base.copy() as? NSImage) ?? base
        image.isTemplate = true
        image.size = NSSize(width: pointSize, height: pointSize)
        return image
    }
}
