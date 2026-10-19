import SwiftUI
import UIKit
import LocalFilterSetup

enum CertificateSettingsDestination: String, Identifiable {
    case profiles, trust
    var id: String { rawValue }
    var title: String { self == .profiles ? "Install the certificate" : "Enable full trust" }
}

/// Match the menu names on the phone while keeping the app's instructions in English.
/// English and French are the currently reviewed Settings labels, not universal locale coverage.
private struct SettingsLabels {
    var french: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--guide-french") { return true }
        if ProcessInfo.processInfo.arguments.contains("--guide-english") { return false }
        #endif
        return Locale.preferredLanguages.first?.hasPrefix("fr") == true
    }
    func label(_ english: String, _ french: String) -> String { self.french ? french : english }
    var settings: String { label("Settings", "Réglages") }
    var general: String { label("General", "Général") }
    var profiles: String { label("VPN & Device Management", "VPN et gestion de l’appareil") }
    var downloaded: String { label("Profile Downloaded", "Profil téléchargé") }
    var about: String { label("About", "Informations") }
    var trust: String { label("Certificate Trust Settings", "Réglages des certificats") }
    var install: String { label("Install", "Installer") }
    var done: String { label("Done", "Terminé") }
    var allow: String { label("Allow", "Autoriser") }
    var close: String { label("Close", "Fermer") }
    var proceed: String { label("Continue", "Continuer") }
}

/// Shared by live setup and the isolated simulator preview.
struct CertificateSetupView: View {
    var progress: CertificateSetupProgress
    var download: () -> Void
    var navigate: (CertificateSettingsDestination) -> Void
    var check: () -> Void
    private let labels = SettingsLabels()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(progress.canContinue ? "Finish certificate setup" : "Set up your certificate")
                .font(.title2.bold())
            if !progress.canContinue {
                Button(action: download) {
                    Text("1. Download certificate").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                Text("In Safari, tap “\(labels.allow)”, then “\(labels.close)”. Return to LocalFilter for step 2.")
                    .font(.subheadline)
            } else {
                Text(progress.certificateServedAt != nil
                     ? "Certificate sent to Safari. Continue with step 2."
                     : "If you already downloaded the certificate, continue with step 2.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Button { navigate(.profiles) } label: {
                Text("2. Install certificate — show steps").frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.borderedProminent).controlSize(.large)
            Button { navigate(.trust) } label: {
                Text("3. Enable full trust — show steps").frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.bordered).controlSize(.large)
            Text("Already installed LocalFilter Personal CA? Go to step 3. Return here afterward; setup is checked automatically.")
                .font(.footnote).foregroundStyle(.secondary)
            DisclosureGroup("Certificate missing? / Need help?") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("A download is not an installation. If LocalFilter Personal CA is missing from Settings, download it again and install it within 8 minutes. An installed certificate does not need another download.")
                    Text("Use LocalFilter Personal CA. The old YouTube PoC certificate belongs to the earlier Mac test.")
                    Button("Download certificate again", action: download)
                    Button("Check my setup", action: check)
                }.font(.subheadline).padding(.top, 10)
            }
        }
    }
}

struct CertificateSettingsHelp: View {
    @State private var destination: CertificateSettingsDestination
    var download: () -> Void
    var check: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var settingsFailed = false
    private let labels = SettingsLabels()

