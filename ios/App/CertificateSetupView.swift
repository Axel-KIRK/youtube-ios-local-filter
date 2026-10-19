import SwiftUI
import LocalFilterSetup

enum CertificateSettingsDestination: String, Identifiable {
    case profiles, trust
    var id: String { rawValue }
    var shortcutName: String { self == .profiles ? "LocalFilter Profiles" : "LocalFilter Trust" }
    var title: String { self == .profiles ? "Install LocalFilter Personal CA" : "Turn on full trust" }
    var path: String {
        self == .profiles ? "Settings → General → VPN & Device Management → LocalFilter Personal CA → Install"
            : "Settings → General → About → Certificate Trust Settings → LocalFilter Personal CA"
    }
    var settingsURL: String {
        self == .profiles ? "prefs:root=General&path=ManagedConfigurationList"
            : "prefs:root=General&path=About/CERT_TRUST_SETTINGS"
    }
    var runURL: URL {
        var url = URLComponents(string: "shortcuts://run-shortcut")!
        url.queryItems = [URLQueryItem(name: "name", value: shortcutName)]
        return url.url!
    }
    // Only a published, reviewed Apple shortcut link belongs here. Missing assets
    // show an explicit limitation instead of launching a nonexistent shortcut.
    var importURL: URL? {
        guard let file = Bundle.main.url(forResource: "SettingsShortcuts", withExtension: "plist"),
              let data = try? Data(contentsOf: file),
              let links = try? PropertyListDecoder().decode([String: String].self, from: data),
              let text = links[rawValue], let url = URL(string: text),
              url.scheme == "https", url.host == "www.icloud.com", url.path.hasPrefix("/shortcuts/") else { return nil }
        return url
    }
}

/// The same view is used by live setup and the isolated simulator harness.
struct CertificateSetupView: View {
    var progress: CertificateSetupProgress
    var download: () -> Void
    var navigate: (CertificateSettingsDestination) -> Void
    var check: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(progress.canContinue ? "Finish certificate setup" : "Approve your certificate")
                .font(.title2.bold())
            if !progress.canContinue {
                Button(action: download) {
                    Text("Download certificate").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                Text(progress.certificateServedAt != nil ? "Certificate sent to Safari. Continue below."
                     : "Continue below if you already downloaded or installed the certificate.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Button { navigate(.profiles) } label: {
                Label("Install LocalFilter Personal CA", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.borderedProminent).controlSize(.large)
            Button { navigate(.trust) } label: {
                Label("Turn on full trust", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.bordered).controlSize(.large)
            Text("Already installed? Go straight to full trust. Return here afterward; LocalFilter checks and finishes automatically.")
                .font(.footnote).foregroundStyle(.secondary)
            DisclosureGroup("Need help?") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("If the profile is missing from Settings, download it again. iOS removes uninstalled downloads after eight minutes. An installed certificate does not need downloading again.")
                    Button("Download certificate again", action: download)
                    Button("Check again", action: check)
                }.font(.subheadline).padding(.top, 10)
            }
        }
    }
}

struct CertificateSettingsHelp: View {
    let destination: CertificateSettingsDestination
    var run: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var offeredImport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(destination.title).font(.title2.bold())
            if let url = destination.importURL {
                Text("Add this navigation shortcut once. It only opens the matching Settings page.")
                Button("Add navigation shortcut") {
                    openURL(url) { opened in offeredImport = opened }
                }.buttonStyle(.borderedProminent)
                if offeredImport {
                    Button("I added the shortcut — continue", action: run).buttonStyle(.borderedProminent)
                }
            } else {
                Text("The navigation shortcut is not available in this build yet. For now, use this path in Settings:")
                Text(destination.path).font(.headline)
            }
            DisclosureGroup("Shortcut already added?") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Use this only if you have saved “\(destination.shortcutName)” in Shortcuts.")
                    Button("Open with saved shortcut", action: run).buttonStyle(.bordered)
                }.padding(.top, 10)
            }
            Text("Opening Settings does not install the certificate or enable trust. LocalFilter verifies trust separately.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }.padding(24)
    }
}

#if DEBUG
/// Does not construct a connection controller or change live setup preferences.
struct CertificateSetupPreview: View {
    @State private var progress = CertificateSetupProgress()
    @State private var notice = "Synthetic setup preview — no VPN"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(notice).font(.caption)
                CertificateSetupView(progress: progress, download: {
                    progress.recordDownloadOpened()
                    notice = "Safari opening alone must not confirm delivery."
                }, navigate: { destination in
                    UIApplication.shared.open(destination.runURL) { accepted in
                        notice = accepted ? "Check the actual destination in Settings." : "Shortcuts did not open."
                    }
                }, check: { notice = "No trust check is run in this preview." })
                Divider()
                Button("Simulate certificate delivery") {
                    progress.observe(certificateID: "simulated-ca", servedAt: Date())
                }
                Button("Simulate replacement CA") {
                    progress.observe(certificateID: UUID().uuidString, servedAt: nil)
                }
            }.padding(20)
        }
    }
}
#endif
