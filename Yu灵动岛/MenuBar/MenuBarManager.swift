import AppKit
import SwiftUI

@MainActor
final class MenuBarManager: NSObject, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
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

        // Module shortcuts — only show enabled modules.
        for module in appState.availableModules {
            let item = NSMenuItem(
                title: module.displayName,
                action: selector(for: module),
                keyEquivalent: keyEquivalent(for: module)
            )
            item.target = self
            item.state = appState.currentModule == module ? .on : .off
            menu.addItem(item)
        }

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

    private func selector(for module: NotchModule) -> Selector {
        switch module {
        case .music: return #selector(switchToMusic)
        case .file: return #selector(switchToFile)
        }
    }

    private func keyEquivalent(for module: NotchModule) -> String {
        switch module {
        case .music: return "1"
        case .file: return "2"
        }
    }

    // MARK: - Actions

    @objc private func switchToMusic() {
        appState.selectModule(.music, reveal: true)
    }

    @objc private func switchToFile() {
        appState.selectModule(.file, reveal: true)
    }

    @objc private func openSettings() {
        // The menu is still tracking/closing when this action fires, so
        // activation and key-window promotion get swallowed if done inline.
        // Defer to the next runloop tick so the menu has fully dismissed first.
        DispatchQueue.main.async { [weak self] in
            self?.presentSettings()
        }
    }

    private func presentSettings() {
        // This is an LSUIElement (menu-bar-only) app, so it normally runs as an
        // .accessory app that can't become active — its windows show but never
        // become key, so controls don't take clicks. Promote to .regular while
        // the settings window is open so it can accept input, then drop back to
        // .accessory when it closes (see windowWillClose).
        NSApp.setActivationPolicy(.regular)

        // Rebuild the content each open so SwiftUI @State reloads from the saved
        // settings rather than showing stale draft values from a prior session.
        let controller = NSHostingController(
            rootView: SettingsView { [weak self] in
                self?.settingsWindow?.close()
            }
        )
        if let window = settingsWindow {
            window.contentViewController = controller
        } else {
            let window = NSWindow(contentViewController: controller)
            window.title = "设置"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            settingsWindow = window
        }
        settingsWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    // MARK: - NSWindowDelegate

    /// Drop back to accessory (menu-bar-only) once settings closes, so the app
    /// stops showing a Dock icon and app menu.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
