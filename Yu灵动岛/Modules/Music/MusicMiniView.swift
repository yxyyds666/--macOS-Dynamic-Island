import SwiftUI

struct MusicMiniView: View {
    @Bindable var appState: AppState
    
    var body: some View {
        HStack(spacing: 6) {
            if appState.hasMediaPlaying {
                // Album art thumbnail
                if let art = appState.albumArt {
                    Image(nsImage: art)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                
                // Song info
                Text(appState.songTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 50)
                
                // Controls
                HStack(spacing: 8) {
                    Button(action: { appState.isPlaying = false }) {
                        Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {}) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white)
            } else {
                // No media state
                Image(systemName: "music.note")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                
                Text("未在播放")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: AppConstants.notchHeight)
    }
}
