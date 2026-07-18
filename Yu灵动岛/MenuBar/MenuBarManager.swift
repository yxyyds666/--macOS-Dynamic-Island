import AppKit

final class MenuBarManager: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        updateIcon()

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    /// Reflects playback state in the status bar glyph.
    func updateIcon() {
        guard let button = statusItem?.button else { return }
        let symbol = appState.isPlaying ? "music.note" : "circle.fill"
        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: AppConstants.appName
        )
        button.image?.isTemplate = true
    }

    // MARK: - NSMenuDelegate

    /// Rebuild the menu each time it opens so it reflects current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        buildItems(into: menu)
    }

    private func buildItems(into menu: NSMenu) {
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
    }

    // MARK: - Actions

    @objc private func switchToMusic() {
        appState.currentModule = .music
    }

    @objc private func switchToFile() {
        appState.currentModule = .file
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // macOS 14+ uses the "showSettingsWindow:" selector; older uses
        // "showPreferencesWindow:". Try both so the Settings scene opens.
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
