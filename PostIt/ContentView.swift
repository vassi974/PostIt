import SwiftUI

// MARK: - Couleurs de statut

extension Statut {
    var couleur: Color {
        switch self {
        case .actif:      return .green
        case .bloque:     return .red
        case .en_attente: return .orange
        case .dormant:    return .gray
        case .termine:    return .secondary
        }
    }
}

// MARK: - Police configurable

extension ReglagesFenetre {
    /// Police au choix de l'utilisateur, taille relative à la base réglée.
    /// delta : écart par rapport à la taille de base (sous-lignes en négatif).
    func police(delta: CGFloat = 0, gras: Bool = false) -> Font {
        let taille = max(9, CGFloat(taillePolice) + delta)
        if policeNom.isEmpty {
            return .system(size: taille, weight: gras ? .semibold : .regular)
        }
        return .custom(policeNom, size: taille).weight(gras ? .semibold : .regular)
    }
}

// MARK: - Vue principale

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var nouvelleNote = ""
    @State private var deplie: Set<String> = []
    @State private var idEnEdition: String?
    @State private var rechercheOuverte = false
    @FocusState private var focusSaisie: Bool

    var body: some View {
        VStack(spacing: 0) {
            if rechercheOuverte {
                RechercheArchiveView { rechercheOuverte = false }
            } else {
                barreSaisie
                Divider()
                liste
                if let e = store.erreur { barreErreur(e) }
                Divider()
                barrePied
            }
        }
        .frame(minWidth: 300, minHeight: 240)
    }

    // MARK: Saisie

    private var barreSaisie: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
                .foregroundStyle(.secondary)
            TextField("Ajouter une note…", text: $nouvelleNote)
                .textFieldStyle(.plain)
                .focused($focusSaisie)
                .onSubmit(ajouter)
            Button { rechercheOuverte = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))  // 2× la taille précédente (~10pt)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Rechercher dans l'archive des conversations")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func ajouter() {
        store.ajouterNote(nouvelleNote)
        nouvelleNote = ""
        focusSaisie = true      // saisie en rafale, comme le popover de tags ChapterMark
    }

    // MARK: Liste

    private var liste: some View {
        // Séparation franche épinglés / reste : deux groupes distincts plutôt
        // qu'un simple tri, avec un bloc visuel propre aux épinglés (fond
        // teinté, bordure, en-tête) pour que ça tranche au premier coup d'œil.
        let epingles = store.lignes.filter(\.pin)
        let reste = store.lignes.filter { !$0.pin }

        return ScrollViewReader { proxy in
            List {
                if !epingles.isEmpty {
                    Section {
                        ForEach(epingles) { ligne in ligneRow(ligne) }
                            .onMove { store.deplacerDansGroupe(epingles, de: $0, vers: $1) }
                    } header: {
                        Text("ÉPINGLÉ")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.leading, 2)
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.14))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                    )
                }

                if !reste.isEmpty {
                    Section {
                        ForEach(reste) { ligne in ligneRow(ligne) }
                            .onMove { store.deplacerDansGroupe(reste, de: $0, vers: $1) }
                    } header: {
                        if !epingles.isEmpty {
                            Text("AUTRES")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 2)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: idEnEdition) { ancien, nouvel in
                guard let id = nouvel ?? ancien else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }
        }
    }

    /// Une ligne de la liste — factorisé pour être appelé depuis les deux
    /// sections (épinglés / reste) sans dupliquer les paramètres.
    private func ligneRow(_ ligne: Ligne) -> some View {
        LigneVue(ligne: ligne,
                 deplie: store.reglages.deplieParDefaut != deplie.contains(ligne.id),
                 basculer: {
                     if deplie.contains(ligne.id) { deplie.remove(ligne.id) }
                     else { deplie.insert(ligne.id) }
                 },
                 surEdition: { idEnEdition = $0 })
        .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
    }

    // MARK: Pied

    private var barrePied: some View {
        HStack(spacing: 10) {
            Text("\(store.lignes.count)")
                .font(.caption).monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer()

            Toggle("Sommeil", isOn: Binding(
                get: { store.reglages.afficherDormants },
                set: { store.basculerFiltre(dormants: $0) }))

            Toggle("Terminés", isOn: Binding(
                get: { store.reglages.afficherTermines },
                set: { store.basculerFiltre(termines: $0) }))

            // Restauration : rien de supprimé n'est perdu, tout revient d'ici.
            Menu {
                if store.lignesRetirees.isEmpty {
                    Text("Rien à restaurer")
                } else {
                    ForEach(store.lignesRetirees) { l in
                        Button(l.titre) { store.restaurer(l) }
                    }
                    Divider()
                    Button("Tout réafficher") { store.toutRestaurer() }
                }
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Restaurer des lignes retirées")

            Button {
                store.basculerToujoursDevant()
            } label: {
                Image(systemName: store.reglages.toujoursDevant
                      ? "pin.circle.fill" : "pin.circle")
            }
            .buttonStyle(.borderless)
            .help("Garder la fenêtre au-dessus des autres")
        }
        .toggleStyle(.checkbox)
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func barreErreur(_ texte: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(texte).lineLimit(2)
        }
        .font(.caption)
        .foregroundStyle(.orange)
        .padding(.horizontal, 12).padding(.vertical, 5)
    }
}

