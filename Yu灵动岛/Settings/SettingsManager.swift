import Foundation

final class SettingsManager: @unchecked Sendable {
    static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    
    var launchAtLogin: Bool {
        get { defaults.bool(forKey: AppConstants.DefaultsKeys.launchAtLogin) }
        set { defaults.set(newValue, forKey: AppConstants.DefaultsKeys.launchAtLogin) }
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
    
    func registerDefaults() {
        defaults.register(defaults: [
            AppConstants.DefaultsKeys.launchAtLogin: false,
            AppConstants.DefaultsKeys.showMusicModule: true,
            AppConstants.DefaultsKeys.showFileModule: true,
            AppConstants.DefaultsKeys.defaultModule: "music",
            AppConstants.DefaultsKeys.animationSpeed: 1.0
        ])
    }
}
