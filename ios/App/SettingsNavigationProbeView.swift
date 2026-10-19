#if DEBUG
import SwiftUI
import UIKit
import OSLog

/// Isolated navigation diagnostic: no connection controller, VPN setup, or foreground tasks.
/// Every open call runs directly inside a Button action, with an official positive control.
struct SettingsNavigationProbeView: View {
    @State private var result = "No link opened yet."
    private let logger = Logger(subsystem: "com.axelkirk.localfilter", category: "navigation")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings navigation test").font(.title2.bold())
            Text("Open each link, then return to LocalFilter.").font(.subheadline)
            route("1. App settings — control", id: "manual-control",
                  url: UIApplication.openSettingsURLString)
            route("2. VPN & profiles — standard", id: "manual-profiles-root",
                  url: "App-prefs:root=General&path=ManagedConfigurationList")
            route("3. VPN & profiles — alternate", id: "manual-profiles-alternate",
                  url: "App-prefs:General&path=ManagedConfigurationList")
            route("4. VPN & profiles — modern", id: "manual-profiles-modern",
                  url: "settings-navigation://com.apple.Settings.General/ManagedConfigurationList")
            route("5. VPN & profiles — prefs", id: "manual-profiles-prefs",
                  url: "prefs:root=General&path=ManagedConfigurationList")
            Text(result).font(.footnote).foregroundStyle(.secondary)
            Text("An accepted link does not confirm the destination. This screen does not start the VPN or check certificate trust.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func route(_ title: String, id: String, url: String) -> some View {
        Button {
            let active = UIApplication.shared.applicationState == .active
            let mainThread = Thread.isMainThread
            logger.info("Manual navigation \(id, privacy: .public): active=\(active, privacy: .public), mainThread=\(mainThread, privacy: .public)")
            // No canOpenURL gate and no Task/launch-time trigger: preserve the actual tap context.
            UIApplication.shared.open(URL(string: url)!, options: [:]) { accepted in
                logger.info("Manual navigation \(id, privacy: .public): accepted=\(accepted, privacy: .public)")
                result = "\(title): \(accepted ? "Accepted; check the actual screen." : "Rejected by iOS.")"
            }
        } label: {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered).controlSize(.large)
    }
}
#endif
