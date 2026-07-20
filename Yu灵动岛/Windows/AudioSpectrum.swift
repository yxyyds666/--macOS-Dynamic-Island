import SwiftUI

/// A decorative audio-spectrum, boring.notch style. MediaRemote does not expose
/// real spectrum data, so the bars are driven by layered sine waves — they dance
/// while playing and rest flat when paused. Purely cosmetic.
struct AudioSpectrumView: View {
    var isPlaying: Bool
    var barCount: Int = 4
    var maxHeight: CGFloat = 16

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(.white.opacity(isPlaying ? 0.9 : 0.4))
                        .frame(width: 2.5, height: barHeight(i, t))
                }
            }
            .frame(height: maxHeight, alignment: .center)
            .animation(.easeOut(duration: 0.12), value: isPlaying)
        }
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
