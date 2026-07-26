import Foundation

extension Notification.Name {
    static let lyricsRetryRequested = Notification.Name("com.yuxi.yulingdongdao.lyricsRetryRequested")
    /// Posted from the expanded island's tab bar to ask the menu-bar controller
    /// to open the Settings window (the island can't own that window itself).
    static let openSettingsRequested = Notification.Name("com.yuxi.yulingdongdao.openSettingsRequested")
}

enum AppConstants {
    static let appName = "岛一下"
    static let bundleIdentifier = "com.yuxi.yulingdongdao"

    // Physical notch dimensions, measured from this MacBook via the screen's
    // auxiliary top areas (see NSScreen.notchWidth/notchHeight, which override
    // these at runtime when a screen is available).
    static let notchWidth: CGFloat = 220
    static let notchHeight: CGFloat = 38
    static let notchCornerRadius: CGFloat = 18

    // Collapsed playback state: narrow wings animate beside the physical notch
    // without growing downward into the peek panel.
    static let islandPlayingWingWidth: CGFloat = 44
    static var islandPlayingWidth: CGFloat { notchWidth + 2 * islandPlayingWingWidth }
    static let islandPlayingHeight: CGFloat = notchHeight

    // Hover state: a shallow wrap that grows around the physical notch.
    static let islandHoverWingWidth: CGFloat = 72
    static let islandHoverHeightExtra: CGFloat = 14

    // Peek state: a wider drape whose chin is tall enough to clear the physical
    // notch AND fully show the artwork + track info + scrubber + controls below
    // it (content starts at ~notchHeight+10, so the chin must exceed that plus
    // the music panel's own height or the bottom gets clipped by the shape).
    static let islandPeekWingWidth: CGFloat = 112
    static let islandPeekHeight: CGFloat = 232
    static let islandCornerRadius: CGFloat = 24

    // Activity state: a horizontal live-activity capsule wrapping AROUND the
    // notch — album art in the left wing, lyrics or track info in the right
    // wing, the physical notch showing through the middle. Shown on hover while
    // playing (lyrics) or briefly on a track change (info).
    static let islandActivityWingWidth: CGFloat = 172
    static var islandActivityWidth: CGFloat { notchWidth + 2 * islandActivityWingWidth }
    static let islandActivityHeight: CGFloat = 56
    // How long the auto-popped track-change capsule lingers before collapsing.
    static let activityAutoDismissSeconds: TimeInterval = 3

    // Expanded panel: a wide bar that wraps AROUND the notch — music on the
    // left, files on the right, the physical notch showing through the middle.
    static let expandSidePanelWidth: CGFloat = 320
    static var expandPanelWidth: CGFloat { notchWidth + 2 * expandSidePanelWidth }
    static let expandPanelHeight: CGFloat = 340
    static let expandPanelCornerRadius: CGFloat = 24
    // Rounded inner corners of the notch cutout in the expanded bar.
    static let notchCutoutCornerRadius: CGFloat = 10

    // Fixed-window architecture (boring.notch style): the window is created ONCE
    // at the largest extent any state can reach and never resizes. All state size
    // changes happen inside SwiftUI (.frame + spring), which the GPU composites —
    // no per-frame window resize, no drift/judder, no diagonal "gap".
    //
    // The largest state is `expanded`. Shadow padding leaves room on the sides and
    // bottom so the SwiftUI drop shadow isn't clipped by the window edge. The top
    // stays flush with the screen (the island grows downward only).
    static let islandShadowPadding: CGFloat = 24
    static var fixedWindowWidth: CGFloat { expandPanelWidth + 2 * islandShadowPadding }
    static var fixedWindowHeight: CGFloat { expandPanelHeight + islandShadowPadding }

    // Collapsed playback (playing, mouse not over): album art + spectrum bars in
    // the wings, boring.notch style.
    static let playingArtworkSize: CGFloat = 22

    // File transfer limits
    static let maxFileItems = 10

    // UserDefaults keys
    enum DefaultsKeys {
        static let showMusicModule = "showMusicModule"
        static let showFileModule = "showFileModule"
        static let defaultModule = "defaultModule"
        static let animationSpeed = "animationSpeed"
        static let hoverToReveal = "hoverToReveal"
        static let hoverDelay = "hoverDelay"
        static let artworkBreathing = "artworkBreathing"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let showOnAllDisplays = "showOnAllDisplays"
        static let lyricsFontScale = "lyricsFontScale"
    }
}

/// The visual states of the island:
///   • idle     — collapsed into the notch (a black pill)
///   • playing  — idle while music plays: album art + spectrum bars in the wings
///   • hover    — mouse over the notch: a subtle bulge, no content
///   • activity — horizontal capsule wrapping the notch (lyrics or track info)
///   • peek     — clicked once: music/file panel drapes straight down
///   • expanded — clicked again: a wide bar wrapping AROUND the notch (music
///                left, files right, the physical notch showing through)
enum IslandMode {
    case idle
    case playing
    case hover
    case activity
    case peek
    case expanded

    func size(notchSize: CGSize) -> CGSize {
        switch self {
        case .idle:
            return notchSize
        case .playing:
            return CGSize(
                width: notchSize.width + 2 * AppConstants.islandPlayingWingWidth,
                height: notchSize.height
            )
        case .hover:
            return CGSize(
                width: notchSize.width + 2 * AppConstants.islandHoverWingWidth,
                height: notchSize.height + AppConstants.islandHoverHeightExtra
            )
        case .activity:
            return CGSize(
                width: notchSize.width + 2 * AppConstants.islandActivityWingWidth,
                height: AppConstants.islandActivityHeight
            )
        case .peek:
            return CGSize(
                width: notchSize.width + 2 * AppConstants.islandPeekWingWidth,
                height: AppConstants.islandPeekHeight
            )
        case .expanded:
            return CGSize(
                width: notchSize.width + 2 * AppConstants.expandSidePanelWidth,
                height: AppConstants.expandPanelHeight
            )
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .idle: return AppConstants.notchCornerRadius
        case .playing: return AppConstants.notchCornerRadius
        case .hover: return AppConstants.islandCornerRadius
        case .activity: return AppConstants.islandCornerRadius
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
