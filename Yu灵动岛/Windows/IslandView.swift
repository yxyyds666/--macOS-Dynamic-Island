import SwiftUI

/// The island's SwiftUI content. Four states:
///   • idle     — black pill blended into the notch
///   • hover    — a subtle bulge around the notch (no content)
///   • peek      — music player drapes straight down out of the notch
///   • expanded — a wide bar wrapping AROUND the notch: music in the left wing,
///                files in the right wing, the physical notch showing through
///                a cutout in the middle. iOS-styled.
/// The window owns the size/animation; this view just fills it.
struct IslandView: View {
    @Bindable var appState: AppState

    private var mode: IslandMode { appState.islandMode }

    /// Real notch dimensions, used to size the expanded cutout.
    private var notchWidth: CGFloat { NSScreen.main?.notchWidth ?? AppConstants.notchWidth }
    private var notchHeight: CGFloat { NSScreen.main?.notchHeight ?? AppConstants.notchHeight }

    private var topCornerRadius: CGFloat {
        mode == .idle ? AppConstants.notchCornerRadius : AppConstants.islandTopCornerRadius
    }

    private var bottomCornerRadius: CGFloat {
        switch mode {
        case .idle: return AppConstants.notchCornerRadius
        case .hover, .peek: return AppConstants.islandCornerRadius
        case .expanded: return AppConstants.expandPanelCornerRadius
        }
    }

    /// The shape for the current mode. Expanded wraps around the notch; every
    /// other mode is the single notch-hugging pill/drape.
    @ViewBuilder
    private func background(_ fill: some ShapeStyle) -> some View {
        if mode == .expanded {
            ExpandedNotchShape(notchCutoutWidth: notchWidth, notchCutoutHeight: notchHeight)
                .fill(fill)
        } else {
            NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
                .fill(fill)
        }
    }

    private var clip: AnyShape {
        if mode == .expanded {
            return AnyShape(ExpandedNotchShape(notchCutoutWidth: notchWidth, notchCutoutHeight: notchHeight))
        } else {
            return AnyShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius))
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            background(.black)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Clip to the shape so content stays within the island / cutout.
        .clipShape(clip)
        .contentShape(clip)
        .onTapGesture {
            // Any state → click commits to the full wrap-around layout.
            if mode != .expanded { appState.expand() }
        }
        .animation(.easeInOut(duration: 0.18), value: mode)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .idle, .hover:
            // Idle and the hover bulge show no content.
            EmptyView()
        case .peek:
            // Dwell reveals the music player, draping down out of the notch.
            MusicPanel(appState: appState)
                .padding(.top, notchHeight - 8)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
        case .expanded:
            // Music in the left wing, files in the right wing, with the notch
            // cutout kept clear between them.
            HStack(spacing: 0) {
                // Left wing fills the space left of the notch.
                Group {
                    if appState.showMusicModule {
                        MusicPanel(appState: appState)
                            .padding(.horizontal, 12)
                    }
                }
                .frame(maxWidth: .infinity)
                // Keep the physical notch clear between the wings.
                Color.clear.frame(width: notchWidth)
                // Right wing fills the space right of the notch.
                Group {
                    if appState.showFileModule {
                        FilePanel(appState: appState)
                            .padding(.horizontal, 12)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, notchHeight + 8)
            .padding(.bottom, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
