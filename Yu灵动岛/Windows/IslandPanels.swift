import SwiftUI
import UniformTypeIdentifiers

// MARK: - Music (left side), iOS Now-Playing style.

struct MusicPanel: View {
    @Bindable var appState: AppState
    /// The volume slider only shows in the full expanded layout; the peek drape
    /// hides it to stay compact.
    var showVolume: Bool = false
    var compact: Bool = false
    var focused: Bool = true
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0
    @State private var artworkBreathing = false

    private var displayTime: TimeInterval { isScrubbing ? scrubTime : appState.currentTime }
    private var fraction: CGFloat {
        guard appState.duration > 0 else { return 0 }
        return CGFloat(min(max(0, displayTime / appState.duration), 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 14) {
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

            if !compact {
                HStack(spacing: 34) {
                    Spacer(minLength: 0)
                    controlButton("backward.fill", size: 18) { appState.previousTrack() }
                    controlButton(appState.isPlaying ? "pause.fill" : "play.fill", size: 30) { appState.togglePlayPause() }
                    controlButton("forward.fill", size: 18) { appState.nextTrack() }
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 28) {
                    Spacer(minLength: 0)
                    controlButton("backward.fill", size: 16) { appState.previousTrack() }
                    controlButton(appState.isPlaying ? "pause.fill" : "play.fill", size: 25) { appState.togglePlayPause() }
                    controlButton("forward.fill", size: 16) { appState.nextTrack() }
                    Spacer(minLength: 0)
                }
            }

            // Volume and full lyrics only in expanded layout.
            if showVolume {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    Slider(value: Binding(get: { Double(appState.volume) }, set: { appState.setVolume(Float($0)) }), in: 0...1)
                        .tint(.white)
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
                LyricsPanel(appState: appState).frame(height: 92)
            }

            Spacer(minLength: 0)
        }
        .opacity(focused ? 1 : 0.62)
        .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.8, blendDuration: 0.08), value: focused)
        .onAppear {
            if showVolume { appState.syncVolumeFromSystem() }
            syncArtworkAnimation()
        }
        .onChange(of: appState.isPlaying) { _, _ in syncArtworkAnimation() }
        .onChange(of: appState.songTitle) { _, _ in
            artworkBreathing = false
            syncArtworkAnimation()
        }
    }

    private func syncArtworkAnimation() {
        let active = appState.isPlaying && !appState.songTitle.isEmpty
        if active {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                artworkBreathing = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                artworkBreathing = false
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(artworkBreathing ? 0.11 : 0))
                .frame(width: 74, height: 74)
                .blur(radius: 5)
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
            .scaleEffect(artworkBreathing ? 1.025 : 1)
        }
        .frame(width: 74, height: 74)
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
    var compact: Bool = false
    var focused: Bool = true
    @State private var isTargeted = false

    private let columns = [GridItem(.adaptive(minimum: 68), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
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
                            .foregroundStyle(.white.opacity((isTargeted || appState.isDragTarget) ? 0.5 : 0))
                    )

                if let feedback = appState.fileDropFeedback {
                    Text(feedback.message).font(.system(size: 11, weight: .medium)).foregroundStyle(feedback.isError ? .orange : .green).lineLimit(1)
                } else if appState.fileItems.isEmpty {
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
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { _ = appState.addFiles([url]) }
            }
        }
        return !providers.isEmpty
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
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .contextMenu {
            Button("打开") { NSWorkspace.shared.open(item.url) }
            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("复制路径") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.url.path, forType: .string) }
            Divider()
            Button("移除", role: .destructive, action: onRemove)
        }
        .onHover { hovering = $0 }
    }
}


