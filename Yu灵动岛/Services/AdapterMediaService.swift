import Foundation
import Combine
import AppKit

/// Now-playing access that survives macOS 15.4+.
///
/// Since 15.4 the MediaRemote framework refuses to answer processes that lack a
/// private entitlement, so loading it directly (see the old `MediaService`)
/// always returned nil. Instead we shell out to `/usr/bin/perl` — a system
/// binary that *is* entitled — and have it load a small helper framework
/// (`MediaRemoteAdapter.framework`) that prints now-playing JSON to stdout.
///
/// - `stream` runs as a long-lived child process emitting line-delimited JSON
///   diffs, which we merge into the current state.
/// - control commands (`send`, `seek`) run as one-shot child processes.
final class AdapterMediaService: MediaServiceProtocol, @unchecked Sendable {
    private let nowPlayingSubject = CurrentValueSubject<NowPlayingInfo, Never>(.empty)
    private let isPlayingSubject = CurrentValueSubject<Bool, Never>(false)

    var nowPlayingPublisher: AnyPublisher<NowPlayingInfo, Never> {
        nowPlayingSubject.eraseToAnyPublisher()
    }
    var isPlayingPublisher: AnyPublisher<Bool, Never> {
        isPlayingSubject.eraseToAnyPublisher()
    }

    private let perlPath = "/usr/bin/perl"
    private let scriptPath: String?
    private let frameworkPath: String?

    private let streamQueue = DispatchQueue(label: "com.yuxi.yulingdongdao.media-stream")
    private var streamProcess: Process?
    private var streamPipe: Pipe?
    private var streamBuffer = Data()
    private var merged: [String: Any] = [:]
    private var streamGeneration: UInt = 0
    private var shouldRestart = false

    init() {
        let resources = Bundle.main.resourceURL?.appendingPathComponent("MediaRemoteAdapter")
        let script = resources?.appendingPathComponent("mediaremote-adapter.pl")
        let framework = resources?.appendingPathComponent("MediaRemoteAdapter.framework")
        self.scriptPath = script?.path
        self.frameworkPath = framework?.path
    }

    var isAvailable: Bool {
        guard let scriptPath, let frameworkPath else { return false }
        return FileManager.default.fileExists(atPath: scriptPath)
            && FileManager.default.fileExists(atPath: frameworkPath)
    }

    // MARK: - Listening

    func startListening() {
        streamQueue.async { [weak self] in
            self?.startStream()
        }
    }

    func stopListening() {
        streamQueue.async { [weak self] in
            self?.stopStream()
        }
    }

    private func startStream() {
        guard isAvailable, let scriptPath, let frameworkPath else {
            print("[Adapter] media adapter resources missing; now-playing disabled")
            return
        }
        guard streamProcess == nil else { return }

        shouldRestart = true
        streamGeneration &+= 1
        let generation = streamGeneration
        streamBuffer.removeAll(keepingCapacity: true)
        merged.removeAll(keepingCapacity: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: perlPath)
        process.arguments = [scriptPath, frameworkPath, "stream", "--debounce=150"]

        let pipe = Pipe()
        streamPipe = pipe
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.streamQueue.async { [weak self] in
                self?.ingest(data, generation: generation)
            }
        }
        process.terminationHandler = { [weak self, weak process] _ in
            guard let process else { return }
            self?.streamQueue.async { [weak self] in
                self?.handleStreamTermination(process, generation: generation)
            }
        }

