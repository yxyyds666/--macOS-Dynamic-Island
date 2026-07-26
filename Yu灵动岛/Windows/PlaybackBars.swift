import SwiftUI

/// Compact three-bar playback indicator (hover capsule, next to the lyric
/// preview). Driven by wall-clock sine waves via TimelineView, same engine as
/// `AudioSpectrumView`: the phase is a pure function of absolute time, so the
/// container re-rendering twice a second with playback progress — or the
/// lyric-line `.animation(value:)` transaction — cannot restart or corrupt the
/// motion the way a repeatForever implicit animation can.
struct PlaybackBars: View {
    let isPlaying: Bool

    var body: some View {
        // Same Canvas-per-tick approach as AudioSpectrumView: one redraw per
        // frame instead of three view layouts + layer commits.
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let color = Color.white.opacity(isPlaying ? 0.8 : 0.4)
                let barWidth: CGFloat = 2.5, spacing: CGFloat = 2.0
                var x = (size.width - (3 * barWidth + 2 * spacing)) / 2
                for index in 0..<3 {
                    let h = barHeight(index, t)
                    let rect = CGRect(x: x, y: (size.height - h) / 2, width: barWidth, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
                    x += barWidth + spacing
                }
            }
        }
        .frame(width: 12, height: 18)
    }

    private func barHeight(_ index: Int, _ t: Double) -> CGFloat {
        let floor: CGFloat = 5
        guard isPlaying else { return floor }
        let phase = t * 6.5 + Double(index) * 1.4
        let n = (sin(phase) + sin(phase * 1.9 + 0.7)) / 2  // -1...1
        return floor + CGFloat((n + 1) / 2) * (17 - floor)
    }
}
