import SwiftUI
import VibelslandFreeCore

@main
struct VibelslandFreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.store)
                .environmentObject(appDelegate.configurationStore)
        }
    }
}
