import SwiftUI

@main
struct YuLingDongDaoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // No window group - we manage windows manually
        Settings {
            SettingsView()
        }
    }
}
