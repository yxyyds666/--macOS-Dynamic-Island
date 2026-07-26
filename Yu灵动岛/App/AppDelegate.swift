import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Shared state

    var appState: AppState?
    var menuBarManager: MenuBarManager?
    var mediaService: (any MediaServiceProtocol)?

    // MARK: - Per-screen state

    /// One entry per active screen. Key = screen's display-id string.
    private var screenControllers: [String: ScreenController] = [:]

    private var cancellables = Set<AnyCancellable>()
    private var lyricRequestGeneration = 0
    private var lyricFetchTask: Task<Void, Never>?
    private var pendingLyricIdentity: String?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsManager.shared.registerDefaults()

        // Require a notch screen only when multi-screen is off.
        let showAll = SettingsManager.shared.showOnAllDisplays
        if !showAll, NotchDetector.builtInNotchScreen == nil {
            NSApp.terminate(nil)
            return
        }

        let state = AppState()
        self.appState = state

        let media = AdapterMediaService()
        self.mediaService = media
        state.mediaService = media
        media.startListening()
        state.startProgressTimer()
        state.syncVolumeFromSystem()

        setupMediaBindings(media, state: state)

        cancellables.insert(
            NotificationCenter.default.publisher(for: .lyricsRetryRequested)
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak state] _ in
                    guard let self, let state else { return }
                    self.fetchLyrics(
                        for: NowPlayingInfo(
                            title: state.songTitle, artist: state.artistName,
                            album: state.albumName, artwork: state.albumArt,
                            duration: state.duration, elapsedTime: state.currentTime,
                            isPlaying: state.isPlaying
                        ),
                        into: state, forceRefresh: true)
                }
        )

        let menuManager = MenuBarManager(appState: state)
        menuManager.setup()
        self.menuBarManager = menuManager

        // Respond to settings changes (show-on-all-displays may toggle).
        NotificationCenter.default.addObserver(
            forName: .settingsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcileScreenControllers() }
        }

        // Respond to display hot-plug / arrangement.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcileScreenControllers() }
        }

        buildScreenControllers(state: state, menuManager: menuManager)
    }

    // MARK: - Screen management

    /// Returns the screens that should currently show an island.
    private func targetScreens() -> [NSScreen] {
        if SettingsManager.shared.showOnAllDisplays {
            return NSScreen.screens
        } else {
            return NotchDetector.builtInNotchScreen.map { [$0] } ?? []
        }
    }

    private func displayKey(for screen: NSScreen) -> String {
        let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return num?.stringValue ?? screen.localizedName
    }

    /// Build a controller for each target screen, close any that are no
    /// longer in scope, and wire the primary island into MenuBarManager.
    private func buildScreenControllers(state: AppState, menuManager: MenuBarManager) {
        let targets = targetScreens()
        for screen in targets {
            let key = displayKey(for: screen)
            if screenControllers[key] == nil {
                let ctrl = ScreenController(screen: screen, appState: state)
                screenControllers[key] = ctrl
                setupIslandObserver(island: ctrl.island, window: ctrl.window)
            }
        }
        // Wire the built-in island (or first available) to the menu bar.
        let primary = screenControllers[
            NotchDetector.builtInNotchScreen.map { displayKey(for: $0) } ?? ""
        ] ?? screenControllers.values.first
        menuManager.primaryIsland = primary?.island
    }

    /// Called when settings or screen parameters change: add/remove controllers.
    private func reconcileScreenControllers() {
        guard let state = appState, let menuBarManager else { return }

        let targets = targetScreens()
        let targetKeys = Set(targets.map { displayKey(for: $0) })
        let existingKeys = Set(screenControllers.keys)

        // Close controllers whose screen is no longer a target.
        for key in existingKeys.subtracting(targetKeys) {
            screenControllers[key]?.window.close()
            screenControllers.removeValue(forKey: key)
        }

        // Create controllers for new target screens.
        for screen in targets where !existingKeys.contains(displayKey(for: screen)) {
            let key = displayKey(for: screen)
            let ctrl = ScreenController(screen: screen, appState: state)
            screenControllers[key] = ctrl
            setupIslandObserver(island: ctrl.island, window: ctrl.window)
        }

        // Relocate existing windows (screen may have moved).
        for ctrl in screenControllers.values { ctrl.window.relocate() }

        // Re-wire primary island.
        let primaryKey = NotchDetector.builtInNotchScreen.map { displayKey(for: $0) } ?? ""
        menuBarManager.primaryIsland = (screenControllers[primaryKey] ?? screenControllers.values.first)?.island
    }

    // MARK: - Island observer

    private func setupIslandObserver(island: IslandState, window: NotchWindow) {
        window.animate(to: island.islandMode)
        withObservationTracking {
            _ = island.islandMode
        } onChange: { [weak self, weak island, weak window] in
            Task { @MainActor in
                guard let self, let island, let window else { return }
                window.animate(to: island.islandMode)
                self.setupIslandObserver(island: island, window: window)
            }
        }
    }

    // MARK: - Media bindings

    private func setupMediaBindings(_ media: any MediaServiceProtocol, state: AppState) {
        cancellables.insert(
            media.nowPlayingPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak state] info in
                    guard let state else { return }
                    let prevId = self?.lyricIdentity(title: state.songTitle, artist: state.artistName, album: state.albumName)
                    let newId  = self?.lyricIdentity(for: info)
                    let changed   = newId != prevId
                    let hadTrack  = !state.songTitle.isEmpty

                    state.songTitle = info.title
                    state.artistName = info.artist
                    state.albumName  = info.album
                    state.albumArt   = info.artwork
                    state.currentTime = info.elapsedTime
                    state.duration    = info.duration
                    state.isPlaying   = info.isPlaying
                    self?.menuBarManager?.updateIcon()

                    if info.title.isEmpty {
                        self?.cancelLyricFetch()
                        self?.pendingLyricIdentity = nil
                        state.resetLyrics()
                    } else if changed {
                        self?.cancelLyricFetch()
                        state.resetLyrics()
                        self?.pendingLyricIdentity = nil
                        if info.duration > 0 {
                            self?.fetchLyrics(for: info, into: state)
                        } else {
                            state.setLyricsLoading()
                            self?.pendingLyricIdentity = newId
                        }
                        // Pop track-change capsule on every island that is idle.
                        if hadTrack {
                            self?.screenControllers.values.forEach { $0.island.trackDidChange() }
                        }
                    } else if state.lyricsState == .loading,
                              self?.pendingLyricIdentity == newId,
                              info.duration > 0 {
                        self?.pendingLyricIdentity = nil
                        self?.fetchLyrics(for: info, into: state)
                    }
                    state.updateCurrentLyric(at: info.elapsedTime)
                }
        )
    }

    // MARK: - Lyrics

    private func lyricIdentity(for info: NowPlayingInfo) -> String {
        lyricIdentity(title: info.title, artist: info.artist, album: info.album)
    }
    private func lyricIdentity(title: String, artist: String, album: String) -> String {
        "\(title)|\(artist)|\(album)"
    }
    private func cancelLyricFetch() {
        lyricRequestGeneration += 1
        lyricFetchTask?.cancel()
        lyricFetchTask = nil
    }
    private func fetchLyrics(for info: NowPlayingInfo, into state: AppState, forceRefresh: Bool = false) {
        cancelLyricFetch()
        let generation = lyricRequestGeneration
        state.setLyricsLoading()
        lyricFetchTask = Task { [weak self, weak state] in
            let result = await LyricsService.shared.fetch(
                title: info.title, artist: info.artist, album: info.album,
                duration: info.duration, forceRefresh: forceRefresh)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, let state,
                      self.lyricRequestGeneration == generation,
                      self.lyricIdentity(title: state.songTitle, artist: state.artistName, album: state.albumName)
                      == self.lyricIdentity(for: info) else { return }
                self.lyricFetchTask = nil
                state.applyLyricsResult(result)
            }
        }
    }

    // MARK: - Terminate

    func applicationWillTerminate(_ notification: Notification) {
        cancelLyricFetch()
        mediaService?.stopListening()
        appState?.stopProgressTimer()
    }
}

// MARK: - Per-screen controller

/// Bundles an island state + window + drag service for one screen.
@MainActor
private final class ScreenController {
    let island: IslandState
    let window: NotchWindow
    private let dragService: DragDropService

    init(screen: NSScreen, appState: AppState) {
        let island = IslandState(screen: screen, appState: appState)
        self.island = island
        self.window = NotchWindow(island: island, appState: appState)
        self.dragService = DragDropService(island: island, appState: appState)

        if let cv = window.contentView {
            let dv = dragService.makeDraggingView()
            dv.frame = cv.bounds
            dv.autoresizingMask = [.width, .height]
            cv.addSubview(dv)
        }
    }
}
