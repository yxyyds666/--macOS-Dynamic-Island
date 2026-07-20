import Foundation
import ServiceManagement

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

    var launchAtLoginStatus: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .disabled
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    var launchAtLogin: Bool {
        launchAtLoginStatus == .enabled
    }

    @discardableResult
    func setLaunchAtLogin(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        let service = SMAppService.mainApp
        if enabled {
            if service.status == .notRegistered {
                try service.register()
            }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
        return launchAtLoginStatus
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
            AppConstants.DefaultsKeys.animationSpeed: 1.0
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
