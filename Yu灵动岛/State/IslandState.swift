import AppKit
import Foundation

// MARK: - Shared enums (used by IslandState and AppState)

/// Per-screen reveal state. Each screen's island has its own copy so hovering
/// or clicking one screen never affects another.
enum RevealState: Equatable {
    case idle
    case hover
    case activity(ActivityContent)
    case peek
    case expanded
}

/// What the horizontal activity capsule is showing on a given screen.
enum ActivityContent: Equatable { case lyrics, trackInfo }

// MARK: - Per-screen island state

/// Owns the interaction state for ONE screen's island. Every screen gets its
/// own `IslandState` so hover/click on screen A never affects screen B.
///
/// Content (music, lyrics, files, settings) lives in the shared `AppState`.
@MainActor
@Observable
final class IslandState {
    // MARK: Properties

    /// The screen this island lives on.
    let screen: NSScreen

    /// The reveal state for this screen's island.
    var revealState: RevealState = .idle

    /// The notch size for this screen (real on notched screens, simulated on
    /// external displays).
    var notchSize: CGSize

    /// Whether a file drag is targeting this island specifically.
    var isDragTarget: Bool = false

    /// Weak ref to shared content so interaction methods can read music/lyrics.
    private unowned let appState: AppState

    @ObservationIgnored private var activityDismissTimer: Timer?

    // MARK: Init

    init(screen: NSScreen, appState: AppState) {
        self.screen = screen
        self.appState = appState
        self.notchSize = IslandState.computeNotchSize(for: screen)
    }

    // MARK: Computed

    /// The visual mode derived from this screen's reveal state and the shared
    /// music state.
    var islandMode: IslandMode {
        switch revealState {
        case .idle:
            return appState.isPlaying && !appState.songTitle.isEmpty ? .playing : .idle
        case .hover:     return .hover
        case .activity:  return .activity
        case .peek:      return .peek
        case .expanded:  return .expanded
        }
    }

    var activityContent: ActivityContent? {
        if case .activity(let c) = revealState { return c }
        return nil
    }

    // MARK: Interaction

    func mouseEnteredNotch() {
        cancelActivityAutoDismiss()
        guard appState.hoverToReveal else { return }
        guard revealState != .peek, revealState != .expanded else { return }
        if appState.currentModule == .music,
           appState.showMusicModule,
           appState.isPlaying,
           !appState.songTitle.isEmpty {
            revealState = .activity(.lyrics)
        } else {
            revealState = .hover
        }
    }

    func mouseExitedNotch() {
        collapse()
    }

    func advanceReveal() {
        cancelActivityAutoDismiss()
        switch revealState {
        case .peek:     revealState = .expanded
        case .expanded: break
        default:        revealState = .peek
        }
    }

    func collapse() {
        revealState = .idle
        isDragTarget = false
        cancelActivityAutoDismiss()
    }

    func expand() {
        cancelActivityAutoDismiss()
        revealState = .expanded
    }

    /// Called when the now-playing track changes. Shows the track-info capsule
    /// if the island is idle, then auto-dismisses after a few seconds.
    func trackDidChange() {
        guard revealState == .idle else { return }
        revealState = .activity(.trackInfo)
        scheduleActivityAutoDismiss()
    }

    private func scheduleActivityAutoDismiss() {
        cancelActivityAutoDismiss()
        activityDismissTimer = Timer.scheduledTimer(
            withTimeInterval: AppConstants.activityAutoDismissSeconds,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .activity(.trackInfo) = self.revealState {
                    self.revealState = .idle
                }
            }
        }
    }

    private func cancelActivityAutoDismiss() {
        activityDismissTimer?.invalidate()
        activityDismissTimer = nil
    }

    // MARK: Drag support

    /// A file drag arrived. Returns false to reject when file station is disabled
    /// or full so AppKit can skip the drop.
    @discardableResult
    func beginFileDrag() -> Bool {
        guard appState.showFileModule else {
            appState.showFileDropFeedback("文件中转站已关闭", isError: true)
            return false
        }
        guard appState.remainingFileSlots > 0 else {
            appState.showFileDropFeedback("文件中转站已满", isError: true)
            return false
        }
        isDragTarget = true
        appState.currentModule = .file
        revealState = .expanded
        cancelActivityAutoDismiss()
        return true
    }

    func dragEnteredNotch() { _ = beginFileDrag() }

    func dragExitedNotch() {
        isDragTarget = false
        collapse()
    }

    // MARK: Notch size

    func updateNotchSize() {
        notchSize = IslandState.computeNotchSize(for: screen)
    }

    private static func computeNotchSize(for screen: NSScreen) -> CGSize {
        if screen.hasNotch {
            return CGSize(width: screen.notchWidth, height: screen.notchHeight)
        }
        // External or non-notch screen: simulate a pill matching the built-in
        // notch dimensions so the island has a consistent anchor.
        return CGSize(width: AppConstants.notchWidth, height: AppConstants.notchHeight)
    }
}
