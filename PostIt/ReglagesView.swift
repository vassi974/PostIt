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

            Section("Écran TURZX") {
                Toggle("Limiter le nombre d'épinglés", isOn: Binding(
                    get: { store.reglages.maxEpingles > 0 },
                    set: { actif in
                        store.reglages.maxEpingles = actif ? max(1, epinglesActuelsPourDefaut) : 0
                        store.sauverReglages()
                    }))

                if store.reglages.maxEpingles > 0 {
                    Stepper(value: Binding(
                        get: { store.reglages.maxEpingles },
                        set: { store.reglages.maxEpingles = $0; store.sauverReglages() }),
                        in: 1...20) {
                        Text("Maximum : \(store.reglages.maxEpingles)")
                    }
                }

                Text("Utile si un écran externe (TURZX) n'affiche que les épinglés — sans " +
                     "limite, illimité par défaut, ne gêne personne d'autre. Épingler " +
                     "au-delà de la limite est refusé ; désépingler reste toujours possible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Valeur de départ raisonnable quand on active la limite pour la
    /// première fois : le nombre d'épinglés actuels, pour ne rien casser
    /// tout de suite (sinon activer la limite désépinglerait tout d'un coup).
    private var epinglesActuelsPourDefaut: Int {
        max(1, store.lignes.filter(\.pin).count)
    }
}
