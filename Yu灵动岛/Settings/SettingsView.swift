import SwiftUI

struct SettingsView: View {
    let onSave: () -> Void
    @State private var launchAtLogin = false
    @State private var showMusicModule = true
    @State private var showFileModule = true
    @State private var defaultModule: NotchModule = .music
    @State private var animationSpeed: Double = 1.0
    @State private var saveError: String?
    @State private var loginStatus: SettingsManager.LaunchAtLoginStatus = .disabled
    
    private let settings = SettingsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("设置")
                .font(.system(size: 20, weight: .bold))
            
            // General
            GroupBox("通用") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("开机启动", isOn: Binding(
                        get: { launchAtLogin },
                        set: { launchAtLogin = $0 }
                    ))
                    if loginStatus == .requiresApproval {
                        Text("已注册，但需要在系统设置中批准")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    } else if loginStatus == .unavailable {
                        Text("当前应用不支持开机启动")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Toggle("显示音乐模块", isOn: Binding(
                        get: { showMusicModule },
                        set: { newValue in
                            if !newValue && !showFileModule { return }
                            showMusicModule = newValue
                            clampDefaultModule()
                        }
                    ))
                    Toggle("显示文件中转模块", isOn: Binding(
                        get: { showFileModule },
                        set: { newValue in
                            if !newValue && !showMusicModule { return }
                            showFileModule = newValue
                            clampDefaultModule()
                        }
                    ))
                    Text("至少保留一个模块")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
            
            // Default module
            GroupBox("默认模块") {
                Picker("", selection: $defaultModule) {
                    ForEach(NotchModule.allCases.filter { isModuleEnabled($0) }, id: \.self) { module in
                        Text(module.displayName).tag(module)
                    }
                }
                .pickerStyle(.segmented)
                .padding(8)
            }
            
            // Animation
            GroupBox("动画") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("动画速度")
                    Slider(value: $animationSpeed, in: 0.5...2.0, step: 0.1)
                }
                .padding(8)
            }
            
            Spacer()
            
            // Save button
            VStack(alignment: .trailing, spacing: 8) {
                if let saveError {
                    Text(saveError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer()
                    Button("保存") {
                        if save() { NSApp.keyWindow?.close() }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .padding(20)
        .frame(width: 360, height: 400)
        .onAppear {
            loadSettings()
            loginStatus = settings.launchAtLoginStatus
        }
    }
    
    private func loadSettings() {
        launchAtLogin = settings.launchAtLogin
        showMusicModule = settings.showMusicModule
        showFileModule = settings.showFileModule
        defaultModule = settings.defaultModule
        animationSpeed = settings.animationSpeed
    }
    
    private func clampDefaultModule() {
        if defaultModule == .music && !showMusicModule {
            defaultModule = showFileModule ? .file : .music
        } else if defaultModule == .file && !showFileModule {
            defaultModule = showMusicModule ? .music : .file
        }
    }

    private func isModuleEnabled(_ module: NotchModule) -> Bool {
        module == .music ? showMusicModule : showFileModule
    }

    private func save() -> Bool {
        if !showMusicModule && !showFileModule {
            showMusicModule = true
        }
        clampDefaultModule()
        saveError = nil
        do {
            let status = try settings.setLaunchAtLogin(launchAtLogin)
            loginStatus = status
            launchAtLogin = status == .enabled
            if status == .requiresApproval {
                saveError = "已注册，请在系统设置的登录项中批准"
                return false
            }
        } catch {
            launchAtLogin = settings.launchAtLogin
            saveError = "无法更新开机启动：\(error.localizedDescription)"
            return false
        }
        settings.showMusicModule = showMusicModule
        settings.showFileModule = showFileModule
        settings.defaultModule = defaultModule
        settings.animationSpeed = animationSpeed
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        onSave()
        return true
    }
}

// Make NotchModule work with Picker
extension NotchModule: Hashable {}
