import AppKit
import Foundation
import SwiftUI

@MainActor
@Observable
final class AppState {
    // Current focused module. Expanded mode can show both wings, but this drives
    // first-click peek, menu/default selection, and the focused wing treatment.
    var currentModule: NotchModule = .music

    // Interaction state. Keep one source of truth so the island cannot be both
    // peeked and expanded, or hovered while showing a transient activity capsule.
    enum RevealState: Equatable {
        case idle
        case hover
        case activity(ActivityContent)
        case peek
        case expanded
    }

    /// What the horizontal activity capsule is currently showing.
    ///   • lyrics    — hover while focused on music and playing: synced lyrics
    ///   • trackInfo — auto-popped on a track change: artist · album
    enum ActivityContent: Equatable { case lyrics, trackInfo }

    var revealState: RevealState = .idle

    // Music state
    var isPlaying: Bool = false
    var songTitle: String = ""
    var artistName: String = ""
    var albumName: String = ""
    var albumArt: NSImage? = nil
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Float = 0.5

    // Time-synced/plain lyrics for the current track.
    enum LyricsState: Equatable {
        case idle
        case loading
        case synced([LyricLine])
        case plain(String)
        case notFound
        case failed
    }

    var lyricsState: LyricsState = .idle
    var currentLyricIndex: Int = -1

    var lyricsLines: [LyricLine] {
        if case .synced(let lines) = lyricsState { return lines }
        return []
    }

    var plainLyricsText: String? {
        if case .plain(let text) = lyricsState { return text }
        return nil
    }

    func requestLyricsRetry() {
        guard !songTitle.isEmpty else { return }
        setLyricsLoading()
        NotificationCenter.default.post(name: .lyricsRetryRequested, object: nil)
    }

    // File transfer state
    var fileItems: [FileItem] = []

    enum FileDropResult: Equatable {
        case added(Int)
        case partial(added: Int, skipped: Int)
        case full
        case disabled
        case empty
    }

    struct FileDropFeedback: Identifiable, Equatable, Sendable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    var fileDropFeedback: FileDropFeedback?

    // Settings
    var showMusicModule: Bool = true
    var showFileModule: Bool = true

    // Drag state
    var isDragTarget: Bool = false

    // Media control (injected by AppDelegate; not observed)
    @ObservationIgnored weak var mediaService: (any MediaServiceProtocol)?
    @ObservationIgnored private var progressTimer: Timer?
    @ObservationIgnored private var activityDismissTimer: Timer?
    @ObservationIgnored private var fileFeedbackTask: Task<Void, Never>?

