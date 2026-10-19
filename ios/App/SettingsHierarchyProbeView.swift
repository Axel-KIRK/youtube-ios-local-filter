#if DEBUG
import SwiftUI
import UIKit
import OSLog

/// Each launch selects one allowlisted level. Nothing starts a VPN or changes trust.
struct SettingsHierarchyProbeView: View {
    @State private var result = "No navigation attempted."
    private let logger = Logger(subsystem: "com.axelkirk.localfilter", category: "navigation")
    private let destinations: [String: (title: String, path: String)] = [
        "general": ("1. General", ""),
        "profiles": ("2. VPN & Device Management", "ManagedConfigurationList"),
        "install": ("3. Pending profile installation", "ManagedConfigurationList/PurgatoryInstallRequested"),
        "downloaded": ("3. Downloaded profile route", "ManagedConfigurationList/DownloadedProfile"),
        "about": ("2. About", "About"),
        "trust": ("3. Certificate Trust Settings", "About/CERT_TRUST_SETTINGS")
    ]
    private var selection: String {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--navigation-level=") }?
            .replacingOccurrences(of: "--navigation-level=", with: "") ?? "general"
    }
    private var destination: (title: String, path: String) { destinations[selection] ?? destinations["general"]! }
    private var suffix: String { destination.path.isEmpty ? "" : "&path=" + destination.path }
    private var profileID: String? {
        guard selection == "downloaded", let value = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("--navigation-profile-id=")
        })?.replacingOccurrences(of: "--navigation-profile-id=", with: ""),
        [64, 65].contains(value.count), value.allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
        return value
    }
    private var modernURL: String {
        "settings-navigation://com.apple.Settings.General" + (destination.path.isEmpty ? "" : "/" + destination.path)
            + (profileID.map { "?id=" + $0 } ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings hierarchy test").font(.title2.bold())
                Text(destination.title).font(.headline)
                Text("Inspect the actual heading after each tap. Reset Settings before comparing routes.")
                    .font(.subheadline)
                route("App settings — control", id: "control", url: UIApplication.openSettingsURLString)
                route("Open level — App-prefs root", id: "app-prefs-root", url: "App-prefs:root=General" + suffix)
                route("Open level — App-prefs alternate", id: "app-prefs-alternate", url: "App-prefs:General" + suffix)
                route("Open level — prefs", id: "prefs", url: "prefs:root=General" + suffix)
                route("Open level — modern", id: "modern", url: modernURL)
                Button("Open level through test shortcut") {
                    // Simulator-only helper created in the UI: Open Shortcut Input, then Nothing.
                    // It is not a distributable consumer shortcut or an installation/trust claim.
                    var url = URLComponents(string: "shortcuts://run-shortcut")!
                    url.queryItems = [URLQueryItem(name: "name", value: "LocalFilter Profiles 1"),
                        URLQueryItem(name: "input", value: "text"),
                        URLQueryItem(name: "text", value: "prefs:root=General" + suffix)]
                    open(url.url!, id: "shortcut-input")
                }.buttonStyle(.borderedProminent)
                Button("Open modern level through test shortcut") {
                    var url = URLComponents(string: "shortcuts://run-shortcut")!
                    url.queryItems = [URLQueryItem(name: "name", value: "LocalFilter Profiles 1"),
                        URLQueryItem(name: "input", value: "text"), URLQueryItem(name: "text", value: modernURL)]
                    open(url.url!, id: "shortcut-modern-input")
                }.buttonStyle(.bordered)
                if selection == "downloaded" {
                    Text(profileID == nil ? "No profile identifier supplied." : "Observed test-profile identifier supplied.")
                        .font(.caption)
                }
                Text(result).font(.footnote).foregroundStyle(.secondary)
                #if targetEnvironment(simulator)
                if selection == "install" {
                    Button("Download simulator navigation certificate") {
                        open(URL(string: "http://127.0.0.1:8899/LocalFilterNavigation.cer")!, id: "test-certificate")
                    }.buttonStyle(.bordered)
                    Text("Test certificate only. Download it to create a pending profile; do not install or trust it.")
                        .font(.caption)
                }
                #endif
            }.controlSize(.large).padding(20)
        }
    }

    private func route(_ title: String, id: String, url: String) -> some View {
        Button(title) { open(URL(string: url)!, id: id) }.buttonStyle(.bordered)
    }

    private func open(_ url: URL, id: String) {
        let level = selection
        UIApplication.shared.open(url) { accepted in
            logger.info("Hierarchy probe level=\(level, privacy: .public) route=\(id, privacy: .public) accepted=\(accepted, privacy: .public)")
            result = "\(id): \(accepted ? "Accepted; verify the destination." : "Rejected.")"
        }
    }
}
#endif
