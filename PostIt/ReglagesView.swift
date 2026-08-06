import SwiftUI

/// Fenêtre Réglages (⌘,). Texte et comportement de la liste.
struct ReglagesView: View {
    @EnvironmentObject var store: Store

    /// Polices proposées : la police système + celles installées pour l'app.
    /// Seules les familles réellement présentes sur la machine sont listées,
    /// pour ne jamais proposer un choix qui afficherait un fallback moche.
    private var policesDisponibles: [(nom: String, famille: String)] {
        let candidates = [
            ("Inter", "Inter"),
            ("Space Grotesk", "Space Grotesk"),
            ("Manrope", "Manrope"),
            ("JetBrains Mono", "JetBrains Mono"),
            ("Avenir Next", "Avenir Next"),
            ("SF Mono", "SF Mono"),
        ]
        let installees = Set(NSFontManager.shared.availableFontFamilies)
        return [("Système", "")] + candidates.filter { installees.contains($0.1) }
    }

    var body: some View {
        Form {
            Section("Texte") {
                Picker("Police", selection: Binding(
                    get: { store.reglages.policeNom },
                    set: { store.reglages.policeNom = $0; store.sauverReglages() })) {
                    ForEach(policesDisponibles, id: \.famille) { p in
                        Text(p.nom).tag(p.famille)
                    }
                }

                HStack {
                    Slider(value: Binding(
                        get: { store.reglages.taillePolice },
                        set: { store.reglages.taillePolice = $0 }),
                        in: 10...18, step: 1,
                        onEditingChanged: { fini in if fini { store.sauverReglages() } })
                    Text("\(Int(store.reglages.taillePolice)) pt")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }

                Text("Aperçu — Rapprochement BL fournisseurs")
                    .font(store.reglages.police(gras: true))
                Text("La sous-ligne s'ajuste automatiquement, deux points plus petite.")
                    .font(store.reglages.police(delta: -2))
                    .foregroundStyle(.secondary)
            }

            Section("Comportement") {
                Toggle("Notes dépliées par défaut", isOn: Binding(
                    get: { store.reglages.deplieParDefaut },
                    set: { store.reglages.deplieParDefaut = $0; store.sauverReglages() }))
                Text("Un clic sur une ligne inverse son état, quel que soit ce réglage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}
