import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var notchWindow: NotchWindow?
    var menuBarManager: MenuBarManager?
    var mediaService: (any MediaServiceProtocol)?
    var dragDropService: DragDropService?
    var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var lyricRequestGeneration = 0
    private var lyricFetchTask: Task<Void, Never>?
    private var pendingLyricIdentity: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check for notch
        guard NotchDetector.builtInNotchScreen != nil else {
            print("This app requires a built-in MacBook Pro display with notch")
            NSApp.terminate(nil)
            return
        }

        // Register default preferences before any state reads them.
        SettingsManager.shared.registerDefaults()

        // Initialize state
        let state = AppState()
        self.appState = state

        // Setup services. AdapterMediaService reaches now-playing through the
        // entitled system perl binary, which still works on macOS 15.4+.
        let media = AdapterMediaService()
        self.mediaService = media
        state.mediaService = media
        media.startListening()
        state.startProgressTimer()
        // Reflect the real system output volume on the slider at launch.
        state.syncVolumeFromSystem()

        // Bind media to state
        setupMediaBindings(media, state: state)
        cancellables.insert(
            NotificationCenter.default.publisher(for: .lyricsRetryRequested)
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak state] _ in
                    guard let self, let state else { return }
                    self.fetchLyrics(
                        for: NowPlayingInfo(
                            title: state.songTitle,
                            artist: state.artistName,
                            album: state.albumName,
                            artwork: state.albumArt,
                            duration: state.duration,
                            elapsedTime: state.currentTime,
                            isPlaying: state.isPlaying
                        ),
                        into: state,
                        forceRefresh: true
                    )
                }
        )

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.notchWindow?.relocateToBuiltInDisplay()
            }
        }

        let dragService = DragDropService(appState: state)
        self.dragDropService = dragService

        // Create the island window (handles idle/hover/expanded itself).
        let notchWin = NotchWindow(appState: state)
        self.notchWindow = notchWin

        // Setup menu bar
        let menuManager = MenuBarManager(appState: state)
        menuManager.setup()
        self.menuBarManager = menuManager

        // Drive the window's frame from the island's visual mode.
        setupIslandObserver(state)

        // Install the drag-receiving overlay over the notch window content.
        if let contentView = notchWin.contentView {
            let dragView = dragService.makeDraggingView()
            dragView.frame = contentView.bounds
            dragView.autoresizingMask = [.width, .height]
            contentView.addSubview(dragView)
        }
    }

    private func setupMediaBindings(_ media: any MediaServiceProtocol, state: AppState) {
        cancellables.insert(
            media.nowPlayingPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak state] info in
                    guard let state else { return }
                    // Detect a track change by identity (title + artist) so we
                    // can pop the info capsule and refresh lyrics exactly once.
                    let previousIdentity = self?.lyricIdentity(
                        title: state.songTitle,
                        artist: state.artistName,
                        album: state.albumName
                    )
                    let identity = self?.lyricIdentity(for: info)
                    let changed = identity != previousIdentity
                    let hadTrack = !state.songTitle.isEmpty

                    state.songTitle = info.title
                    state.artistName = info.artist
                    state.albumName = info.album
                    state.albumArt = info.artwork
                    state.currentTime = info.elapsedTime
                    state.duration = info.duration
                    state.isPlaying = info.isPlaying
                    self?.menuBarManager?.updateIcon()

                    if info.title.isEmpty {
                        self?.cancelLyricFetch()
                        self?.pendingLyricIdentity = nil
                        state.resetLyrics()
                    } else if changed {
                        self?.cancelLyricFetch()
                        // New song: clear stale lyrics and start loading only when
                        // enough metadata is available for a useful lookup.
                        state.resetLyrics()
                        self?.pendingLyricIdentity = nil
                        if info.duration > 0 {
                            self?.fetchLyrics(for: info, into: state)
                        } else {
                            state.setLyricsLoading()
                            self?.pendingLyricIdentity = identity
                        }
                        if hadTrack { state.trackDidChange() }
                    } else if state.lyricsState == .loading,
                              self?.pendingLyricIdentity == identity,
                              info.duration > 0 {
                        self?.pendingLyricIdentity = nil
                        self?.fetchLyrics(for: info, into: state)
                    }
                    // Keep the highlighted lyric in step with the media update.
                    state.updateCurrentLyric(at: info.elapsedTime)
                }
        )
    }

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

    /// Applies fetched lyrics only if the track has not changed while they arrive.
    private func fetchLyrics(for info: NowPlayingInfo, into state: AppState, forceRefresh: Bool = false) {
        cancelLyricFetch()
        let generation = lyricRequestGeneration
        state.setLyricsLoading()
        lyricFetchTask = Task { [weak self, weak state] in
            let result = await LyricsService.shared.fetch(
                title: info.title,
                artist: info.artist,
                album: info.album,
                duration: info.duration,
                forceRefresh: forceRefresh
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, let state,
                      self.lyricRequestGeneration == generation,
                      self.lyricIdentity(
                        title: state.songTitle,
                        artist: state.artistName,
                        album: state.albumName
                      ) == self.lyricIdentity(for: info) else { return }
                self.lyricFetchTask = nil
                state.applyLyricsResult(result)
            }
        }
    }

    /// Reacts to island-mode changes via the Observation framework instead of
    /// polling. `withObservationTracking` fires once per change, so we re-arm it
    /// after each callback to keep listening.
    private func setupIslandObserver(_ state: AppState) {
        notchWindow?.animate(to: state.islandMode)
        withObservationTracking {
            _ = state.islandMode
        } onChange: { [weak self, weak state] in
            // onChange fires just before the value updates; hop to the main actor
            // so we read the new value and re-subscribe.
            Task { @MainActor in
                guard let self, let state else { return }
                self.notchWindow?.animate(to: state.islandMode)
                self.setupIslandObserver(state)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cancelLyricFetch()
        mediaService?.stopListening()
        appState?.stopProgressTimer()
    }
}
