import Foundation
import Combine

protocol MediaServiceProtocol: AnyObject {
    var nowPlayingPublisher: AnyPublisher<NowPlayingInfo, Never> { get }
    var isPlayingPublisher: AnyPublisher<Bool, Never> { get }
    
    func play()
    func pause()
    func togglePlayPause()
    func nextTrack()
    func previousTrack()
    func seek(to time: TimeInterval)
    @discardableResult func setVolume(_ volume: Float) -> Bool
    
    func startListening()
    func stopListening()
}
