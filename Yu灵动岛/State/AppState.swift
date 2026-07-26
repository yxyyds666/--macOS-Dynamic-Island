import AppKit
import Foundation
import SwiftUI

/// Shared app-wide content state. All screen islands read from this single
/// instance — music, lyrics, files, settings, and media control live here.
/// Per-screen interaction state (reveal, hover, drag, notch size) lives in
/// `IslandState`, one per screen.
@MainActor
@Observable
final class AppState {
    // MARK: - Module selection (shared across screens)

    var currentModule: NotchModule = .music

    // MARK: - Music state

    var isPlaying: Bool = false
    var songTitle: String = ""
    var artistName: String = ""
    var albumName: String = ""
    var albumArt: NSImage? = nil
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Float = 0.5

    /// The app the media is playing from, resolved once per bundle-id change.
    private(set) var sourceBundleID: String?
    private(set) var sourceAppIcon: NSImage?
    private(set) var sourceAppName: String?

    // MARK: - Lyrics

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

    // MARK: - File transfer state

    var fileItems: [FileItem] = []

    enum FileDropResult: Equatable {
        case added(Int)
        case partial(added: Int, invalid: Int, overflow: Int)
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

    // MARK: - Settings (mirrored from UserDefaults so views can observe)

    var showMusicModule: Bool = true
    var showFileModule: Bool = true
    /// Multiplier applied to spring response times. 1.0 = default, >1 = faster.
    var animationSpeed: Double = 1.0
    /// Whether hovering reveals the island.
    var hoverToReveal: Bool = true
    /// Seconds the cursor must dwell before hover reveals the island.
    var hoverDelay: Double = 0
    /// Whether the album artwork gently breathes (scales) while playing.
    var artworkBreathing: Bool = true
    /// Scale factor for lyrics text in the expanded panel.
    var lyricsFontScale: Double = 1.0

    // MARK: - Media control (injected by AppDelegate; not observed)

    @ObservationIgnored weak var mediaService: (any MediaServiceProtocol)?
    @ObservationIgnored private var progressTimer: Timer?
    @ObservationIgnored private var fileFeedbackTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        SettingsManager.shared.normalizeModuleSettings()
        loadSettings()
        let preferred = SettingsManager.shared.defaultModule
        currentModule = availableModules.contains(preferred)
            ? preferred
            : (availableModules.first ?? .music)

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

    // MARK: - Module management

    var availableModules: [NotchModule] {
        var modules: [NotchModule] = []
        if showMusicModule { modules.append(.music) }
        if showFileModule  { modules.append(.file)  }
        return modules
    }

    /// Change the active module. Does NOT affect reveal state (callers must
    /// call the relevant `IslandState` methods for that).
    func selectModule(_ module: NotchModule) {
        guard availableModules.contains(module) else { return }
        currentModule = module
    }

    func nextModule() {
        let modules = availableModules
        guard let idx = modules.firstIndex(of: currentModule), !modules.isEmpty else { return }
        currentModule = modules[(idx + 1) % modules.count]
    }

    // MARK: - Settings

    func reloadSettings(applyDefault: Bool = false) {
        loadSettings()
        let modules = availableModules
        if applyDefault, modules.contains(SettingsManager.shared.defaultModule) {
            currentModule = SettingsManager.shared.defaultModule
        } else if !modules.contains(currentModule) {
            currentModule = modules.first ?? .music
        }
    }

    private func loadSettings() {
        let s = SettingsManager.shared
        s.normalizeModuleSettings()
        showMusicModule  = s.showMusicModule
        showFileModule   = s.showFileModule
        animationSpeed   = s.animationSpeed > 0 ? s.animationSpeed : 1.0
        hoverToReveal    = s.hoverToReveal
        hoverDelay       = s.hoverDelay
        artworkBreathing = s.artworkBreathing
        lyricsFontScale  = s.lyricsFontScale > 0 ? s.lyricsFontScale : 1.0
    }

    // MARK: - File management

    var remainingFileSlots: Int { max(0, AppConstants.maxFileItems - fileItems.count) }
    var canAcceptFiles: Bool    { showFileModule && remainingFileSlots > 0 }
    var hasFiles: Bool          { !fileItems.isEmpty }
    var canAddFile: Bool        { remainingFileSlots > 0 }
    var hasMediaPlaying: Bool   { !songTitle.isEmpty }

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

