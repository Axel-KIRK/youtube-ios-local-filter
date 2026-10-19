import SwiftUI

@main
struct LocalFilterApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--settings-navigation-test") {
                SettingsNavigationProbeView()
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
