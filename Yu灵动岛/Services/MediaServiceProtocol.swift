import Foundation
import Combine

protocol MediaServiceProtocol {
    var nowPlayingPublisher: AnyPublisher<NowPlayingInfo, Never> { get }
    var isPlayingPublisher: AnyPublisher<Bool, Never> { get }
    
    func play()
    func pause()
    func togglePlayPause()
    func nextTrack()
    func previousTrack()
    func seek(to time: TimeInterval)
    func setVolume(_ volume: Float)
    
    func startListening()
    func stopListening()
}