    init(destination: CertificateSettingsDestination, download: @escaping () -> Void, check: @escaping () -> Void) {
        _destination = State(initialValue: destination)
        self.download = download
        self.check = check
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(destination == .profiles ? "STEP 2 OF 3" : "STEP 3 OF 3")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(destination.title).font(.title2.bold())
                    Text("Use the menu names below on your iPhone.").font(.subheadline)
                    step(1, "Open “\(labels.settings)”", "Use the button below, or open Settings from your Home Screen. If it opens inside an app’s settings, tap the top-left back arrow until you reach the main Settings screen.")
                    Button("Open Settings") {
                        openURL(URL(string: UIApplication.openSettingsURLString)!) { opened in settingsFailed = !opened }
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                    if settingsFailed {
                        Text("Open “\(labels.settings)” from your Home Screen to continue.").foregroundStyle(.orange)
                    }
                    if destination == .profiles { installationSteps } else { trustSteps }
                }.padding(22).frame(maxWidth: 640).frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(destination)
            .navigationTitle("Certificate setup").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }
    }

    private var installationSteps: some View {
        VStack(alignment: .leading, spacing: 20) {
            step(2, "Tap “\(labels.general)”")
            step(3, "Tap “\(labels.profiles)”", "Scroll down in General to find it.")
            step(4, "Tap “LocalFilter Personal CA”", "Select this exact name. If it is already installed, continue to step 3 of this guide: full trust.")
            step(5, "Tap “\(labels.install)” at the top right", "Enter your iPhone passcode if asked. Confirm “\(labels.install)” on the following screens, then tap “\(labels.done)”.")
            Text("If “\(labels.downloaded)” appears on the main Settings screen, you can tap it to go straight to the downloaded profile.")
                .font(.footnote).foregroundStyle(.secondary)
            GroupBox("Can't find LocalFilter Personal CA?") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Only seeing the old YouTube PoC certificate? The new certificate is still missing. Pending downloads expire after 8 minutes.")
                    Button("Download certificate again", action: download)
                    Text("In Safari, tap “\(labels.allow)” and “\(labels.close)”, then repeat these installation steps.")
                }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("After installing, return to LocalFilter. One more Settings approval is needed.")
                .font(.subheadline)
            Button("Next: enable full trust") { destination = .trust }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private var trustSteps: some View {
        VStack(alignment: .leading, spacing: 20) {
            step(2, "Tap “\(labels.general)”")
            step(3, "Tap “\(labels.about)”")
            step(4, "Tap “\(labels.trust)”", "Scroll to the bottom of the About screen.")
            step(5, "Turn on “LocalFilter Personal CA”", "Enable the switch beside this exact name. If a confirmation appears, tap “\(labels.proceed)”. This lets LocalFilter read and modify YouTube responses on this iPhone.")
            step(6, "Return to LocalFilter", "Open LocalFilter from your Home Screen. It checks the certificate and connection automatically. Wait for “Ready for YouTube”.")
            GroupBox("Switch missing?") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Install LocalFilter Personal CA first. Downloading it alone is not enough; the old YouTube PoC certificate does not complete this setup.")
                    Button("Back to installation steps") { destination = .profiles }
                }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Check my setup", action: check).buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(number)).font(.subheadline.bold()).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(.blue, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .combine)
    }
}

#if DEBUG
/// No VPN, no live setup preferences; exercises the same guide as the phone.
struct CertificateSetupPreview: View {
    @State private var progress = CertificateSetupProgress()
    @State private var notice = "Synthetic setup preview — no VPN"
    @State private var destination: CertificateSettingsDestination?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(notice).font(.caption)
                CertificateSetupView(progress: progress, download: {
                    progress.recordDownloadOpened()
                    notice = "Safari opening alone must not confirm delivery."
                }, navigate: { destination = $0 }, check: { notice = "No trust check is run in this preview." })
                Divider()
                Button("Simulate certificate delivery") { progress.observe(certificateID: "simulated-ca", servedAt: Date()) }
                Button("Simulate replacement CA") { progress.observe(certificateID: UUID().uuidString, servedAt: nil) }
            }.padding(20)
        }
        .sheet(item: $destination) { selected in
            CertificateSettingsHelp(destination: selected, download: {
                destination = nil
                notice = "Preview download requested; no certificate was transferred."
            }, check: {
                destination = nil
                notice = "Preview check requested; no trust result is inferred."
            })
        }
    }
}
#endif
