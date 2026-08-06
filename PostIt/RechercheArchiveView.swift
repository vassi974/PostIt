import SwiftUI

/// Panneau de recherche plein texte sur l'archive exportée. Recherche floue :
/// familles de mots (tokenizer 'porter' de l'index) + préfixes partiels.
struct RechercheArchiveView: View {
    @State private var requete = ""
    @State private var resultats: [ResultatRecherche] = []
    @FocusState private var focus: Bool
    var fermer: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Rechercher dans l'archive…", text: $requete)
                    .textFieldStyle(.plain)
                    .focused($focus)
                    .onChange(of: requete) { _, _ in lancer() }
                    .onSubmit(lancer)
                Button { fermer() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            if !ArchiveRecherche.disponible {
                Text("Archive introuvable — lancer indexer_archives.py après un export Anthropic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                Spacer()
            } else if requete.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("142 conversations indexées. Tape un mot pour chercher.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                Spacer()
            } else if resultats.isEmpty {
                Text("Aucun résultat pour « \(requete) ».")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                Spacer()
            } else {
                List(resultats) { r in
                    LigneResultat(resultat: r)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { focus = true }
    }

    private func lancer() {
        resultats = ArchiveRecherche.rechercher(requete)
    }
}

private struct LigneResultat: View {
    let resultat: ResultatRecherche

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(resultat.titre)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Image(systemName: resultat.auteur == "human" ? "person.fill" : "asterisk")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Text(surligner(resultat.extrait))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { ouvrir() }
    }

    /// Les marqueurs ⟦...⟧ posés par snippet() en SQL deviennent du texte en
    /// gras — c'est la même logique de contraste que pour les instructions
    /// de navigation ailleurs dans l'app.
    private func surligner(_ texte: String) -> AttributedString {
        var résultat = AttributedString()
        var reste = texte[...]
        while let debut = reste.range(of: "⟦"), let fin = reste.range(of: "⟧", range: debut.upperBound..<reste.endIndex) {
            résultat += AttributedString(reste[reste.startIndex..<debut.lowerBound])
            var marque = AttributedString(reste[debut.upperBound..<fin.lowerBound])
            marque.font = .system(size: 11, weight: .bold)
            résultat += marque
            reste = reste[fin.upperBound...]
        }
        résultat += AttributedString(reste)
        return résultat
    }

    private func ouvrir() {
        guard let url = URL(string: "claude://claude.ai/chat/\(resultat.convUUID)") else { return }
        NSWorkspace.shared.open(url)
    }
}
