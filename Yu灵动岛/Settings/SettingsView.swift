import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let onClose: () -> Void
    @State private var selectedTab = "general"

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: "general") {
                    Label("通用", systemImage: "gear")
                }
                NavigationLink(value: "modules") {
                    Label("模块", systemImage: "square.grid.2x2")
                }
                NavigationLink(value: "about") {
                    Label("关于", systemImage: "info.circle")
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(160)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch selectedTab {
                case "general":  GeneralSettingsView(onClose: onClose)
                case "modules":  ModuleSettingsView()
                case "about":    AboutView()
                default:         GeneralSettingsView(onClose: onClose)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .formStyle(.grouped)
        .frame(width: 560, height: 400)
    }
}

// MARK: - 通用

private struct GeneralSettingsView: View {
    let onClose: () -> Void
    private let settings = SettingsManager.shared

    @State private var loginStatus: SettingsManager.LaunchAtLoginStatus = .disabled
    @State private var loginError: String?
    @State private var animationSpeed: Double = 1.0
    @State private var showMenuBarIcon = true
    @State private var showOnAllDisplays = false
    @State private var hoverToReveal = true
    @State private var hoverDelay: Double = 0
    @State private var artworkBreathing = true
    @State private var lyricsFontScale: Double = 1.0

    var body: some View {
        Form {
            Section {
                launchAtLoginRow
                Toggle("显示菜单栏图标", isOn: $showMenuBarIcon)
                    .onChange(of: showMenuBarIcon) { _, v in
                        settings.showMenuBarIcon = v
                        postChange()
                    }
                Toggle("在所有显示器上显示", isOn: $showOnAllDisplays)
                    .onChange(of: showOnAllDisplays) { _, v in
                        settings.showOnAllDisplays = v
                        postChange()
                    }
            } header: {
                Text("系统")
            } footer: {
                Text("关闭后仍可点击刘海内的齿轮进入设置。")
            }

            Section {
                Toggle("悬停展开", isOn: $hoverToReveal)
                    .onChange(of: hoverToReveal) { _, v in
                        settings.hoverToReveal = v
                        postChange()
                    }
                if hoverToReveal {
                    HStack {
                        Text("悬停延迟")
                        Spacer()
                        Text(hoverDelay <= 0 ? "立即" : String(format: "%.1f s", hoverDelay))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $hoverDelay, in: 0...1.0, step: 0.1)
                        .onChange(of: hoverDelay) { _, v in
                            settings.hoverDelay = v
                            postChange()
                        }
                }
            } header: {
                Text("交互")
            } footer: {
                Text(hoverToReveal
                    ? "鼠标移到刘海上后停留该时长再展开。"
                    : "关闭后仅点击刘海才会展开。")
            }

            Section {
                HStack {
                    Text("动画速度")
                    Spacer()
                    Text(speedLabel)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $animationSpeed, in: 0.5...2.0, step: 0.1) {
                    EmptyView()
                } minimumValueLabel: {
                    Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Image(systemName: "hare.fill").foregroundStyle(.secondary)
                }
                .onChange(of: animationSpeed) { _, v in
                    settings.animationSpeed = v
                    postChange()
                }
                Toggle("封面呼吸动画", isOn: $artworkBreathing)
                    .onChange(of: artworkBreathing) { _, v in
                        settings.artworkBreathing = v
                        postChange()
                    }
            } header: {
                Text("动画")
            } footer: {
                Text("数值越小动画越慢，越大越快。默认 1.0。")
            }

            Section {
                HStack {
                    Text("歌词字号")
                    Spacer()
                    Text(String(format: "%.1f×", lyricsFontScale))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $lyricsFontScale, in: 0.8...1.8, step: 0.1) {
                    EmptyView()
                } minimumValueLabel: {
                    Image(systemName: "textformat.size.smaller").foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Image(systemName: "textformat.size.larger").foregroundStyle(.secondary)
                }
                .onChange(of: lyricsFontScale) { _, v in
                    settings.lyricsFontScale = v
                    postChange()
                }
            } header: {
                Text("歌词")
            } footer: {
                Text("调整展开面板中歌词的文字大小。默认 1.0。")
            }
        }
        .navigationTitle("通用")
        .onAppear {
            loginStatus = settings.launchAtLoginStatus
            animationSpeed = settings.animationSpeed > 0 ? settings.animationSpeed : 1.0
            showMenuBarIcon = settings.showMenuBarIcon
            showOnAllDisplays = settings.showOnAllDisplays
            hoverToReveal = settings.hoverToReveal
            hoverDelay = settings.hoverDelay
            artworkBreathing = settings.artworkBreathing
            lyricsFontScale = settings.lyricsFontScale > 0 ? settings.lyricsFontScale : 1.0
        }
    }

