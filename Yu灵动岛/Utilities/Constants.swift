import Foundation

enum AppConstants {
    static let appName = "Yu灵动岛"
    static let bundleIdentifier = "com.yuxi.yulingdongdao"

    // Notch dimensions (macOS 26+ MacBook Pro)
    static let notchWidth: CGFloat = 124
    static let notchHeight: CGFloat = 37
    static let notchCornerRadius: CGFloat = 18

    // Expand panel dimensions
    static let expandPanelWidth: CGFloat = 360
    static let expandPanelHeight: CGFloat = 480
    static let expandPanelCornerRadius: CGFloat = 16

    // File transfer limits
    static let maxFileItems = 10

    // Animation durations
    static let expandDuration: TimeInterval = 0.35
    static let moduleSwitchDuration: TimeInterval = 0.25

    // UserDefaults keys
    enum DefaultsKeys {
        static let launchAtLogin = "launchAtLogin"
        static let showMusicModule = "showMusicModule"
        static let showFileModule = "showFileModule"
        static let defaultModule = "defaultModule"
        static let animationSpeed = "animationSpeed"
    }
}

enum NotchModule: String, CaseIterable {
    case music = "music"
    case file = "file"

    var displayName: String {
        switch self {
        case .music: return "音乐控制"
        case .file: return "文件中转站"
        }
    }

    var sfSymbol: String {
        switch self {
        case .music: return "music.note"
        case .file: return "folder"
        }
    }
}
