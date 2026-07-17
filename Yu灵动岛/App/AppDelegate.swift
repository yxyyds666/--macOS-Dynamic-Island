import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    var notchWindow: NotchWindow?
    var expandPanel: ExpandPanel?
    var menuBarManager: MenuBarManager?
    var mediaService: MediaService?
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
        
        // Initialize state
        let state = AppState()
        self.appState = state
        
        // Setup services
        let media = MediaService()
        self.mediaService = media
        media.startListening()
        
        // Bind media to state
        setupMediaBindings(media, state: state)
        
        // Setup drag and drop
        let dragService = DragDropService(appState: state)
        self.dragDropService = dragService
        
        // Create windows
        let notchWin = NotchWindow(appState: state)
        self.notchWindow = notchWin
        
        let panel = ExpandPanel(appState: state)
        self.expandPanel = panel
        
        // Setup menu bar
        let menuManager = MenuBarManager(appState: state)
        menuManager.setup()
        self.menuBarManager = menuManager
        
        // Observe expand state
        setupExpandObserver(state)
        
        // Setup drag destination on notch window
        if let contentView = notchWin.contentView {
            dragService.setupDragDestination(for: contentView)
        }
    }
    
    private func setupMediaBindings(_ media: MediaService, state: AppState) {
        cancellables.insert(
            media.nowPlayingPublisher
                .receive(on: DispatchQueue.main)
                .sink { info in
                    state.songTitle = info.title
                    state.artistName = info.artist
                    state.albumArt = info.artwork
                    state.currentTime = info.elapsedTime
                    state.duration = info.duration
                    state.isPlaying = info.isPlaying
                }
        )
    }
    
    private func setupExpandObserver(_ state: AppState) {
        // Simple polling approach for @Observable
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let state = self.appState else { return }
            if state.isExpanded {
                self.expandPanel?.show()
            } else {
                self.expandPanel?.hide()
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        mediaService?.stopListening()
    }
}
