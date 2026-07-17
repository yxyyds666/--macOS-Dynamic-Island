import AppKit

struct NowPlayingInfo: Equatable {
    let title: String
    let artist: String
    let album: String
    let artwork: NSImage?
    let duration: TimeInterval
    let elapsedTime: TimeInterval
    let isPlaying: Bool
    
    static let empty = NowPlayingInfo(
        title: "",
        artist: "",
        album: "",
        artwork: nil,
        duration: 0,
        elapsedTime: 0,
        isPlaying: false
    )
    
    var hasArtwork: Bool {
        artwork != nil
    }
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return elapsedTime / duration
    }
    
    var formattedElapsed: String {
        formatTime(elapsedTime)
    }
    
    var formattedRemaining: String {
        formatTime(duration - elapsedTime)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
