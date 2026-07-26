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
    /// Shared namespace so the album artwork morphs in from the collapsed states.
    var namespace: Namespace.ID?
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0
    @State private var artworkBreathing = false

    private var displayTime: TimeInterval { isScrubbing ? scrubTime : appState.currentTime }
    private var fraction: CGFloat {
        guard appState.duration > 0 else { return 0 }
        return CGFloat(min(max(0, displayTime / appState.duration), 1))
    }

    var body: some View {
        if showVolume {
            expandedBody
        } else {
            compactBody
        }
    }

    // MARK: - Expanded (full tab panel, boring.notch style)

    private var expandedBody: some View {
        VStack(spacing: 12) {
            // ── Top row: artwork (left) + lyrics (right), boring.notch style ──
            // Lyrics greedily fill the leftover space; the bottom rows get a
            // higher layout priority so they are never compressed or clipped.
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 8) {
                    IslandArtwork(
                        appState: appState,
                        size: 104,
                        cornerRadius: 16,
                        namespace: namespace
                    )
                    .scaleEffect(artworkBreathing ? 1.022 : 1)
                    .modifier(OpenSourceOnTap(appState: appState))

                    // Title + artist under the artwork.
                    VStack(spacing: 3) {
                        Text(appState.songTitle.isEmpty ? "未在播放" : appState.songTitle)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(appState.artistName.isEmpty ? "打开任意音乐 App" : appState.artistName)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    .frame(width: 104)
                }

                // Lyrics fill the space to the right of the artwork.
                LyricsPanel(appState: appState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            // ── Scrubber ──────────────────────────────────────────────────
            VStack(spacing: 4) {
                GeometryReader { geo in
                    let w = geo.size.width
                    Capsule()
                        .fill(.white.opacity(0.18))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white).frame(width: w * fraction)
                        }
                        .frame(height: 4)
                        .contentShape(Rectangle().inset(by: -8))
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
                .frame(height: 4)
                HStack {
                    Text(formatTime(displayTime))
                    Spacer()
                    Text(formatTime(appState.duration))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            }
            .layoutPriority(1)

            // ── Bottom row: transport controls (left) + volume (right) ──────
            HStack(spacing: 18) {
                HStack(spacing: 26) {
                    controlButton("backward.fill", size: 18) { appState.previousTrack() }
                    controlButton(appState.isPlaying ? "pause.fill" : "play.fill", size: 30) { appState.togglePlayPause() }
                    controlButton("forward.fill", size: 18) { appState.nextTrack() }
                }

                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                    Slider(value: Binding(get: { Double(appState.volume) }, set: { appState.setVolume(Float($0)) }), in: 0...1)
                        .tint(.white)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity)
            }
            .layoutPriority(1)
        }
        .frame(maxHeight: .infinity)
        .opacity(focused ? 1 : 0.62)
        .onAppear {
            appState.syncVolumeFromSystem()
            syncArtworkAnimation()
        }
        .onChange(of: appState.isPlaying) { _, _ in syncArtworkAnimation() }
        .onChange(of: appState.songTitle) { _, _ in artworkBreathing = false; syncArtworkAnimation() }
    }

    // MARK: - Compact (peek drape)

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            HStack(spacing: 28) {
                Spacer(minLength: 0)
                controlButton("backward.fill", size: 16) { appState.previousTrack() }
                controlButton(appState.isPlaying ? "pause.fill" : "play.fill", size: 25) { appState.togglePlayPause() }
                controlButton("forward.fill", size: 16) { appState.nextTrack() }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
        .opacity(focused ? 1 : 0.62)
        .onAppear { syncArtworkAnimation() }
        .onChange(of: appState.isPlaying) { _, _ in syncArtworkAnimation() }
        .onChange(of: appState.songTitle) { _, _ in artworkBreathing = false; syncArtworkAnimation() }
    }

    private func syncArtworkAnimation() {
        let active = appState.artworkBreathing && appState.isPlaying && !appState.songTitle.isEmpty
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
        let side: CGFloat = compact ? 58 : 66
        IslandArtwork(
            appState: appState,
            size: side,
            cornerRadius: 12,
            namespace: namespace
        )
        .scaleEffect(artworkBreathing ? 1.025 : 1)
        .frame(width: side + 8, height: side + 8)
        .modifier(OpenSourceOnTap(appState: appState))
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
    var isDragTarget: Bool = false
    @State private var isTargeted = false

    private var dropActive: Bool { isTargeted || isDragTarget }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
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

            // boring.notch shelf style: a dashed rounded "tray" that holds either
            // an empty-state prompt or a horizontally-scrolling row of file tiles.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    dropActive ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.12),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [10, 6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.05))
                )
                .overlay { trayContent }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.15), value: dropActive)
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    handleDrop(providers)
                }
        }
    }

    @ViewBuilder
    private var trayContent: some View {
        if let feedback = appState.fileDropFeedback {
            Text(feedback.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(feedback.isError ? .orange : .green)
                .lineLimit(1)
                .padding(.horizontal, 12)
        } else if appState.fileItems.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down")
                    .symbolVariant(.fill)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.55))
                Text("拖拽文件到此")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
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
            .scrollIndicators(.never)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        // Providers resolve asynchronously; gather every URL, then add them in a
        // single call so the feedback is one aggregated message (not N "added 1
        // file" toasts) and ordering is stable.
        let group = DispatchGroup()
        let box = URLBox()
        for (index, provider) in providers.enumerated() {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { box.set(index, url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = box.ordered()
            guard !urls.isEmpty else { return }
            _ = appState.addFiles(urls)
        }
        return true
    }
}

