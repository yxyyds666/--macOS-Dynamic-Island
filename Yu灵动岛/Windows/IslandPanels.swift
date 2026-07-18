import SwiftUI
import UniformTypeIdentifiers

// MARK: - Music (left side), iOS Now-Playing style.

struct MusicPanel: View {
    @Bindable var appState: AppState
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0

    private var displayTime: TimeInterval { isScrubbing ? scrubTime : appState.currentTime }
    private var fraction: CGFloat {
        guard appState.duration > 0 else { return 0 }
        return CGFloat(min(max(0, displayTime / appState.duration), 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.songTitle.isEmpty ? "未在播放" : appState.songTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(appState.artistName.isEmpty ? "打开任意音乐 App" : appState.artistName)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            // Scrubber
            VStack(spacing: 5) {
                GeometryReader { geo in
                    let w = geo.size.width
                    Capsule()
                        .fill(.white.opacity(0.18))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white).frame(width: w * fraction)
                        }
                        .frame(height: 6)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    isScrubbing = true
                                    scrubTime = Double(min(max(0, v.location.x / w), 1)) * appState.duration
                                }
                                .onEnded { _ in
                                    appState.seek(to: scrubTime)
                                    isScrubbing = false
                                }
                        )
                }
                .frame(height: 6)

                HStack {
                    Text(formatTime(displayTime))
                    Spacer()
                    Text(formatTime(appState.duration))
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            }

            // Transport
            HStack(spacing: 34) {
                Spacer(minLength: 0)
                controlButton("backward.fill", size: 18) { appState.previousTrack() }
                controlButton(appState.isPlaying ? "pause.fill" : "play.fill", size: 30) { appState.togglePlayPause() }
                controlButton("forward.fill", size: 18) { appState.nextTrack() }
                Spacer(minLength: 0)
            }

            // Volume
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                Slider(value: Binding(get: { Double(appState.volume) }, set: { appState.setVolume(Float($0)) }), in: 0...1)
                    .tint(.white)
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let art = appState.albumArt {
                Image(nsImage: art).resizable()
            } else {
                RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.1))
                    .overlay(Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(.white.opacity(0.35)))
            }
        }
        .frame(width: 66, height: 66)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func controlButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .medium)).foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: - Files (right side), iOS-style square tiles.

struct FilePanel: View {
    @Bindable var appState: AppState
    @State private var isTargeted = false

    private let columns = [GridItem(.adaptive(minimum: 68), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("文件中转站")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(appState.fileItems.count)/\(AppConstants.maxFileItems)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                if !appState.fileItems.isEmpty {
                    Button { appState.clearAllFiles() } label: {
                        Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(.red.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .overlay(
                        // Dashed outline only while a drag is hovering over it.
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .foregroundStyle(.white.opacity(isTargeted ? 0.5 : 0))
                    )

                if appState.fileItems.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.3))
                        Text("拖拽文件到此")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(appState.fileItems) { item in
                                FileTile(item: item) {
                                    if let i = appState.fileItems.firstIndex(where: { $0.id == item.id }) {
                                        appState.removeFile(at: i)
                                    }
                                }
                                .onDrag { NSItemProvider(object: item.url as NSURL) }
                            }
                        }
                        .padding(10)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isTargeted)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { appState.addFile(FileItem(url: url)) }
            }
            handled = true
        }
        return handled
    }
}

/// A single square file tile: icon on top, name below, with a delete badge.
private struct FileTile: View {
    let item: FileItem
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: item.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: 68, height: 72)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(hovering ? 0.16 : 0.09))
        )
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .onHover { hovering = $0 }
    }
}