    @ViewBuilder
    private var launchAtLoginRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("开机启动", isOn: Binding(
                get: { loginStatus == .enabled },
                set: { enabled in
                    loginError = nil
                    do {
                        let status = try settings.setLaunchAtLogin(enabled)
                        loginStatus = status
                    } catch {
                        loginError = error.localizedDescription
                        loginStatus = settings.launchAtLoginStatus
                    }
                }
            ))

            switch loginStatus {
            case .requiresApproval:
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("已注册，请在")
                    Button("系统设置 › 登录项") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    Text("中批准。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            case .unavailable:
                Label("当前版本不支持开机启动", systemImage: "xmark.circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
            default:
                EmptyView()
            }

            if let err = loginError {
                Label(err, systemImage: "exclamationmark.circle.fill")
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var speedLabel: String {
        String(format: "%.1f×", animationSpeed)
    }

    private func postChange() {
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }
}

// MARK: - 模块

private struct ModuleSettingsView: View {
    private let settings = SettingsManager.shared

    @State private var showMusicModule = true
    @State private var showFileModule  = true
    @State private var defaultModule: NotchModule = .music

    private var availableModules: [NotchModule] {
        var m: [NotchModule] = []
        if showMusicModule { m.append(.music) }
        if showFileModule  { m.append(.file)  }
        return m
    }

    var body: some View {
        Form {
            Section {
                Toggle("音乐控制", isOn: Binding(
                    get: { showMusicModule },
                    set: { v in
                        guard v || showFileModule else { return }
                        showMusicModule = v
                        clamp()
                        apply()
                    }
                ))
                Toggle("文件中转站", isOn: Binding(
                    get: { showFileModule },
                    set: { v in
                        guard v || showMusicModule else { return }
                        showFileModule = v
                        clamp()
                        apply()
                    }
                ))
            } header: {
                Text("启用的模块")
            } footer: {
                Text("至少保留一个模块。")
            }

            Section {
                Picker("默认展开模块", selection: $defaultModule) {
                    ForEach(availableModules, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: defaultModule) { _, v in
                    settings.defaultModule = v
                    apply()
                }
                .disabled(availableModules.count < 2)
            } header: {
                Text("默认模块")
            } footer: {
                Text("从菜单栏打开时默认展示此模块。")
            }
        }
        .navigationTitle("模块")
        .onAppear { load() }
    }

    private func load() {
        showMusicModule = settings.showMusicModule
        showFileModule  = settings.showFileModule
        defaultModule   = settings.defaultModule
    }

    private func clamp() {
        if defaultModule == .music && !showMusicModule {
            defaultModule = showFileModule ? .file : .music
        } else if defaultModule == .file && !showFileModule {
            defaultModule = showMusicModule ? .music : .file
        }
    }

    private func apply() {
        settings.showMusicModule = showMusicModule
        settings.showFileModule  = showFileModule
        settings.defaultModule   = defaultModule
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }
}

// MARK: - 关于

private struct AboutView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("应用") { Text("岛一下") }
                LabeledContent("版本") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
                LabeledContent("适用系统") { Text("macOS 26.0 及以上（刘海屏）") }
            } header: {
                Text("关于")
            }

            Section {
                Link(destination: URL(string: "https://github.com/yxyyds666/--macOS-Dynamic-Island")!) {
                    Label("GitHub 仓库", systemImage: "link")
                }
                Link(destination: URL(string: "https://github.com/TheBoredTeam/boring.notch")!) {
                    Label("灵感来源 boring.notch", systemImage: "heart")
                }
            } header: {
                Text("链接")
            }

            Section {
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label("退出岛一下", systemImage: "power")
                }
            }
        }
        .navigationTitle("关于")
    }
}

// MARK: - backward compat

extension SettingsView {
    /// Convenience init that keeps the MenuBarManager's onSave closure working
    /// without renaming the parameter everywhere.
    init(onSave: @escaping () -> Void) {
        self.init(onClose: onSave)
    }
}

extension NotchModule: Hashable {}
