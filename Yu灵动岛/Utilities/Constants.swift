import Foundation

enum AppConstants {
    static let appName = "Yu灵动岛"
    static let bundleIdentifier = "com.yuxi.yulingdongdao"

    // Physical notch dimensions, measured from this MacBook via the screen's
    // auxiliary top areas (see NSScreen.notchWidth/notchHeight, which override
    // these at runtime when a screen is available).
    static let notchWidth: CGFloat = 220
    static let notchHeight: CGFloat = 38
    static let notchCornerRadius: CGFloat = 18

    // Hover state: a subtle bulge around the notch (visual only, no content).
    static let islandHoverWidth: CGFloat = 300
    static let islandHoverHeight: CGFloat = 52

    // Peek state: dwell ~1s and the music player drapes straight down. Same
    // width as hover so the reveal is purely vertical.
    static let islandPeekWidth: CGFloat = 300
    static let islandPeekHeight: CGFloat = 250
    static let islandCornerRadius: CGFloat = 24

    // Concave top-corner radius that makes the shape hug the notch shoulders.
    static let islandTopCornerRadius: CGFloat = 12

    // Expanded panel: a wide bar that wraps AROUND the notch — music on the
    // left, files on the right, the physical notch showing through the middle.
    static let expandSidePanelWidth: CGFloat = 320
    static var expandPanelWidth: CGFloat { notchWidth + 2 * expandSidePanelWidth }
    static let expandPanelHeight: CGFloat = 250
    static let expandPanelCornerRadius: CGFloat = 24
    // Rounded inner corners of the notch cutout in the expanded bar.
    static let notchCutoutCornerRadius: CGFloat = 10
    // Time the mouse must dwell over the notch before the peek appears.
    static let peekDwellSeconds: TimeInterval = 1.0

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

/// The four visual states of the island:
///   • idle     — collapsed into the notch (a black pill)
///   • hover    — mouse over the notch: a subtle bulge, no content
///   • peek     — dwelled ~1s: music player drapes straight down
///   • expanded — clicked: a wide bar wrapping AROUND the notch (music left,
///                files right, the physical notch showing through the middle)
enum IslandMode {
    case idle
    case hover
    case peek
    case expanded

    var size: CGSize {
        switch self {
        case .idle:
            return CGSize(width: AppConstants.notchWidth, height: AppConstants.notchHeight)
        case .hover:
            return CGSize(width: AppConstants.islandHoverWidth, height: AppConstants.islandHoverHeight)
        case .peek:
            return CGSize(width: AppConstants.islandPeekWidth, height: AppConstants.islandPeekHeight)
        case .expanded:
            return CGSize(width: AppConstants.expandPanelWidth, height: AppConstants.expandPanelHeight)
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .idle: return AppConstants.notchCornerRadius
        case .hover: return AppConstants.islandCornerRadius
        case .peek: return AppConstants.islandCornerRadius
        case .expanded: return AppConstants.expandPanelCornerRadius
        }
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