    init() {
        SettingsManager.shared.normalizeModuleSettings()
        loadSettings()
        // Honor the user's preferred default module, clamped to what's enabled.
        let preferred = SettingsManager.shared.defaultModule
        currentModule = availableModules.contains(preferred) ? preferred : (availableModules.first ?? .music)

        NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadSettings(applyDefault: true)
            }
        }
    }

    /// Re-reads persisted settings and reconciles the active/default module.
    func reloadSettings(applyDefault: Bool = false) {
        loadSettings()
        clampCurrentModule(applyDefault: applyDefault)
    }

    private func clampCurrentModule(applyDefault: Bool) {
        let modules = availableModules
        if applyDefault, modules.contains(SettingsManager.shared.defaultModule) {
            currentModule = SettingsManager.shared.defaultModule
        } else if !modules.contains(currentModule) {
            currentModule = modules.first ?? .music
        }
    }

    /// The island's visual state: expanded wins, then peek, then the horizontal
    /// activity capsule, then hover, else idle.
    var islandMode: IslandMode {
        switch revealState {
        case .idle:
            return isPlaying && !songTitle.isEmpty ? .playing : .idle
        case .hover: return .hover
        case .activity: return .activity
        case .peek: return .peek
        case .expanded: return .expanded
        }
    }

    var activityContent: ActivityContent? {
        if case .activity(let content) = revealState { return content }
        return nil
    }

    /// Mouse entered the notch. Hovering focused music while a track is playing
    /// shows the horizontal lyrics capsule; otherwise it is only a subtle bulge.
    func mouseEnteredNotch() {
        cancelActivityAutoDismiss()
        guard revealState != .peek, revealState != .expanded else { return }
        if currentModule == .music, showMusicModule, isPlaying, !songTitle.isEmpty {
            revealState = .activity(.lyrics)
        } else {
            revealState = .hover
        }
    }

    /// Mouse left the island: collapse everything back to idle.
    func mouseExitedNotch() {
        collapse()
    }

    /// A click advances the reveal one step: idle/hover/activity → peek for the
    /// focused module, then peek → expanded two-wing layout.
    func advanceReveal() {
        cancelActivityAutoDismiss()
        clampCurrentModule(applyDefault: false)
        switch revealState {
        case .peek:
            revealState = .expanded
        case .expanded:
            break
        default:
            revealState = .peek
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

    func selectModule(_ module: NotchModule, reveal: Bool = false) {
        guard availableModules.contains(module) else { return }
        currentModule = module
        if reveal {
            cancelActivityAutoDismiss()
            if revealState != .expanded {
                revealState = .peek
            }
        }
    }

    // MARK: - Track-change activity

    /// Called when the now-playing track changes. Pops the horizontal capsule
    /// showing the new track's info, then auto-collapses after a few seconds.
    func trackDidChange() {
        // Don't hijack the island if the user is actively interacting with it.
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

    // MARK: - Drag/File state

    /// A file drag arrived over the notch. Return false to reject hidden/full file
    /// station drags before AppKit starts a copy operation.
    @discardableResult
    func beginFileDrag() -> Bool {
        guard showFileModule else {
            showFileDropFeedback("文件中转站已关闭", isError: true)
            return false
        }
        guard remainingFileSlots > 0 else {
            showFileDropFeedback("文件中转站已满", isError: true)
            return false
        }
        isDragTarget = true
        currentModule = .file
        revealState = .expanded
        cancelActivityAutoDismiss()
        return true
    }

    func dragEnteredNotch() {
        _ = beginFileDrag()
    }

    /// The drag left without dropping: snap crisply back to idle.
    func dragExitedNotch() {
        isDragTarget = false
        collapse()
    }

    var remainingFileSlots: Int {
        max(0, AppConstants.maxFileItems - fileItems.count)
    }

    var canAcceptFiles: Bool {
        showFileModule && remainingFileSlots > 0
    }

    @discardableResult
    func addFiles(_ urls: [URL]) -> FileDropResult {
        guard showFileModule else {
            let result: FileDropResult = .disabled
            showFileDropFeedback(for: result)
            return result
        }

        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else {
            let result: FileDropResult = .empty
            showFileDropFeedback(for: result)
            return result
        }

        let remaining = remainingFileSlots
        guard remaining > 0 else {
            let result: FileDropResult = .full
            showFileDropFeedback(for: result)
            return result
        }

        let accepted = Array(fileURLs.prefix(remaining))
        for url in accepted {
            addFile(FileItem(url: url))
        }
        currentModule = .file

        let skipped = fileURLs.count - accepted.count
        let result: FileDropResult = skipped > 0
            ? .partial(added: accepted.count, skipped: skipped)
            : .added(accepted.count)
        showFileDropFeedback(for: result)
        return result
    }

    private func showFileDropFeedback(for result: FileDropResult) {
        switch result {
        case .added(let count):
            showFileDropFeedback("已添加 \(count) 个文件", isError: false)
        case .partial(let added, let skipped):
            showFileDropFeedback("已添加 \(added) 个，\(skipped) 个超出上限", isError: true)
        case .full:
            showFileDropFeedback("文件中转站已满", isError: true)
        case .disabled:
            showFileDropFeedback("文件中转站已关闭", isError: true)
        case .empty:
            showFileDropFeedback("没有可添加的文件", isError: true)
        }
    }

    func showFileDropFeedback(_ message: String, isError: Bool) {
        fileFeedbackTask?.cancel()
        let feedback = FileDropFeedback(message: message, isError: isError)
        fileDropFeedback = feedback
        fileFeedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled, self?.fileDropFeedback?.id == feedback.id else { return }
            self?.fileDropFeedback = nil
        }
    }

    // MARK: - Lyrics

    var syncedLyrics: [LyricLine] {
        if case .synced(let lines) = lyricsState { return lines }
        return []
    }

    // Compatibility for code paths that only need synced lyric lines.
    var lyrics: [LyricLine] {
        get { syncedLyrics }
        set {
            lyricsState = newValue.isEmpty ? .notFound : .synced(newValue)
            if newValue.isEmpty { currentLyricIndex = -1 }
        }
    }

    func resetLyrics() {
        lyricsState = .idle
        currentLyricIndex = -1
    }

    func setLyricsLoading() {
        lyricsState = .loading
        currentLyricIndex = -1
    }

    func applyLyricsResult(_ result: LyricsFetchResult) {
        switch result {
        case .synced(let lines):
            lyricsState = lines.isEmpty ? .notFound : .synced(lines)
        case .plain(let text):
            lyricsState = text.isEmpty ? .notFound : .plain(text)
        case .notFound:
            lyricsState = .notFound
        case .failed:
            lyricsState = .failed
        }
        updateCurrentLyric(at: currentTime)
    }

    /// Index of the lyric line active at the given playback time, or -1 if the
    /// track has no synced lyrics or playback is before the first line.
    func updateCurrentLyric(at time: TimeInterval) {
        guard case .synced(let lines) = lyricsState, !lines.isEmpty else {
            currentLyricIndex = -1
            return
        }
        var idx = -1
        for (i, line) in lines.enumerated() where line.time <= time { idx = i }
        currentLyricIndex = idx
    }

    var hasMediaPlaying: Bool {
        !songTitle.isEmpty
    }

    var hasFiles: Bool {
        !fileItems.isEmpty
    }

    var canAddFile: Bool {
        remainingFileSlots > 0
    }

    func nextModule() {
        let modules = availableModules
        guard let currentIndex = modules.firstIndex(of: currentModule), !modules.isEmpty else { return }
        let nextIndex = (currentIndex + 1) % modules.count
        currentModule = modules[nextIndex]
    }

    var availableModules: [NotchModule] {
        var modules: [NotchModule] = []
        if showMusicModule { modules.append(.music) }
        if showFileModule { modules.append(.file) }
        return modules
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
        showFileDropFeedback("已清空", isError: false)
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
        updateCurrentLyric(at: clamped)
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

    /// Smoothly advances `currentTime` between now-playing updates so the progress
    /// bar and highlighted lyric do not visibly jump.
    func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                let next = self.currentTime + 0.5
                if self.duration <= 0 || next <= self.duration {
                    self.currentTime = next
                }
                self.updateCurrentLyric(at: self.currentTime)
            }
        }
    }

    func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func loadSettings() {
        let settings = SettingsManager.shared
        settings.normalizeModuleSettings()
        showMusicModule = settings.showMusicModule
        showFileModule = settings.showFileModule
    }
}