// MARK: - Une ligne

struct LigneVue: View {
    @EnvironmentObject var store: Store
    let ligne: Ligne
    let deplie: Bool
    let basculer: () -> Void
    /// Signale à la liste quelle ligne passe en édition (nil = plus aucune),
    /// pour qu'elle puisse la garder visible.
    let surEdition: (String?) -> Void
    @State private var enEdition = false
    @State private var titreEdite = ""
    @State private var corpsEdite = ""
    @FocusState private var focusEdition: Bool

    private var aDuDetail: Bool {
        !ligne.resume.isEmpty || !ligne.bloquePar.isEmpty || !ligne.url.isEmpty
    }

    var body: some View {
        Group {
            if enEdition {
                // Aucun détecteur de clic ici : il volerait les clics destinés
                // aux boutons OK/Annuler et au champ de texte.
                editeur
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    enTete
                    if deplie { detail }
                }
                .contentShape(Rectangle())
                // Zéro latence : le simple clic bascule immédiatement, sans
                // attendre de savoir si un double suit. Si un double arrive
                // (simultaneousGesture), on annule la bascule du premier clic
                // puis on fait l'action du double — édition pour une note de
                // Vassili, ouverture de la conversation pour une fiche Claude.
                .onTapGesture { basculer() }
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    basculer()   // annule la bascule déclenchée par le 1er clic
                    if store.estAVassili(ligne) {
                        demarrerEdition()
                    } else if !ligne.url.isEmpty {
                        ouvrirLien()
                    }
                })
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button(ligne.pin ? "Désépingler" : "Épingler") {
                store.basculerEpingle(ligne)
            }
            Button(ligne.statut == .dormant ? "Réveiller" : "Mettre en sommeil") {
                store.basculerSommeil(ligne)
            }
            if !ligne.url.isEmpty {
                Button("Ouvrir la conversation") { ouvrirLien() }
            }
            Divider()
            Button(store.estAVassili(ligne) ? "Supprimer" : "Retirer de la liste",
                   role: .destructive) {
                store.supprimer(ligne)
            }
        }
    }

    private var enTete: some View {
        HStack(alignment: .center, spacing: 8) {
            iconeSource

            if enEdition {
                TextField("", text: $titreEdite)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .focused($focusEdition)
                    .onSubmit(validerEdition)
                    .onExitCommand { arreterEdition() }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ligne.titre)
                        .font(store.reglages.police(gras: ligne.pin))
                        .foregroundStyle(store.estAVassili(ligne)
                                         ? Color.primary
                                         : Color(red: 0.90, green: 0.55, blue: 0.35))
                        .lineLimit(deplie ? nil : 2)

                    if !ligne.prochaineEtape.isEmpty {
                        Text(ligne.prochaineEtape)
                            .font(store.reglages.police(delta: -2))
                            .foregroundStyle(.secondary)
                            .lineLimit(deplie ? nil : 1)
                    }
                }
            }

            Spacer(minLength: 4)

            Button { store.basculerEpingle(ligne) } label: {
                Image(systemName: ligne.pin ? "pin.fill" : "pin")
                    .font(.system(size: 10))
                    .foregroundStyle(ligne.pin ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help(ligne.pin ? "Désépingler" : "Épingler")
        }
    }

    /// Qui porte la ligne : silhouette pour Vassili, astérisque orange pour
    /// Claude — avec le statut en mini-pastille, pour ne pas perdre cette
    /// information en remplaçant l'ancienne pastille par l'icône.
    private var iconeSource: some View {
        let deVassili = store.estAVassili(ligne)
        return ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(deVassili ? Color(white: 0.85) : Color(red: 0.85, green: 0.40, blue: 0.22))
                .frame(width: 22, height: 22)
            Image(systemName: deVassili ? "person.fill" : "asterisk")
                .font(.system(size: deVassili ? 11 : 10, weight: .bold))
                .foregroundStyle(deVassili ? Color.black : Color.white)
                .frame(width: 22, height: 22)
            Circle()
                .fill(ligne.statut.couleur)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                .offset(x: 2, y: 2)
                .help(ligne.statut.libelle)
        }
    }

    private func demarrerEdition() {
        guard store.estAVassili(ligne) else { return }
        titreEdite = ligne.titre
        corpsEdite = ligne.resume
        enEdition = true
        surEdition(ligne.id)
        // Le champ n'existe pas encore à cet instant : demander le focus au
        // cycle suivant, sinon la demande tombe dans le vide.
        DispatchQueue.main.async { focusEdition = true }
    }

    private func validerEdition() {
        store.modifierNote(ligne, titre: titreEdite, corps: corpsEdite)
        arreterEdition()
    }

    /// Toutes les sorties d'édition passent par ici : sinon la liste croit
    /// qu'une ligne est encore en cours et ne réagit plus si on rouvre la même.
    private func arreterEdition() {
        enEdition = false
        surEdition(nil)
    }

    /// Éditeur en place : titre + corps de texte libre. ⌘⏎ valide (⏎ seul
    /// fait un retour à la ligne dans le corps), Échap annule.
    private var editeur: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Titre", text: $titreEdite)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .focused($focusEdition)
                .onSubmit(validerEdition)

            TextEditor(text: $corpsEdite)
                .font(.system(size: 11))
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(minHeight: 52, maxHeight: 140)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            HStack(spacing: 8) {
                Spacer()
                Button("Annuler") { arreterEdition() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("OK") { validerEdition() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .font(.caption)
            .controlSize(.small)
        }
        .padding(.leading, 2)
        .onExitCommand { arreterEdition() }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !ligne.bloquePar.isEmpty {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 9))
                    Text(ligne.bloquePar).font(store.reglages.police(delta: -2))
                }
                .foregroundStyle(.red.opacity(0.85))
            }

            if !ligne.resume.isEmpty {
                Text(ligne.resume)
                    .font(store.reglages.police(delta: -2))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !ligne.url.isEmpty {
                Button(action: ouvrirLien) {
                    Label("Ouvrir la conversation", systemImage: "arrow.up.forward.square")
                        .font(.system(size: 10))
                }
                .buttonStyle(.link)
            }
        }
        .padding(.leading, 14)
        .padding(.top, 1)
    }

    private func ouvrirLien() {
        guard let u = URL(string: ligne.url) else { return }
        NSWorkspace.shared.open(u)
    }
}
