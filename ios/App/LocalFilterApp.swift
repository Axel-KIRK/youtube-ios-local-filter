import SwiftUI

@main
struct LocalFilterApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--settings-navigation-test") {
                SettingsNavigationProbeView()
            } else if ProcessInfo.processInfo.arguments.contains("--settings-shortcuts-test") {
                SettingsShortcutsProbeView()
            } else if ProcessInfo.processInfo.arguments.contains("--certificate-setup-preview") {
                CertificateSetupPreview()
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
