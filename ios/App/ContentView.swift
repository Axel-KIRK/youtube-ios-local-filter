import SwiftUI
import UIKit
import NetworkExtension
import LocalFilterCore
import OSLog

struct ContentView: View {
    @StateObject private var connection = ConnectionController()
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("certificateDownloadOpenedAt") private var certificateDownloadOpenedAt = 0.0
    @State private var diagnostic: DiagnosticResult?
    @State private var checking = false
    @State private var showingGuide = false
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Label(statusTitle, systemImage: connection.filtering ? "checkmark.shield" : "shield")
                        .font(.headline).foregroundStyle(connection.filtering ? .green : .secondary)

                    GroupBox {
                        VStack(alignment: .leading, spacing: 18) {
                            if connection.busy {
                                Text(connection.checkingCertificate ? "Checking your setup" : "Preparing your connection")
                                    .font(.title2.bold())
                                ProgressView(connection.checkingCertificate
                                    ? "Verifying certificate trust and internet access…"
                                    : "Keep LocalFilter open. Approve the iOS prompt if it appears.")
                                Text("YouTube stays outside the filter until the check succeeds.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else if connection.filtering {
                                activeContent
                            } else if connection.certificateRequired {
                                certificateContent
                            } else {
                                welcomeContent
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let message = connection.message {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(.orange)
                    }
                    if connection.running || connection.enableWhenReady {
                        Button(connection.filtering ? "Stop filtering" : "Cancel setup", role: .destructive) {
                            connection.stop()
                        }
                        .frame(maxWidth: .infinity).disabled(connection.busy)
                    }

                    diagnostics
                    Text("Experimental build. Ad removal and background operation on iPhone are still being tested.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("Test results and project status",
                         destination: URL(string: "https://github.com/Axel-KIRK/youtube-ios-local-filter")!)
                        .font(.footnote)
                }
                .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .navigationTitle("LocalFilter").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingGuide) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            Text("Two approvals, once").font(.title2.bold())
                            Text("LocalFilter prepares everything it can. iOS requires you to approve the certificate in Settings. Return to LocalFilter afterward; it checks the setup and finishes activation automatically.")
                            CertificateGuide()
                        }.padding(24)
                    }
                    .navigationTitle("Setup guide").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingGuide = false } } }
                }
            }
            .onAppear {
                guard !appeared else { return }
                appeared = true
                // These operations must survive the inactive scene caused by an iOS permission prompt.
                Task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--probe-install-profile") {
                        let route = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--profile-route=") }?
                            .replacingOccurrences(of: "--profile-route=", with: "") ?? "legacy-root"
                        await openCertificateSettings(route: route)
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--stop-local-connection") {
                        await connection.stopSavedConnection()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--verify-local-setup") {
                        await connection.start(.filter)
                        return
                    }
                    #endif
                    await connection.resumeSetup()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await connection.resumeSetup() } }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    await connection.refresh()
                    do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { break }
                }
            }
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(connection.hasCompletedSetup ? "Filtering is off" : "Let's set up LocalFilter").font(.title2.bold())
            Text("Processing stays on this iPhone, with no remote VPN server.")
            Text(connection.hasCompletedSetup
                 ? "Tap Enable filtering. LocalFilter will check the connection before starting. If your certificate still works, there is nothing else to configure."
                 : "Approve a local VPN connection, then a certificate in Settings. LocalFilter guides you and checks the setup automatically.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("The certificate lets LocalFilter read and change YouTube responses. Its private key stays on this iPhone.")
                .font(.footnote).foregroundStyle(.secondary)
            Button { beginSetup() } label: {
                Text(connection.message != nil ? "Try again" : (connection.hasCompletedSetup ? "Enable filtering" : "Set up and enable"))
                    .frame(maxWidth: .infinity)
            }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private var certificateContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("iOS approval required").font(.title2.bold())
            Text("Install and trust the certificate in Settings, then return here. LocalFilter will check and finish automatically.")
                .font(.subheadline)
            Button { downloadCertificate() } label: {
                Text("Download certificate").frame(maxWidth: .infinity)
            }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Text("After the download, open Settings from your Home Screen. Direct navigation to certificate installation is still being investigated.")
                .font(.caption).foregroundStyle(.secondary)
            CertificateGuide()
            DisclosureGroup("Need help?") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No “Profile Downloaded”? Look under General → VPN & Device Management, or download again. iOS removes uninstalled downloads after eight minutes.")
                    Button("Download certificate again") { downloadCertificate() }
                    Button("Check again") { Task { await connection.start(.filter) } }
                }.font(.subheadline).padding(.top, 10)
            }
        }
    }

    #if DEBUG
    private func openCertificateSettings(route: String) async {
        // Undocumented experiments, excluded from Release. The legacy-root candidate
        // opens Settings root on the tested iOS 18.6.1 phone, even with a fresh profile.
        // A successful URL open is neither proof of the destination nor of trust.
        let candidates = [
            "legacy-root": "App-prefs:root=General&path=ManagedConfigurationList/PurgatoryInstallRequested",
            "without-root": "App-prefs:General&path=ManagedConfigurationList/PurgatoryInstallRequested",
            "profiles-root": "App-prefs:root=General&path=ManagedConfigurationList",
            "profiles-without-root": "App-prefs:General&path=ManagedConfigurationList",
            "profiles-prefs": "prefs:root=General&path=ManagedConfigurationList",
            "modern-profile": "settings-navigation://com.apple.Settings.General/ManagedConfigurationList/DownloadedProfile",
            "modern-profiles": "settings-navigation://com.apple.Settings.General/ManagedConfigurationList",
            "modern-general": "settings-navigation://com.apple.Settings.General"
        ]
        guard let value = candidates[route], let url = URL(string: value) else { return }
        let opened = await UIApplication.shared.open(url)
        Logger(subsystem: "com.axelkirk.localfilter", category: "navigation")
            .info("Settings probe \(route, privacy: .public): accepted=\(opened, privacy: .public)")
        if !opened {
            connection.message = "Open Settings from your Home Screen, then tap Profile Downloaded."
            showingGuide = true
        }
    }
    #endif

    private var activeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ready for YouTube").font(.title2.bold())
            Label(connection.certificateVerified ? "Certificate and connection verified" : "Local connection active", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Open a fresh video in the YouTube app to test filtering.")
            Button("Open YouTube") {
                // Only open the installed app. Never turn this into a Safari playback test.
                UIApplication.shared.open(URL(string: "https://www.youtube.com/")!,
                                          options: [.universalLinksOnly: true]) { opened in
                    if !opened {
                        connection.message = "Open the YouTube app from your Home Screen to continue the test."
                    }
                }
            }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
            if let status = connection.snapshot, status.responses > 0 {
                Text("\(status.responses) responses received · \(status.rewrittenResponses) rewritten")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("These counts do not confirm how many ads were prevented.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var diagnostics: some View {
        DisclosureGroup("Help and diagnostics") {
            VStack(alignment: .leading, spacing: 14) {
                Button("Show setup guide") { showingGuide = true }
                if let status = connection.snapshot {
                    Text("Mode: \(status.mode.rawValue)")
                    Text("Connections: \(status.connections) · HTTPS tunnels: \(status.connectRequests) · Requests: \(status.decryptedRequests)")
                    Text("Responses: \(status.responses) · Rewritten: \(status.rewrittenResponses)")
                    Text("Downstream failures: \(status.downstreamFailures) · Upstream failures: \(status.upstreamFailures)")
                    if let failure = status.lastFailure { Text("Last connection issue: \(failure)") }
                    Text("Setup checks also create connections. Counters reset when filtering starts.")
                }
                Button(checking ? "Checking…" : "Run local engine check") { runDiagnostic() }
                    .disabled(checking)
                if let diagnostic {
                    Text(diagnostic.passed ? "Synthetic check passed. This does not validate live filtering." : "The local check failed.")
                }
                Button("Remove local connection", role: .destructive) {
                    Task { await connection.removeConfiguration() }
                }.disabled(connection.running || connection.busy)
                Text("Stop the connection first. To remove the trusted certificate as well, delete LocalFilter Personal CA in Settings → General → VPN & Device Management.")
                    .foregroundStyle(.secondary)
            }.font(.footnote).padding(.top, 12).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusTitle: String {
        if connection.busy { return "Setting up…" }
        if connection.certificateRequired { return "Waiting for your approval" }
        switch connection.connectionStatus {
        case .connecting, .reasserting: return "Starting local connection…"
        case .disconnecting: return "Stopping…"
        case .connected:
            guard let status = connection.snapshot else { return "Waiting for connection status" }
            if status.mode == .setup { return "Setup connection ready" }
            return status.responses > 0 ? "Receiving YouTube traffic" : "Waiting for YouTube traffic"
        default: return "Filter is off"
        }
    }

    private func beginSetup() {
        Task {
            await connection.start(.filter)
            // Open the download once after the user's action, never on every foreground/check failure.
            if connection.certificateRequired,
               Date().timeIntervalSince1970 - certificateDownloadOpenedAt > 8 * 60 {
                downloadCertificate()
            }
        }
    }

    private func downloadCertificate() {
        guard let url = connection.certificateURL else {
            connection.message = "The setup connection is unavailable. Tap Check again to prepare it."
            return
        }
        openURL(url) { opened in
            if opened {
                // Opening Safari does not prove that the download or installation succeeded.
                certificateDownloadOpenedAt = Date().timeIntervalSince1970
            } else {
                connection.message = "The certificate download could not open. Try again."
            }
        }
    }

    private func runDiagnostic() {
        checking = true
        Task {
            diagnostic = await Task.detached(priority: .userInitiated) { LocalDiagnostic.run() }.value
            checking = false
        }
    }
}

private struct CertificateGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            instruction(1, title: "Install LocalFilter Personal CA",
                        path: "Profile Downloaded → Install")
            instruction(2, title: "Turn on full trust",
                        path: "General → About → Certificate Trust Settings → LocalFilter Personal CA")
        }
    }

    private func instruction(_ number: Int, title: String, path: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.subheadline.bold())
                .frame(width: 28, height: 28)
                .background(.tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.bold())
                Text(path).font(.subheadline)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
