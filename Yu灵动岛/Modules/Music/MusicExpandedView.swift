import SwiftUI

struct MusicExpandedView: View {
    @Bindable var appState: AppState
    @State private var isDraggingProgress = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Album art + info
            HStack(spacing: 12) {
                if let art = appState.albumArt {
                    Image(nsImage: art)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.1))
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundStyle(.white.opacity(0.4))
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.songTitle.isEmpty ? "未在播放" : appState.songTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(appState.artistName.isEmpty ? "打开任意音乐 App 开始播放" : appState.artistName)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                
                Spacer()
            }
            
            // Playback controls
            HStack(spacing: 20) {
                Button(action: { }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                
                Button(action: { }) {
                    Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24))
                }
                .buttonStyle(.plain)
                
                Button(action: { }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            
            // Progress bar
            VStack(spacing: 4) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white.opacity(0.2))
                            .frame(height: 4)
                        
                        // Progress fill
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white)
                            .frame(
                                width: geometry.size.width * appState.currentTime / max(appState.duration, 1),
                                height: 4
                            )
                    }
                }
                .frame(height: 4)
                
                HStack {
                    Text(formatTime(appState.currentTime))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("-\(formatTime(appState.duration - appState.currentTime))")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            
            // Lyrics (if available)
            if !appState.lyrics.isEmpty {
                VStack(spacing: 6) {
                    ForEach(appState.lyrics.prefix(5), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxHeight: 120)
            }
        }
        .padding(16)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
