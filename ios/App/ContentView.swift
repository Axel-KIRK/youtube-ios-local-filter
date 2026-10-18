import SwiftUI
import LocalFilterCore

struct ContentView: View {
    @State private var checking = false
    @State private var diagnostic: DiagnosticResult?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Filter inactive", systemImage: "pause.circle.fill")
                            .font(.headline).foregroundStyle(.secondary)
                        Text("Your YouTube.\nFewer interruptions.")
                            .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                        Text("We are preparing a simple setup, right on your iPhone.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Preview version", systemImage: "info.circle")
                            .font(.headline)
                        Text("This version checks local processing. It does not filter YouTube traffic yet.")
                        Text("No phone settings are changed.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 20) {
                        Text("The planned setup").font(.title2.bold())
                        setupRow("1", title: "Allow the local connection",
                                 detail: "An iOS confirmation will allow connections to reach the filter on this iPhone.")
                        setupRow("2", title: "Trust the certificate",
                                 detail: "A guide will walk you through installation and trust in Settings, once.")
                        setupRow("3", title: "Enable and open YouTube",
                                 detail: "Keep your usual YouTube app. No computer will be needed.")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: runDiagnostic) {
                            HStack {
                                if checking { ProgressView().tint(.white) }
                                Text(checking ? "Checking…" : "Check this version")
                            }.frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent).disabled(checking)
                        .accessibilityHint("Checks test data without connecting to YouTube.")
                        if let diagnostic {
                            Label(diagnostic.passed ? "Local check passed" : "The check failed",
                                  systemImage: diagnostic.passed ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .foregroundStyle(diagnostic.passed ? .green : .red)
                            Text(diagnostic.passed
                                 ? "Test instructions were removed and video data preserved. This does not enable filtering in YouTube."
                                 : "The filter remains inactive. This result does not validate this version.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text("This check only uses synthetic data on your device.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    Link("What has been tested and what remains to be done",
                         destination: URL(string: "https://github.com/Axel-KIRK/youtube-ios-local-filter")!)
                        .font(.footnote)
                }
                .padding(24).frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("LocalFilter").navigationBarTitleDisplayMode(.inline)
        }
    }

    private func setupRow(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.headline).frame(width: 32, height: 32)
                .background(.quaternary, in: Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func runDiagnostic() {
        checking = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { LocalDiagnostic.run() }.value
            diagnostic = result
            checking = false
        }
    }
}
