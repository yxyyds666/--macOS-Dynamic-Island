import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    var notchWindow: NotchWindow?
    var menuBarManager: MenuBarManager?
    var mediaService: (any MediaServiceProtocol)?
    var dragDropService: DragDropService?
    var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check for notch
        guard NSScreen.main?.hasNotch == true else {
            print("This app requires a MacBook Pro with notch")
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

        // Bind media to state
        setupMediaBindings(media, state: state)
        
        // Setup drag and drop
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
                .sink { [weak self] info in
                    state.songTitle = info.title
                    state.artistName = info.artist
                    state.albumArt = info.artwork
                    state.currentTime = info.elapsedTime
                    state.duration = info.duration
                    state.isPlaying = info.isPlaying
                    self?.menuBarManager?.updateIcon()
                }
        )
    }
    
    /// Reacts to island-mode changes via the Observation framework instead of
    /// polling. `withObservationTracking` fires once per change, so we re-arm it
    /// after each callback to keep listening.
    private func setupIslandObserver(_ state: AppState) {
        notchWindow?.animate(to: state.islandMode)
        // The onChange closure is @Sendable; a nonisolated(unsafe) weak local
        // lets us reach back to self without tripping Swift 6's capture check.
        // Safe in practice: we only touch self after hopping to the main queue.
        nonisolated(unsafe) weak var weakSelf = self
        withObservationTracking {
            _ = state.islandMode
        } onChange: {
            // onChange fires just before the value updates; hop to the main
            // queue so we read the new value and re-subscribe.
            DispatchQueue.main.async {
                guard let self = weakSelf, let state = self.appState else { return }
                self.notchWindow?.animate(to: state.islandMode)
                self.setupIslandObserver(state)
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        mediaService?.stopListening()
    }
}