/// Full expanded lyrics area. Synced lines are clickable to seek and auto-follow.
private struct LyricsPanel: View {
    @Bindable var appState: AppState
    @State private var isUserScrolling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("歌词").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.65))
                Spacer()
                if case .failed = appState.lyricsState {
                    Button("重试") { appState.requestLyricsRetry() }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
                }
            }
            Group {
                switch appState.lyricsState {
                case .idle: status("播放歌曲后加载歌词")
                case .loading: HStack(spacing: 6) { ProgressView().controlSize(.small); Text("正在加载歌词…") }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                case .failed: status("歌词加载失败")
                case .notFound: status("暂无歌词")
                case .plain(let text): ScrollView { Text(text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity, alignment: .leading).padding(6) }
                case .synced(let lines): synced(lines)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @ViewBuilder private func synced(_ lines: [LyricLine]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        let active = index == appState.currentLyricIndex
                        Text(line.text).font(.system(size: active ? 12 : 11, weight: active ? .semibold : .regular))
                            .foregroundStyle(.white.opacity(active ? 1 : 0.42)).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(active ? .white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle()).id(line.id).onTapGesture { appState.seek(to: line.time) }
                    }
                }.padding(6)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in isUserScrolling = true }.onEnded { _ in isUserScrolling = false })
            .onChange(of: appState.currentLyricIndex) { _, index in
                guard !isUserScrolling, lines.indices.contains(index) else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(lines[index].id, anchor: .center) }
            }
            .task { guard lines.indices.contains(appState.currentLyricIndex) else { return }; proxy.scrollTo(lines[appState.currentLyricIndex].id, anchor: .center) }
        }
    }

    private func status(_ text: String) -> some View { Text(text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).padding(8) }
}

// MARK: - Activity capsule

struct ActivityCapsule: View {
    @Bindable var appState: AppState
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    @State private var artworkBreathing = false

    var body: some View {
        HStack(spacing: 0) {
            HStack { Spacer(minLength: 0); artwork }.frame(maxWidth: .infinity).padding(.trailing, 12)
            Color.clear.frame(width: notchWidth)
            HStack { rightContent; Spacer(minLength: 0) }.frame(maxWidth: .infinity).padding(.leading, 12)
        }
        .frame(maxHeight: .infinity)
        .padding(.top, max(0, notchHeight - AppConstants.islandActivityHeight + 6)).padding(.bottom, 6)
        .onAppear { syncCapsuleAnimation() }
        .onChange(of: appState.isPlaying) { _, _ in syncCapsuleAnimation() }
    }

    private func syncCapsuleAnimation() {
        let active = appState.isPlaying && !appState.songTitle.isEmpty && appState.activityContent == .lyrics
        if active {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                artworkBreathing = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.18)) { artworkBreathing = false }
        }
    }

    @ViewBuilder private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(artworkBreathing ? 0.12 : 0))
                .frame(width: 44, height: 44)
                .blur(radius: 3)
            Group { if let art = appState.albumArt { Image(nsImage: art).resizable() } else { RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.12)).overlay(Image(systemName: "music.note").font(.system(size: 14)).foregroundStyle(.white.opacity(0.4))) } }
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .scaleEffect(artworkBreathing ? 1.025 : 1)
        }
        .frame(width: 44, height: 44)
    }

    @ViewBuilder private var rightContent: some View {
        switch appState.activityContent {
        case .lyrics: lyricsPreview
        case .trackInfo, .none: trackInfo
        }
    }

    @ViewBuilder private var lyricsPreview: some View {
        switch appState.lyricsState {
        case .loading: Text("正在加载歌词…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
        case .failed: Text("歌词加载失败").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
        case .plain(let text): Text(text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(2).joined(separator: "\n")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
        case .synced(let lines):
            let i = appState.currentLyricIndex
            HStack(spacing: 7) {
                PlaybackBars(isPlaying: appState.isPlaying)
                VStack(alignment: .leading, spacing: 2) {
                    Text(i >= 0 && i < lines.count ? lines[i].text : "♪").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(2).id(i)
                    if i + 1 < lines.count { Text(lines[i + 1].text).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).lineLimit(1) }
                }
            }.animation(.easeInOut(duration: 0.25), value: i)
        case .idle, .notFound: Text("暂无歌词").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
        }
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(appState.songTitle.isEmpty ? "未在播放" : appState.songTitle).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).lineLimit(1)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
        }
    }

    private var subtitle: String {
        if !appState.artistName.isEmpty && !appState.albumName.isEmpty { return "\(appState.artistName) · \(appState.albumName)" }
        return appState.artistName.isEmpty ? appState.albumName : appState.artistName
    }
}
