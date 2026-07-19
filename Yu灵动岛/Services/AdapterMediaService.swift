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

    private var streamProcess: Process?
    private var streamBuffer = Data()
    private var streamPipe: Pipe?

    /// Latest merged now-playing fields (stream emits diffs).
    private var merged: [String: Any] = [:]

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
        guard isAvailable, let scriptPath, let frameworkPath else {
            print("[Adapter] media adapter resources missing; now-playing disabled")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: perlPath)
        process.arguments = [scriptPath, frameworkPath, "stream", "--debounce=150"]

        let pipe = Pipe()
        streamPipe = pipe
        process.standardOutput = pipe
        process.standardError = Pipe() // discard stderr (non-fatal per docs)

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.ingest(data)
        }

        do {
            try process.run()
            streamProcess = process
        } catch {
            print("[Adapter] failed to start stream: \(error)")
        }
    }

    func stopListening() {
        streamProcess?.terminate()
        streamPipe?.fileHandleForReading.readabilityHandler = nil
        streamPipe = nil
        streamProcess = nil
    }

    // MARK: - Stream parsing

    /// Buffers stdout and processes each complete newline-delimited JSON line.
    private func ingest(_ data: Data) {
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
        let title = dict["title"] as? String ?? ""
        // No title → treat as nothing playing.
        guard !title.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                self?.nowPlayingSubject.send(.empty)
                self?.isPlayingSubject.send(false)
            }
            return
        }

        let artist = dict["artist"] as? String ?? ""
        let album = dict["album"] as? String ?? ""
        let duration = (dict["duration"] as? NSNumber)?.doubleValue ?? 0
        let elapsed = (dict["elapsedTime"] as? NSNumber)?.doubleValue ?? 0
        let playing = (dict["playing"] as? Bool) ?? false

        var artwork: NSImage?
        if let b64 = dict["artworkData"] as? String,
           let imgData = Data(base64Encoded: b64) {
            artwork = NSImage(data: imgData)
        }

        let info = NowPlayingInfo(
            title: title,
            artist: artist,
            album: album,
            artwork: artwork,
            duration: duration,
            elapsedTime: elapsed,
            isPlaying: playing
        )

        DispatchQueue.main.async { [weak self] in
            self?.nowPlayingSubject.send(info)
            self?.isPlayingSubject.send(playing)
        }
    }

    // MARK: - Control (one-shot child processes)

    /// MediaRemote command IDs (see MediaRemoteAdapter.h).
    private enum Command {
        static let play = 0
        static let pause = 1
        static let togglePlayPause = 2
        static let nextTrack = 3
        static let previousTrack = 4
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
    func setVolume(_ volume: Float) {
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
