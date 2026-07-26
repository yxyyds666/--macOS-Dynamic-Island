import Foundation

extension Notification.Name {
    /// Posted after settings are saved so the running app can apply them live.
    static let settingsDidChange = Notification.Name("com.yuxi.yulingdongdao.settingsDidChange")
}

final class SettingsManager: @unchecked Sendable {
    enum LaunchAtLoginStatus: Equatable {
        case disabled
        case enabled
        case requiresApproval
        case unavailable
    }

    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    /// Launch-at-login is managed with a per-user LaunchAgent plist rather than
    /// SMAppService. SMAppService requires a stable Developer ID signature to be
    /// honored at login; this app ships ad-hoc signed, so its registration is
    /// silently ignored by macOS. A LaunchAgent works regardless of signing.
    private let launchAgentLabel = "com.yuxi.yulingdongdao.launchatlogin"

    private var launchAgentURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

    var launchAtLoginStatus: LaunchAtLoginStatus {
        launchAtLogin ? .enabled : .disabled
    }

    var launchAtLogin: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    @discardableResult
    func setLaunchAtLogin(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        let fm = FileManager.default
        let url = launchAgentURL
        if enabled {
            try fm.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: launchAgentPlist(),
                format: .xml,
                options: 0
            )
            try data.write(to: url, options: .atomic)
        } else if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        return launchAtLoginStatus
    }

    /// The LaunchAgent contents pointing at the currently running app bundle.
    private func launchAgentPlist() -> [String: Any] {
        [
            "Label": launchAgentLabel,
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
        ]
    }

    var showMusicModule: Bool {
        get { defaults.object(forKey: AppConstants.DefaultsKeys.showMusicModule) as? Bool ?? true }
        set { defaults.set(newValue, forKey: AppConstants.DefaultsKeys.showMusicModule) }
    }

    var showFileModule: Bool {
        get { defaults.object(forKey: AppConstants.DefaultsKeys.showFileModule) as? Bool ?? true }
        set { defaults.set(newValue, forKey: AppConstants.DefaultsKeys.showFileModule) }
    }

    var defaultModule: NotchModule {
        get {
            let raw = defaults.string(forKey: AppConstants.DefaultsKeys.defaultModule) ?? "music"
            return NotchModule(rawValue: raw) ?? .music
        }
        set {
            defaults.set(newValue.rawValue, forKey: AppConstants.DefaultsKeys.defaultModule)
        }
    }

    var animationSpeed: Double {
        get { defaults.double(forKey: AppConstants.DefaultsKeys.animationSpeed) }
        set { defaults.set(newValue, forKey: AppConstants.DefaultsKeys.animationSpeed) }
    }

    /// Whether hovering the notch reveals the island (hover state / lyrics
    /// capsule). When off, only a click reveals it.
    var hoverToReveal: Bool {
        get { defaults.object(forKey: AppConstants.DefaultsKeys.hoverToReveal) as? Bool ?? true }
        set { defaults.set(newValue, forKey: AppConstants.DefaultsKeys.hoverToReveal) }
    }

    /// Seconds the cursor must dwell over the notch before hover reveals it.
    var hoverDelay: Double {
        get { defaults.double(forKey: AppConstants.DefaultsKeys.hoverDelay) }
        set { defaults.set(newValue, forKey: AppConstants.DefaultsKeys.hoverDelay) }
    }

    /// Whether the album artwork gently "breathes" (scales) while playing.
    var artworkBreathing: Bool {
        get { defaults.object(forKey: AppConstants.DefaultsKeys.artworkBreathing) as? Bool ?? true }
        set { defaults.set(newValue, forKey: AppConstants.DefaultsKeys.artworkBreathing) }
    }

    /// Whether the menu bar status item is shown.
    var showMenuBarIcon: Bool {
        get { defaults.object(forKey: AppConstants.DefaultsKeys.showMenuBarIcon) as? Bool ?? true }
        set { defaults.set(newValue, forKey: AppConstants.DefaultsKeys.showMenuBarIcon) }
    }

    /// Show an island on every connected display (not just the built-in notch screen).
    var showOnAllDisplays: Bool {
        get { defaults.object(forKey: AppConstants.DefaultsKeys.showOnAllDisplays) as? Bool ?? false }
        set { defaults.set(newValue, forKey: AppConstants.DefaultsKeys.showOnAllDisplays) }
    }

    /// Scale factor for lyrics text in the expanded panel. 1.0 = default size.
    var lyricsFontScale: Double {
        get { defaults.double(forKey: AppConstants.DefaultsKeys.lyricsFontScale) }
        set { defaults.set(newValue, forKey: AppConstants.DefaultsKeys.lyricsFontScale) }
    }

    var enabledModules: [NotchModule] {
        normalizeModuleSettings()
        var modules: [NotchModule] = []
        if showMusicModule { modules.append(.music) }
        if showFileModule { modules.append(.file) }
        return modules
    }

    func registerDefaults() {
        defaults.register(defaults: [
            AppConstants.DefaultsKeys.showMusicModule: true,
            AppConstants.DefaultsKeys.showFileModule: true,
            AppConstants.DefaultsKeys.defaultModule: "music",
            AppConstants.DefaultsKeys.animationSpeed: 1.0,
            AppConstants.DefaultsKeys.hoverToReveal: true,
            AppConstants.DefaultsKeys.hoverDelay: 0.0,
            AppConstants.DefaultsKeys.artworkBreathing: true,
            AppConstants.DefaultsKeys.showMenuBarIcon: true,
            AppConstants.DefaultsKeys.showOnAllDisplays: false,
            AppConstants.DefaultsKeys.lyricsFontScale: 1.0
        ])
        normalizeModuleSettings()
    }

    /// Keeps module preferences coherent: at least one module is enabled, and the
    /// default module always points at an enabled module.
    func normalizeModuleSettings() {
        if !showMusicModule && !showFileModule {
            showMusicModule = true
        }

        let modules = rawEnabledModules
        if !modules.contains(defaultModule), let fallback = modules.first {
            defaultModule = fallback
        }
    }

    private var rawEnabledModules: [NotchModule] {
        var modules: [NotchModule] = []
        if showMusicModule { modules.append(.music) }
        if showFileModule { modules.append(.file) }
        return modules
    }
}
