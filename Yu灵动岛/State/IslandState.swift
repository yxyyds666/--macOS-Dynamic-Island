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

    /// The screen this island lives on. NSScreen instances are snapshots —
    /// after display reconfiguration the old object may carry stale geometry,
    /// so the app delegate re-resolves and swaps it in via `updateScreen`.
    private(set) var screen: NSScreen

    /// The reveal state for this screen's island.
    var revealState: RevealState = .idle

    /// The notch size for this screen (real on notched screens, simulated on
    /// external displays).
    var notchSize: CGSize

    /// Whether a file drag is targeting this island specifically.
    var isDragTarget: Bool = false

    /// Right-clicking the hover capsule pins the island: mouse-exit no longer
    /// collapses it until unpinned (another right-click) or the reveal state
    /// moves on (click-through to peek/expanded, explicit collapse).
    var isPinned: Bool = false

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
        guard !isPinned else { return }
        collapse()
    }

    /// Whether right-click may pin right now: only while the hover capsule is
    /// showing AND a track is playing. Pinning an empty capsule would leave a
    /// blank island stuck on screen with no content to read.
    var canPin: Bool {
        switch revealState {
        case .activity, .hover:
            return appState.isPlaying && !appState.songTitle.isEmpty
        default:
            return false
        }
    }

    /// Toggle the hover-capsule pin (right-click). Unpinning is always allowed
    /// so playback stopping while pinned can never trap the island.
    func togglePinned() {
        if isPinned {
            isPinned = false
            return
        }
        guard canPin else { return }
        isPinned = true
        // A pinned track-info capsule must not auto-dismiss from under the pin.
        cancelActivityAutoDismiss()
    }

    /// Playback stopped: drop the pin. Collapse too, unless the cursor is still
    /// on the island — a pin that outlives playback would strand it on screen.
    func releasePinIfNeeded() {
        guard isPinned else { return }
        isPinned = false
        guard !islandRectOnScreen.contains(NSEvent.mouseLocation) else { return }
        collapse()
    }

    /// The island's current bounds in screen coordinates: centered horizontally
    /// on the screen, grown downward from its top edge.
    private var islandRectOnScreen: NSRect {
        let size = islandMode.size(notchSize: notchSize)
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    func advanceReveal() {
        cancelActivityAutoDismiss()
        isPinned = false
        switch revealState {
        case .peek:     revealState = .expanded
        case .expanded: break
        default:        revealState = .peek
        }
    }

    /// Reveal the peek panel directly (menu-bar module shortcuts). Leaves an
    /// already-expanded island expanded so a shortcut only switches the tab.
    /// Goes through the state machine so the pin and auto-dismiss timer are
    /// cleared rather than bypassed.
    func revealPeek() {
        guard revealState != .expanded else { return }
        cancelActivityAutoDismiss()
        isPinned = false
        revealState = .peek
    }

    func collapse() {
        revealState = .idle
        isPinned = false
        isDragTarget = false
        cancelActivityAutoDismiss()
    }

    func expand() {
        cancelActivityAutoDismiss()
        isPinned = false
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
                guard let self, !self.isPinned else { return }
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

    /// Swap in the freshly resolved NSScreen for this display (call on display
    /// reconfiguration, before recomputing window geometry from it).
    func updateScreen(_ newScreen: NSScreen) {
        screen = newScreen
        updateNotchSize()
    }

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
