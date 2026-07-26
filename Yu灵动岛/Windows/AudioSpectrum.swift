import SwiftUI

/// A decorative audio-spectrum, boring.notch style. MediaRemote does not expose
/// real spectrum data, so the bars are driven by layered sine waves — they dance
/// while playing and rest flat when paused. Purely cosmetic.
struct AudioSpectrumView: View {
    var isPlaying: Bool
    var barCount: Int = 4
    var maxHeight: CGFloat = 16

    private let barWidth: CGFloat = 2.5
    private let barSpacing: CGFloat = 2.5

    var body: some View {
        // This animation runs the whole time music plays — the single largest
        // steady-state cost in the app — so it is tuned twice over: 15 fps
        // (the ~2.5 pt bars stay fluid; each tick costs a full CA transaction
        // flush regardless of how little changed), and a single Canvas redraw
        // per tick instead of per-bar SwiftUI views with their own layers.
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !isPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let color = Color.white.opacity(isPlaying ? 0.9 : 0.4)
                var x = (size.width - intrinsicWidth) / 2
                for i in 0..<barCount {
                    let h = barHeight(i, t)
                    let rect = CGRect(x: x, y: (size.height - h) / 2, width: barWidth, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
                    x += barWidth + barSpacing
                }
            }
            .frame(width: intrinsicWidth, height: maxHeight)
        }
    }

    private var intrinsicWidth: CGFloat {
        CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
    }

    private func barHeight(_ i: Int, _ t: Double) -> CGFloat {
        let floor: CGFloat = maxHeight * 0.28
        guard isPlaying else { return floor }
        let phase = t * 7 + Double(i) * 1.35
        let n = (sin(phase) + sin(phase * 1.7 + 0.6)) / 2  // -1...1
        return floor + CGFloat((n + 1) / 2) * (maxHeight - floor)
    }
}

/// The album artwork, shared across every music state so it can morph smoothly
/// between them via `matchedGeometryEffect`. Pass the same `namespace` from the
/// owning `IslandView` in each state and SwiftUI interpolates position + size as
/// the island grows/shrinks.
struct IslandArtwork: View {
    let appState: AppState
    var size: CGFloat
    var cornerRadius: CGFloat
    var namespace: Namespace.ID?

    /// Below this edge length the source badge would just be noise.
    private var showsSourceBadge: Bool { size >= 40 }
    private var badgeSide: CGFloat { min(size * 0.3, 28) }

    var body: some View {
        Group {
            if let art = appState.albumArt {
                Image(nsImage: art).resizable()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(0.1))
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.34))
                            .foregroundStyle(.white.opacity(0.35))
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            // Source-app badge. macOS app icons carry their own shape and
            // transparent margins, so render as-is — no extra clipping.
            if showsSourceBadge, let icon = appState.sourceAppIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: badgeSide, height: badgeSide)
                    .shadow(color: .black.opacity(0.55), radius: 2, y: 0.5)
                    .padding(size * 0.03)
            }
        }
        .modifier(OptionalMatchedGeometry(id: "albumArt", namespace: namespace))
    }
}

/// Applies `matchedGeometryEffect` only when a namespace is supplied, so the same
/// artwork view also works in previews / places without a shared namespace.
private struct OptionalMatchedGeometry: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// The always-on playing state (track playing, mouse NOT over the notch):
/// album art in the left wing, dancing spectrum bars in the right wing, the
/// physical notch showing through the middle. boring.notch style.
struct PlayingCapsule: View {
    @Bindable var appState: AppState
    let notchWidth: CGFloat
    var namespace: Namespace.ID?

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                IslandArtwork(
                    appState: appState,
                    size: AppConstants.playingArtworkSize,
                    cornerRadius: 5,
                    namespace: namespace
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.trailing, 8)

            Color.clear.frame(width: notchWidth)

            HStack {
                AudioSpectrumView(isPlaying: appState.isPlaying)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, 10)
        }
        .frame(maxHeight: .infinity)
        .padding(.vertical, 6)
        .allowsHitTesting(false)
    }
}
