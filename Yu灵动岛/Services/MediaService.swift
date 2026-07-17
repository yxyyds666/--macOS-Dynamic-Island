import Foundation
import Combine
import AppKit

// MARK: - MediaRemote Runtime Loader

final class MediaRemoteLoader: @unchecked Sendable {
    static let shared = MediaRemoteLoader()
    
    private var handle: UnsafeMutableRawPointer?
    
    // Function pointers
    private var _registerForNowPlayingNotifications: ((DispatchQueue) -> Void)?
    private var _getNowPlayingInfo: ((DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void)?
    private var _sendCommand: ((UInt32, [String: Any]?) -> Void)?
    private var _setElapsedTime: ((Double) -> Void)?
    private var _setVolume: ((Float) -> Void)?
    
    // String constants
    var kMRMediaRemoteNowPlayingInfoTitle: String?
    var kMRMediaRemoteNowPlayingInfoArtist: String?
    var kMRMediaRemoteNowPlayingInfoAlbum: String?
    var kMRMediaRemoteNowPlayingInfoDuration: String?
    var kMRMediaRemoteNowPlayingInfoElapsedTime: String?
    var kMRMediaRemoteNowPlayingInfoPlaybackRate: String?
    var kMRMediaRemoteNowPlayingInfoArtworkData: String?
    
    let isAvailable: Bool
    
    private init() {
        // Try to load MediaRemote framework
        let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        handle = dlopen(frameworkPath, RTLD_NOW)
        
        guard handle != nil else {
            isAvailable = false
            return
        }
        
        isAvailable = true
        loadFunctions()
        loadConstants()
    }
    
    private func loadFunctions() {
        guard let handle = handle else { return }
        
        // MRMediaRemoteRegisterForNowPlayingNotifications
        if let sym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            typealias FuncType = @convention(c) (DispatchQueue) -> Void
            _registerForNowPlayingNotifications = unsafeBitCast(sym, to: FuncType.self)
        }
        
        // MRMediaRemoteGetNowPlayingInfo
        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            typealias FuncType = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
            _getNowPlayingInfo = unsafeBitCast(sym, to: FuncType.self)
        }
        
        // MRMediaRemoteSendCommand
        if let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
            typealias FuncType = @convention(c) (UInt32, [String: Any]?) -> Void
            _sendCommand = unsafeBitCast(sym, to: FuncType.self)
        }
        
        // MRMediaRemoteSetElapsedTime
        if let sym = dlsym(handle, "MRMediaRemoteSetElapsedTime") {
            typealias FuncType = @convention(c) (Double) -> Void
            _setElapsedTime = unsafeBitCast(sym, to: FuncType.self)
        }
        
        // MRMediaRemoteSetVolume
        if let sym = dlsym(handle, "MRMediaRemoteSetVolume") {
            typealias FuncType = @convention(c) (Float) -> Void
            _setVolume = unsafeBitCast(sym, to: FuncType.self)
        }
    }
    
    private func loadConstants() {
        guard let handle = handle else { return }
        
        // Load string constants
        if let sym = dlsym(handle, "kMRMediaRemoteNowPlayingInfoTitle") {
            kMRMediaRemoteNowPlayingInfoTitle = unsafeBitCast(sym, to: NSString.self) as String
        }
        if let sym = dlsym(handle, "kMRMediaRemoteNowPlayingInfoArtist") {
            kMRMediaRemoteNowPlayingInfoArtist = unsafeBitCast(sym, to: NSString.self) as String
        }
        if let sym = dlsym(handle, "kMRMediaRemoteNowPlayingInfoAlbum") {
            kMRMediaRemoteNowPlayingInfoAlbum = unsafeBitCast(sym, to: NSString.self) as String
        }
        if let sym = dlsym(handle, "kMRMediaRemoteNowPlayingInfoDuration") {
            kMRMediaRemoteNowPlayingInfoDuration = unsafeBitCast(sym, to: NSString.self) as String
        }
        if let sym = dlsym(handle, "kMRMediaRemoteNowPlayingInfoElapsedTime") {
            kMRMediaRemoteNowPlayingInfoElapsedTime = unsafeBitCast(sym, to: NSString.self) as String
        }
        if let sym = dlsym(handle, "kMRMediaRemoteNowPlayingInfoPlaybackRate") {
            kMRMediaRemoteNowPlayingInfoPlaybackRate = unsafeBitCast(sym, to: NSString.self) as String
        }
        if let sym = dlsym(handle, "kMRMediaRemoteNowPlayingInfoArtworkData") {
            kMRMediaRemoteNowPlayingInfoArtworkData = unsafeBitCast(sym, to: NSString.self) as String
        }
    }
    
    // MARK: - Public API
    
    func registerForNowPlayingNotifications(_ queue: DispatchQueue) {
        _registerForNowPlayingNotifications?(queue)
    }
    
    func getNowPlayingInfo(_ queue: DispatchQueue, handler: @escaping ([String: Any]?) -> Void) {
        _getNowPlayingInfo?(queue, handler)
    }
    
    func sendCommand(_ command: UInt32, userInfo: [String: Any]? = nil) {
        _sendCommand?(command, userInfo)
    }
    
    func setElapsedTime(_ time: Double) {
        _setElapsedTime?(time)
    }
    
    func setVolume(_ volume: Float) {
        _setVolume?(volume)
    }
}

