import Foundation
import Combine
import SwiftUI

@Observable
final class AppState {
    // Current active module
    var currentModule: NotchModule = .music
    
    // Interaction states, in increasing order of reveal:
    //   isHovered  — mouse over the notch (kept in sync with isPeeking)
    //   isPeeking  — music player drapes down (peek); shown as soon as hovered
    //   isExpanded — clicked → wide bar wrapping around the notch (expanded)
    var isHovered: Bool = false
    var isPeeking: Bool = false
    var isExpanded: Bool = false

    // Music state
    var isPlaying: Bool = false
    var songTitle: String = ""
    var artistName: String = ""
    var albumArt: NSImage? = nil
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Float = 0.5
    var lyrics: [String] = []
    var currentLyricIndex: Int = -1
    
    // File transfer state
    var fileItems: [FileItem] = []
    
    // Settings
    var showMusicModule: Bool = true
    var showFileModule: Bool = true
    
    // Drag state
    var isDragTarget: Bool = false

    // Media control (injected by AppDelegate; not observed)
    @ObservationIgnored weak var mediaService: (any MediaServiceProtocol)?
    @ObservationIgnored private var progressTimer: Timer?

    init() {
        loadSettings()
        // Honor the user's preferred default module, clamped to what's enabled.
        let preferred = SettingsManager.shared.defaultModule
        currentModule = availableModules.contains(preferred) ? preferred : (availableModules.first ?? .music)

        NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadSettings()
        }
    }

    /// Re-reads persisted settings and re-clamps the active module. Called when
    /// the Settings window saves changes.
    func reloadSettings() {
        loadSettings()
        if !availableModules.contains(currentModule) {
            currentModule = availableModules.first ?? .music
        }
    }
    
    /// The island's visual state: expanded wins, then peek, then hover, else idle.
    var islandMode: IslandMode {
        if isExpanded { return .expanded }
        if isPeeking { return .peek }
        if isHovered { return .hover }
        return .idle
    }

    /// Mouse entered the notch: drape the music player straight down
    /// immediately (no dwell), so the user can reach the volume slider right
    /// away without waiting.
    func mouseEnteredNotch() {
        isHovered = true
        isPeeking = true
    }

    /// Mouse left the notch: collapse everything back to idle.
    func mouseExitedNotch() {
        isHovered = false
        isPeeking = false
        isExpanded = false
    }

    /// A click anywhere on the island commits to the expanded layout.
    func expand() {
        isExpanded = true
    }

    /// A file drag arrived over the notch: pop straight open to the expanded
    /// layout so the file transfer panel is ready to receive the drop.
    func dragEnteredNotch() {
        isHovered = true
        isExpanded = true
    }

    /// The drag left without dropping: snap crisply back to idle.
    func dragExitedNotch() {
        isHovered = false
        isPeeking = false
        isExpanded = false
    }

    var hasMediaPlaying: Bool {
        !songTitle.isEmpty
    }
    
    var hasFiles: Bool {
        !fileItems.isEmpty
    }
    
    var canAddFile: Bool {
        fileItems.count < AppConstants.maxFileItems
    }
    
    func nextModule() {
        let modules = availableModules
        guard let currentIndex = modules.firstIndex(of: currentModule) else { return }
        let nextIndex = (currentIndex + 1) % modules.count
        currentModule = modules[nextIndex]
    }
    
    var availableModules: [NotchModule] {
        var modules: [NotchModule] = []
        if showMusicModule { modules.append(.music) }
        if showFileModule { modules.append(.file) }
        return modules.isEmpty ? [.music] : modules
    }
    
    func addFile(_ item: FileItem) {
        guard canAddFile else { return }
        fileItems.append(item)
    }
    
    func removeFile(at index: Int) {
        guard fileItems.indices.contains(index) else { return }
        fileItems.remove(at: index)
    }
    
    func clearAllFiles() {
        fileItems.removeAll()
    }

    // MARK: - Media Control

    func togglePlayPause() {
        mediaService?.togglePlayPause()
        // Optimistic update; corrected by the next now-playing poll.
        isPlaying.toggle()
    }

    func nextTrack() {
        mediaService?.nextTrack()
    }

    func previousTrack() {
        mediaService?.previousTrack()
    }

    func seek(to time: TimeInterval) {
        let clamped = min(max(0, time), duration)
        currentTime = clamped
        mediaService?.seek(to: clamped)
    }

    func setVolume(_ newValue: Float) {
        volume = newValue
        mediaService?.setVolume(newValue)
    }

    /// Syncs the slider to the actual system output volume so it starts at the
    /// right position rather than a hardcoded default.
    func syncVolumeFromSystem() {
        if let system = SystemAudio.currentVolume() {
            volume = system
        }
    }

    /// Smoothly advances `currentTime` between the 1s now-playing polls so the
    /// progress bar doesn't visibly jump.
    func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            let next = self.currentTime + 0.5
            if self.duration <= 0 || next <= self.duration {
                self.currentTime = next
            }
        }
    }

    func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func loadSettings() {
        let settings = SettingsManager.shared
        showMusicModule = settings.showMusicModule
        showFileModule = settings.showFileModule
    }
}
