import SwiftUI

/// Compact playing indicator that sits beside the physical notch without
/// opening the island downward. The clear center is supplied by the shape.
struct CollapsedPlaybackActivity: View {
    @Bindable var appState: AppState
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                CompactPlaybackBars(isPlaying: appState.isPlaying, mirrored: false)
            }
            .frame(maxWidth: .infinity)
            .padding(.trailing, 8)

            Color.clear.frame(width: notchWidth)

            HStack {
                CompactPlaybackBars(isPlaying: appState.isPlaying, mirrored: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, 8)
        }
        .frame(maxHeight: .infinity)
        .padding(.vertical, 7)
        .allowsHitTesting(false)
    }
}

private struct CompactPlaybackBars: View {
    let isPlaying: Bool
    let mirrored: Bool
    @State private var pulsing = false

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(isPlaying ? 0.9 : 0.35))
                    .frame(width: 3, height: height(for: index))
                    .animation(
                        isPlaying
                            ? .easeInOut(duration: 0.5 + Double(index) * 0.08)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.1)
                            : .easeOut(duration: 0.16),
                        value: pulsing
                    )
            }
        }
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        .frame(width: 18, height: 24)
        .onAppear { pulsing = isPlaying }
        .onChange(of: isPlaying) { _, value in pulsing = value }
    }

    private func height(for index: Int) -> CGFloat {
        guard isPlaying, pulsing else { return 4 }
        return [10, 18, 13][index]
    }
}
