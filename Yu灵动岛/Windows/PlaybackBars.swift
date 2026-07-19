import SwiftUI

struct PlaybackBars: View {
    let isPlaying: Bool
    @State private var pulsing = false

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(isPlaying ? 0.8 : 0.4))
                    .frame(width: 2.5, height: barHeight(index))
                    .animation(
                        isPlaying
                            ? .easeInOut(duration: 0.45 + Double(index) * 0.08).repeatForever(autoreverses: true).delay(Double(index) * 0.09)
                            : .easeOut(duration: 0.15),
                        value: pulsing
                    )
            }
        }
        .frame(width: 12, height: 18)
        .onAppear { pulsing = isPlaying }
        .onChange(of: isPlaying) { _, playing in pulsing = playing }
    }

    private func barHeight(_ index: Int) -> CGFloat {
        guard isPlaying, pulsing else { return 5 }
        return [12, 17, 9][index]
    }
}