        do {
            try process.run()
            streamProcess = process
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            streamPipe = nil
            print("[Adapter] failed to start stream: \(error)")
            scheduleRestart(generation: generation)
        }
    }

    private func stopStream() {
        shouldRestart = false
        streamGeneration &+= 1
        let process = streamProcess
        streamPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        streamPipe = nil
        streamProcess = nil
        streamBuffer.removeAll(keepingCapacity: false)
        merged.removeAll(keepingCapacity: false)
        process?.terminate()
    }

    private func handleStreamTermination(_ process: Process, generation: UInt) {
        guard generation == streamGeneration, streamProcess === process else { return }
        streamPipe?.fileHandleForReading.readabilityHandler = nil
        streamPipe = nil
        streamProcess = nil
        streamBuffer.removeAll(keepingCapacity: false)
        merged.removeAll(keepingCapacity: false)
        publishEmpty(generation: generation)
        scheduleRestart(generation: generation)
    }

    private func scheduleRestart(generation: UInt) {
        guard shouldRestart, generation == streamGeneration else { return }
        streamQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self,
                  self.shouldRestart,
                  generation == self.streamGeneration,
                  self.streamProcess == nil else { return }
            self.startStream()
        }
    }

    // MARK: - Stream parsing

    /// Buffers stdout and processes each complete newline-delimited JSON line.
    private func ingest(_ data: Data, generation: UInt) {
        guard generation == streamGeneration, shouldRestart else { return }
        streamBuffer.append(data)
        while let newline = streamBuffer.firstIndex(of: 0x0A) {
            let lineData = streamBuffer.subdata(in: streamBuffer.startIndex..<newline)
            streamBuffer.removeSubrange(streamBuffer.startIndex...newline)
            handleLine(lineData)
        }
    }

    private func handleLine(_ lineData: Data) {
        guard !lineData.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let payload = obj["payload"] as? [String: Any] else {
            return
        }

        let isDiff = (obj["diff"] as? Bool) ?? false
        if isDiff {
            // Merge changed keys; a null value means the key vanished.
            for (key, value) in payload {
                if value is NSNull { merged.removeValue(forKey: key) }
                else { merged[key] = value }
            }
        } else {
            merged = payload
        }

        publish(from: merged)
    }

    private func publish(from dict: [String: Any]) {
        let generation = streamGeneration
        let title = dict["title"] as? String ?? ""
        // No title → treat as nothing playing.
        guard !title.isEmpty else {
            publishEmpty(generation: generation)
            return
        }

        let artist = dict["artist"] as? String ?? ""
        let album = dict["album"] as? String ?? ""
        let duration = (dict["duration"] as? NSNumber)?.doubleValue ?? 0
        let playing = (dict["playing"] as? Bool) ?? false
        let elapsed = currentElapsedTime(from: dict, duration: duration, isPlaying: playing)

        var artwork: NSImage?
        if let b64 = dict["artworkData"] as? String,
           let imgData = Data(base64Encoded: b64) {
            artwork = NSImage(data: imgData)
        }

        // For web players the framework reports the page's client id in
        // bundleIdentifier's absence via the parent (browser) bundle.
        let bundleID = (dict["bundleIdentifier"] as? String)
            ?? (dict["parentApplicationBundleIdentifier"] as? String)

        let info = NowPlayingInfo(
            title: title,
            artist: artist,
            album: album,
            artwork: artwork,
            duration: duration,
            elapsedTime: elapsed,
            isPlaying: playing,
            sourceBundleID: bundleID?.isEmpty == false ? bundleID : nil
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.streamQueue.async { [weak self] in
                guard let self,
                      generation == self.streamGeneration,
                      self.shouldRestart else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.nowPlayingSubject.send(info)
                    self?.isPlayingSubject.send(playing)
                }
            }
        }
    }

    private func publishEmpty(generation: UInt) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.streamQueue.async { [weak self] in
                guard let self,
                      generation == self.streamGeneration,
                      self.shouldRestart else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.nowPlayingSubject.send(.empty)
                    self?.isPlayingSubject.send(false)
                }
            }
        }
    }

    private func currentElapsedTime(
        from dict: [String: Any],
        duration: TimeInterval,
        isPlaying: Bool
    ) -> TimeInterval {
        let anchor = (dict["elapsedTime"] as? NSNumber)?.doubleValue ?? 0
        let clamp: (TimeInterval) -> TimeInterval = { value in
            let value = max(0, value)
            return duration > 0 ? min(value, duration) : value
        }
        guard isPlaying,
              let timestampText = dict["timestamp"] as? String,
              let timestamp = ISO8601DateFormatter().date(from: timestampText) else {
            return clamp(anchor)
        }
        let rate = (dict["playbackRate"] as? NSNumber)?.doubleValue ?? 1
        return clamp(anchor + max(0, Date().timeIntervalSince(timestamp)) * rate)
    }

    // MARK: - Control (one-shot child processes)

    /// MediaRemote command IDs (see MediaRemoteAdapter.h).
    private enum Command {
        static let play = 0
        static let pause = 1
        static let togglePlayPause = 2
        static let nextTrack = 4
        static let previousTrack = 5
    }

    func play() { runAdapter(["send", "\(Command.play)"]) }
    func pause() { runAdapter(["send", "\(Command.pause)"]) }
    func togglePlayPause() { runAdapter(["send", "\(Command.togglePlayPause)"]) }
    func nextTrack() { runAdapter(["send", "\(Command.nextTrack)"]) }
    func previousTrack() { runAdapter(["send", "\(Command.previousTrack)"]) }

    func seek(to time: TimeInterval) {
        // Adapter expects microseconds.
        let micros = Int(max(0, time) * 1_000_000)
        runAdapter(["seek", "\(micros)"])
    }

    /// The adapter has no volume command, so drive the system output volume.
    @discardableResult
    func setVolume(_ volume: Float) -> Bool {
        SystemAudio.setVolume(volume)
    }

    private func runAdapter(_ args: [String]) {
        guard isAvailable, let scriptPath, let frameworkPath else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: perlPath)
        process.arguments = [scriptPath, frameworkPath] + args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do { try process.run() } catch {
            print("[Adapter] command \(args) failed: \(error)")
        }
    }
}
