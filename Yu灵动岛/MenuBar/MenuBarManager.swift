import AppKit

final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private let appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "circle.fill",
                accessibilityDescription: AppConstants.appName
            )
            button.image?.isTemplate = true
        }
        
        statusItem?.menu = buildMenu()
    }
    
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        
        // Now playing info (non-clickable)
        if appState.hasMediaPlaying {
            let infoItem = NSMenuItem(title: "🎵 \(appState.songTitle)", action: nil, keyEquivalent: "")
            infoItem.isEnabled = false
            menu.addItem(infoItem)
            menu.addItem(.separator())
        }
        
        // Module shortcuts
        let musicItem = NSMenuItem(title: "音乐控制", action: #selector(switchToMusic), keyEquivalent: "1")
        musicItem.target = self
        musicItem.state = appState.currentModule == .music ? .on : .off
        menu.addItem(musicItem)
        
        let fileItem = NSMenuItem(title: "文件中转站", action: #selector(switchToFile), keyEquivalent: "2")
        fileItem.target = self
        fileItem.state = appState.currentModule == .file ? .on : .off
        menu.addItem(fileItem)
        
        menu.addItem(.separator())
        
        // Settings
        let settingsItem = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // About
        let aboutItem = NSMenuItem(title: "关于 \(AppConstants.appName)", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        return menu
    }
    
    @objc private func switchToMusic() {
        appState.currentModule = .music
    }
    
    @objc private func switchToFile() {
        appState.currentModule = .file
    }
    
    @objc private func openSettings() {
        // Will be implemented in Task 10
    }
    
    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    func updateMenu() {
        statusItem?.menu = buildMenu()
    }
}
