import SwiftUI

struct SettingsView: View {
    @State private var launchAtLogin = false
    @State private var showMusicModule = true
    @State private var showFileModule = true
    @State private var defaultModule: NotchModule = .music
    @State private var animationSpeed: Double = 1.0
    
    private let settings = SettingsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("设置")
                .font(.system(size: 20, weight: .bold))
            
            // General
            GroupBox("通用") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("开机启动", isOn: $launchAtLogin)
                    Toggle("显示音乐模块", isOn: $showMusicModule)
                    Toggle("显示文件中转模块", isOn: $showFileModule)
                }
                .padding(8)
            }
            
            // Default module
            GroupBox("默认模块") {
                Picker("", selection: $defaultModule) {
                    ForEach(NotchModule.allCases, id: \.self) { module in
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
            HStack {
                Spacer()
                Button("保存") {
                    save()
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(20)
        .frame(width: 360, height: 400)
        .onAppear {
            loadSettings()
        }
    }
    
    private func loadSettings() {
        launchAtLogin = settings.launchAtLogin
        showMusicModule = settings.showMusicModule
        showFileModule = settings.showFileModule
        defaultModule = settings.defaultModule
        animationSpeed = settings.animationSpeed
    }
    
    private func save() {
        settings.launchAtLogin = launchAtLogin
        settings.showMusicModule = showMusicModule
        settings.showFileModule = showFileModule
        settings.defaultModule = defaultModule
        settings.animationSpeed = animationSpeed
    }
}

// Make NotchModule work with Picker
extension NotchModule: Hashable {}
