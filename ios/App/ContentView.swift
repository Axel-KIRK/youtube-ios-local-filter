import SwiftUI
import NetworkExtension
import LocalFilterCore

struct ContentView: View {
    @StateObject private var connection = ConnectionController()
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var diagnostic: DiagnosticResult?
    @State private var checking = false
    #if DEBUG
    @State private var ranLaunchCheck = false
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(statusTitle, systemImage: connection.running ? "network" : "pause.circle")
                            .font(.headline)
                        Text("Your YouTube.\nFewer interruptions.")
                            .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                        Text("Experimental build. Setup and background filtering on iPhone still need device validation.")
                            .foregroundStyle(.secondary)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("1. Allow the local connection").font(.headline)
                            Text("iOS will ask to add a VPN configuration. Processing happens on this iPhone; there is no remote VPN server.")
                                .font(.subheadline)
                            Button("Prepare connection") { Task { await connection.start(.setup) } }
                                .buttonStyle(.bordered).disabled(connection.busy || connection.running)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("2. Install and trust the certificate").font(.headline)
                            Text("This allows LocalFilter to read and change YouTube responses. The private key stays on this iPhone.")
                                .font(.subheadline)
                            Button("Open certificate in Safari") {
                                if let text = connection.snapshot?.certificateURL, let url = URL(string: text) { openURL(url) }
                            }
                            .buttonStyle(.bordered).disabled(connection.snapshot == nil || connection.busy)
                            Text("Allow the download, then open Settings → General → VPN & Device Management and install LocalFilter Personal CA. Next, open General → About → Certificate Trust Settings and enable full trust for it.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Text("iOS requires you to confirm installation and trust in Settings once. Return here afterward; LocalFilter checks the connection automatically.")
                                .font(.footnote).foregroundStyle(.secondary)
                            if connection.checkingCertificate {
                                ProgressView("Checking certificate and connection…")
                            } else if connection.certificateVerified {
                                Label("Certificate and connection verified", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            Button("Check setup again") { Task { await connection.checkCertificate() } }
                                .disabled(connection.busy || connection.snapshot?.mode != .setup)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("3. Enable and open YouTube").font(.headline)
                        Button {
                            Task { await connection.start(.filter) }
                        } label: {
                            HStack {
                                if connection.busy { ProgressView() }
                                Text(connection.checkingCertificate ? "Checking setup…" : "Verify and enable filtering")
                            }.frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(connection.busy || connection.snapshot?.mode == .filter)
                        if connection.running {
                            Button("Stop local connection", role: .destructive) { connection.stop() }
                                .buttonStyle(.bordered).disabled(connection.busy)
                        }
                        if let message = connection.message {
                            Text(message).font(.footnote).foregroundStyle(.red)
                        }
                        if connection.connectionStatus == .connected, connection.snapshot == nil {
                            Text("The connection is reported active, but the filter has not replied yet.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if let status = connection.snapshot, status.mode == .filter {
                            Text(status.responses == 0
                                 ? "Open a different video in YouTube. We are waiting for traffic; the VPN indicator alone does not confirm filtering."
                                 : "\(status.responses) responses received · \(status.rewrittenResponses) responses rewritten")
                                .font(.footnote).foregroundStyle(.secondary)
                            Text("Rewritten responses are not a count of ads prevented.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Connections: \(status.connections) · HTTPS tunnels: \(status.connectRequests) · Requests: \(status.decryptedRequests)")
                                .font(.caption).foregroundStyle(.secondary)
                            if let failure = status.lastFailure {
                                Text("Last connection issue: \(failure)")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            if status.upstreamFailures > 0 {
                                Text("\(status.upstreamFailures) connection errors. Stop the local connection if playback stalls.")
                                    .font(.footnote).foregroundStyle(.orange)
                            }
                        }
                    }

                    DisclosureGroup("Checks and removal") {
                        VStack(alignment: .leading, spacing: 14) {
                            Button(checking ? "Checking…" : "Run local engine check") { runDiagnostic() }
                                .disabled(checking)
                            if let diagnostic {
                                Text(diagnostic.passed ? "Synthetic check passed. This does not validate live filtering." : "The local check failed.")
                                    .font(.footnote)
                            }
                            Button("Remove local connection", role: .destructive) {
                                Task { await connection.removeConfiguration() }
                            }.disabled(connection.running || connection.busy)
                            Text("Stop the connection first. To remove the trusted certificate as well, delete LocalFilter Personal CA in Settings → General → VPN & Device Management.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }.padding(.top, 12)
                    }
                    Link("Test results and project status",
                         destination: URL(string: "https://github.com/Axel-KIRK/youtube-ios-local-filter")!)
                        .font(.footnote)
                }
                .padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .navigationTitle("LocalFilter").navigationBarTitleDisplayMode(.inline)
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                #if DEBUG
                if !ranLaunchCheck, ProcessInfo.processInfo.arguments.contains("--verify-local-setup") {
                    ranLaunchCheck = true
                    await connection.start(.filter)
                }
                #endif
                await connection.refresh()
                await connection.checkCertificate()
                while !Task.isCancelled {
                    await connection.refresh()
                    do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { break }
                }
            }
        }
    }

    private var statusTitle: String {
        switch connection.connectionStatus {
        case .connecting, .reasserting: return "Starting local connection…"
        case .disconnecting: return "Stopping…"
        case .connected:
            guard let status = connection.snapshot else { return "Waiting for filter status" }
            if status.mode == .setup { return "Ready for certificate setup" }
            return status.responses > 0 ? "Receiving YouTube traffic" : "Waiting for YouTube traffic"
        default: return "Filter inactive"
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