    @discardableResult
    func addFiles(_ urls: [URL]) -> FileDropResult {
        guard showFileModule else {
            let r: FileDropResult = .disabled; showFileDropFeedback(for: r); return r
        }
        let candidates = urls.filter(\.isFileURL)
        let invalid = urls.count - candidates.count
        guard !candidates.isEmpty else {
            let r: FileDropResult = .empty; showFileDropFeedback(for: r); return r
        }
        let remaining = remainingFileSlots
        guard remaining > 0 else {
            let r: FileDropResult = .full; showFileDropFeedback(for: r); return r
        }
        let items = candidates.compactMap(FileItem.init(url:))
        let rejected = candidates.count - items.count
        guard !items.isEmpty else {
            let r: FileDropResult = .empty; showFileDropFeedback(for: r); return r
        }
        let accepted = Array(items.prefix(remaining))
        for item in accepted { addFile(item) }
        currentModule = .file
        let overflow     = max(0, items.count - accepted.count)
        let invalidCount = invalid + rejected
        let result: FileDropResult = invalidCount > 0 || overflow > 0
            ? .partial(added: accepted.count, invalid: invalidCount, overflow: overflow)
            : .added(accepted.count)
        showFileDropFeedback(for: result)
        return result
    }

    private func showFileDropFeedback(for result: FileDropResult) {
        switch result {
        case .added(let n):
            showFileDropFeedback("已添加 \(n) 个文件", isError: false)
        case .partial(let added, let invalid, let overflow):
            var d: [String] = []
            if invalid  > 0 { d.append("\(invalid) 个无效项目") }
            if overflow > 0 { d.append("\(overflow) 个超出上限") }
            showFileDropFeedback("已添加 \(added) 个，" + d.joined(separator: "，"), isError: true)
        case .full:     showFileDropFeedback("文件中转站已满", isError: true)
        case .disabled: showFileDropFeedback("文件中转站已关闭", isError: true)
        case .empty:    showFileDropFeedback("没有可添加的文件", isError: true)
        }
    }

    func showFileDropFeedback(_ message: String, isError: Bool) {
        fileFeedbackTask?.cancel()
        let fb = FileDropFeedback(message: message, isError: isError)
        fileDropFeedback = fb
        fileFeedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled, self?.fileDropFeedback?.id == fb.id else { return }
            self?.fileDropFeedback = nil
        }
    }

    // MARK: - Lyrics helpers

    var syncedLyrics: [LyricLine] {
        if case .synced(let lines) = lyricsState { return lines }
        return []
    }

    var lyrics: [LyricLine] {
        get { syncedLyrics }
        set {
            lyricsState = newValue.isEmpty ? .notFound : .synced(newValue)
            if newValue.isEmpty { currentLyricIndex = -1 }
        }
    }

    func resetLyrics() { lyricsState = .idle; currentLyricIndex = -1 }
    func setLyricsLoading() { lyricsState = .loading; currentLyricIndex = -1 }

    func applyLyricsResult(_ result: LyricsFetchResult) {
        switch result {
        case .synced(let lines): lyricsState = lines.isEmpty ? .notFound : .synced(lines)
        case .plain(let text):   lyricsState = text.isEmpty  ? .notFound : .plain(text)
        case .notFound:          lyricsState = .notFound
        case .failed:            lyricsState = .failed
        }
        updateCurrentLyric(at: currentTime)
    }

    func updateCurrentLyric(at time: TimeInterval) {
        guard case .synced(let lines) = lyricsState, !lines.isEmpty else {
            currentLyricIndex = -1; return
        }
        var idx = -1
        for (i, line) in lines.enumerated() where line.time <= time { idx = i }
        currentLyricIndex = idx
    }

    // MARK: - Music source

    /// Update the source app for the current media. Icon/name lookups hit the
    /// filesystem, so only re-resolve when the bundle id actually changes.
    func updateSource(bundleID: String?) {
        guard bundleID != sourceBundleID else { return }
        sourceBundleID = bundleID
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            sourceAppIcon = nil
            sourceAppName = nil
            return
        }
        sourceAppIcon = NSWorkspace.shared.icon(forFile: url.path)
        sourceAppName = (FileManager.default.displayName(atPath: url.path) as NSString)
            .deletingPathExtension
    }

    /// Bring the source app forward (launch it if it quit since reporting).
    func openMusicSource() {
        guard let sourceBundleID else { return }
        if let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: sourceBundleID).first {
            running.activate()
        } else if let url = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: sourceBundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Media Control

    func togglePlayPause() { mediaService?.togglePlayPause(); isPlaying.toggle() }
    func nextTrack()        { mediaService?.nextTrack() }
    func previousTrack()    { mediaService?.previousTrack() }

    func seek(to time: TimeInterval) {
        let c = min(max(0, time), duration)
        currentTime = c
        mediaService?.seek(to: c)
        updateCurrentLyric(at: c)
    }

    func setVolume(_ newValue: Float) {
        let clamped = min(max(newValue, 0), 1)
        let previous = volume
        guard mediaService?.setVolume(clamped) == true else {
            volume = SystemAudio.currentVolume() ?? previous; return
        }
        volume = clamped
    }

    func syncVolumeFromSystem() {
        if let v = SystemAudio.currentVolume() { volume = v }
    }

    func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                let next = self.currentTime + 0.5
                if self.duration <= 0 || next <= self.duration { self.currentTime = next }
                self.updateCurrentLyric(at: self.currentTime)
            }
        }
    }

    func stopProgressTimer() { progressTimer?.invalidate(); progressTimer = nil }
}
