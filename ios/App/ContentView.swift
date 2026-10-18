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
                        Label("Filtre inactif", systemImage: "pause.circle.fill")
                            .font(.headline).foregroundStyle(.secondary)
                        Text("Votre YouTube.\nMoins d'interruptions.")
                            .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                        Text("Nous préparons une installation simple, directement sur votre iPhone.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Version de préparation", systemImage: "info.circle")
                            .font(.headline)
                        Text("Cette version vérifie le traitement local. Elle ne filtre pas encore le trafic de YouTube.")
                        Text("Aucun réglage de votre téléphone n'est modifié.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 20) {
                        Text("L'installation prévue").font(.title2.bold())
                        setupRow("1", title: "Autoriser la connexion locale",
                                 detail: "Une validation iOS permettra de diriger les connexions vers le filtre sur cet iPhone.")
                        setupRow("2", title: "Approuver le certificat",
                                 detail: "Un guide accompagnera l'installation et la confiance dans Réglages, une seule fois.")
                        setupRow("3", title: "Activer et ouvrir YouTube",
                                 detail: "L'application YouTube habituelle sera conservée. Aucun ordinateur ne sera nécessaire.")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: runDiagnostic) {
                            HStack {
                                if checking { ProgressView().tint(.white) }
                                Text(checking ? "Vérification…" : "Vérifier cette version")
                            }.frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent).disabled(checking)
                        .accessibilityHint("Vérifie des données de test, sans connexion à YouTube.")
                        if let diagnostic {
                            Label(diagnostic.passed ? "Vérification locale réussie" : "La vérification a échoué",
                                  systemImage: diagnostic.passed ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .foregroundStyle(diagnostic.passed ? .green : .red)
                            Text(diagnostic.passed
                                 ? "Les instructions de test ont été retirées et les données vidéo conservées. Cela n'active pas le filtre dans YouTube."
                                 : "Le filtre reste inactif. Le résultat ne permet pas de valider cette version.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text("Ce test utilise uniquement des données fictives sur votre appareil.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    Link("Ce qui a été testé et ce qu'il reste à faire",
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