/// Collects URLs from concurrent provider callbacks by original index so the
/// dropped order is preserved regardless of which provider resolves first.
private final class URLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [Int: URL] = [:]

    func set(_ index: Int, _ url: URL) {
        lock.lock(); urls[index] = url; lock.unlock()
    }

    func ordered() -> [URL] {
        lock.lock(); defer { lock.unlock() }
        return urls.sorted { $0.key < $1.key }.map(\.value)
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

    /// User-adjustable text scale (settings → 歌词字号).
    private var scale: CGFloat { CGFloat(max(0.5, appState.lyricsFontScale)) }

    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            if case .failed = appState.lyricsState {
                Button("重试") { appState.requestLyricsRetry() }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
            }
            Group {
                switch appState.lyricsState {
                case .idle: status("播放歌曲后加载歌词")
                case .loading: HStack(spacing: 6) { ProgressView().controlSize(.small); Text("正在加载歌词…") }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                case .failed: status("歌词加载失败")
                case .notFound: status("暂无歌词")
                case .plain(let text): ScrollView { Text(text).font(.system(size: 11 * scale)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).frame(maxWidth: .infinity, alignment: .center).padding(6) }
                case .synced(let lines): synced(lines)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @ViewBuilder private func synced(_ lines: [LyricLine]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .center, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        let active = index == appState.currentLyricIndex
                        Text(line.text).font(.system(size: (active ? 13 : 11) * scale, weight: active ? .semibold : .regular))
                            .foregroundStyle(.white.opacity(active ? 1 : 0.42)).frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 9).padding(.vertical, 3 * scale)
                            .contentShape(Rectangle()).id(line.id).onTapGesture { appState.seek(to: line.time) }
                    }
                }.padding(.vertical, 6)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in isUserScrolling = true }.onEnded { _ in isUserScrolling = false })
            .onChange(of: appState.currentLyricIndex) { _, index in
                guard !isUserScrolling, lines.indices.contains(index) else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(lines[index].id, anchor: .center) }
            }
            .task { guard lines.indices.contains(appState.currentLyricIndex) else { return }; proxy.scrollTo(lines[appState.currentLyricIndex].id, anchor: .center) }
        }
    }

    private func status(_ text: String) -> some View { Text(text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).multilineTextAlignment(.center).frame(maxWidth: .infinity, alignment: .center).padding(8) }
}

// MARK: - Activity capsule

struct ActivityCapsule: View {
    @Bindable var appState: AppState
    let activityContent: ActivityContent?
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    var isPinned: Bool = false
    var namespace: Namespace.ID? = nil
    @State private var artworkBreathing = false

    var body: some View {
        HStack(spacing: 0) {
            HStack { Spacer(minLength: 0); artwork }.frame(maxWidth: .infinity).padding(.trailing, 12)
            Color.clear.frame(width: notchWidth)
            HStack {
                rightContent
                Spacer(minLength: 0)
                if isPinned { pinBadge }
            }
            .frame(maxWidth: .infinity).padding(.leading, 12)
        }
        .frame(maxHeight: .infinity)
        .padding(.top, max(0, notchHeight - AppConstants.islandActivityHeight + 6)).padding(.bottom, 6)
        .animation(.smooth(duration: 0.18), value: isPinned)
        .onAppear { syncCapsuleAnimation() }
        .onChange(of: appState.isPlaying) { _, _ in syncCapsuleAnimation() }
    }

    private var pinBadge: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55))
            .rotationEffect(.degrees(45))
            .padding(.trailing, 4)
            .transition(.opacity.combined(with: .scale(scale: 0.6)))
            .help("已固定，右键取消")
    }

    private func syncCapsuleAnimation() {
        let active = appState.artworkBreathing && appState.isPlaying && !appState.songTitle.isEmpty && activityContent == .lyrics
        if active {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                artworkBreathing = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.18)) { artworkBreathing = false }
        }
    }

    @ViewBuilder private var artwork: some View {
        IslandArtwork(
            appState: appState,
            size: 38,
            cornerRadius: 8,
            namespace: namespace
        )
        .frame(width: 44, height: 44)
    }

    @ViewBuilder private var rightContent: some View {
        switch activityContent {
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

// MARK: - Open-source-app tap

/// Clicking the artwork brings the media's source app forward. Inert when the
/// source is unknown, so the artwork stays a plain image in that case.
struct OpenSourceOnTap: ViewModifier {
    let appState: AppState

    func body(content: Content) -> some View {
        if appState.sourceBundleID != nil {
            content
                .contentShape(Rectangle())
                .onTapGesture { appState.openMusicSource() }
                .pointerStyle(.link)
                .help("在「\(appState.sourceAppName ?? "来源应用")」中打开")
        } else {
            content
        }
    }
}