// MARK: - MediaRemote Commands

enum MRMediaRemoteCommand {
    static let play: UInt32 = 0
    static let pause: UInt32 = 1
    static let togglePlayPause: UInt32 = 2
    static let nextTrack: UInt32 = 3
    static let previousTrack: UInt32 = 4
}

// MARK: - MediaService

final class MediaService: MediaServiceProtocol {
    private let nowPlayingSubject = CurrentValueSubject<NowPlayingInfo, Never>(.empty)
    private let isPlayingSubject = CurrentValueSubject<Bool, Never>(false)
    private var pollTimer: Timer?
    private let loader = MediaRemoteLoader.shared
    
    var nowPlayingPublisher: AnyPublisher<NowPlayingInfo, Never> {
        nowPlayingSubject.eraseToAnyPublisher()
    }
    
    var isPlayingPublisher: AnyPublisher<Bool, Never> {
        isPlayingSubject.eraseToAnyPublisher()
    }
    
    func startListening() {
        guard loader.isAvailable else {
            print("MediaRemote framework not available")
            return
        }
        
        loader.registerForNowPlayingNotifications(DispatchQueue.main)
        
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.fetchNowPlayingInfo()
        }
        
        fetchNowPlayingInfo()
    }
    
    func stopListening() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
    
    func play() {
        loader.sendCommand(MRMediaRemoteCommand.play)
    }
    
    func pause() {
        loader.sendCommand(MRMediaRemoteCommand.pause)
    }
    
    func togglePlayPause() {
        loader.sendCommand(MRMediaRemoteCommand.togglePlayPause)
    }
    
    func nextTrack() {
        loader.sendCommand(MRMediaRemoteCommand.nextTrack)
    }
    
    func previousTrack() {
        loader.sendCommand(MRMediaRemoteCommand.previousTrack)
    }
    
    func seek(to time: TimeInterval) {
        loader.setElapsedTime(time)
    }
    
    func setVolume(_ volume: Float) {
        loader.setVolume(volume)
    }
    
    private func fetchNowPlayingInfo() {
        loader.getNowPlayingInfo(DispatchQueue.main) { [weak self] info in
            guard let self = self, let info = info else { return }
            
            let title = self.getStringValue(from: info, key: self.loader.kMRMediaRemoteNowPlayingInfoTitle)
            let artist = self.getStringValue(from: info, key: self.loader.kMRMediaRemoteNowPlayingInfoArtist)
            let album = self.getStringValue(from: info, key: self.loader.kMRMediaRemoteNowPlayingInfoAlbum)
            let duration = self.getDoubleValue(from: info, key: self.loader.kMRMediaRemoteNowPlayingInfoDuration)
            let elapsed = self.getDoubleValue(from: info, key: self.loader.kMRMediaRemoteNowPlayingInfoElapsedTime)
            let playbackRate = self.getDoubleValue(from: info, key: self.loader.kMRMediaRemoteNowPlayingInfoPlaybackRate)
            let isPlaying = playbackRate > 0
            
            var artwork: NSImage? = nil
            if let artworkData = info[self.loader.kMRMediaRemoteNowPlayingInfoArtworkData ?? ""] as? Data {
                artwork = NSImage(data: artworkData)
            }
            
            let nowPlaying = NowPlayingInfo(
                title: title,
                artist: artist,
                album: album,
                artwork: artwork,
                duration: duration,
                elapsedTime: elapsed,
                isPlaying: isPlaying
            )
            
            self.nowPlayingSubject.send(nowPlaying)
            self.isPlayingSubject.send(isPlaying)
        }
    }
    
    private func getStringValue(from dict: [String: Any], key: String?) -> String {
        guard let key = key else { return "" }
        return dict[key] as? String ?? ""
    }
    
    private func getDoubleValue(from dict: [String: Any], key: String?) -> Double {
        guard let key = key else { return 0 }
        return (dict[key] as? NSNumber)?.doubleValue ?? 0
    }
}
