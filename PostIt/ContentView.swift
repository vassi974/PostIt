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

// MARK: - Glissé avec retour visuel en direct

/// Réordonne dès le survol (dropEntered), pas seulement au relâchement —
/// c'est ce qui donne le ressenti "les autres lignes se décalent en direct"
/// d'un glisser natif, plutôt qu'un dépôt silencieux (06/08/2026, v4 :
/// la v3 déplaçait bien mais sans aucun retour visuel pendant le geste,
/// jugé "pas mature" — à raison).
struct LigneDropDelegate: DropDelegate {
    let ligne: Ligne
    let groupe: [Ligne]
    @Binding var idGlisse: String?
    let deplacer: (_ idSource: String, _ groupe: [Ligne], _ destination: Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let source = idGlisse, source != ligne.id,
              let depart = groupe.firstIndex(where: { $0.id == source }),
              let arrivee = groupe.firstIndex(where: { $0.id == ligne.id })
        else { return }
        let destination = depart < arrivee ? arrivee + 1 : arrivee
        withAnimation(.easeInOut(duration: 0.15)) {
            deplacer(source, groupe, destination)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        idGlisse = nil
        return true
    }
}

// MARK: - Vue principale

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var nouvelleNote = ""
    @State private var deplie: Set<String> = []
    @State private var idEnEdition: String?
    @State private var rechercheOuverte = false
    @State private var idEnGlissement: String?
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
                        // Plus de .onMove ici (06/08/2026, v3) : le glisser
                        // natif de la List, mélangé aux clics personnalisés
                        // de la ligne, ne fonctionnait qu'1 fois sur 15.
                        // Remplacé par .onDrag/.onDrop maison, posé
                        // uniquement sur la poignée ☰ de chaque ligne — voir
                        // LigneVue. Garder les deux en même temps créerait un
                        // vrai conflit entre deux systèmes de glissé.
                        ForEach(epingles) { ligne in ligneRow(ligne, groupe: epingles) }
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
                        ForEach(reste) { ligne in ligneRow(ligne, groupe: reste) }
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
    /// sections (épinglés / reste) sans dupliquer les paramètres. `groupe`
    /// sert au DropDelegate : la position de `ligne` (et de la ligne glissée)
    /// dans son propre groupe, jamais dans la liste entière.
    private func ligneRow(_ ligne: Ligne, groupe: [Ligne]) -> some View {
        LigneVue(ligne: ligne,
                 deplie: store.reglages.deplieParDefaut != deplie.contains(ligne.id),
                 basculer: {
                     if deplie.contains(ligne.id) { deplie.remove(ligne.id) }
                     else { deplie.insert(ligne.id) }
                 },
                 surEdition: { idEnEdition = $0 },
                 idGlisse: $idEnGlissement)
        .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
        .onDrop(of: [.text], delegate: LigneDropDelegate(
            ligne: ligne, groupe: groupe, idGlisse: $idEnGlissement,
            deplacer: { idSource, groupe, destination in
                guard let source = groupe.firstIndex(where: { $0.id == idSource }) else { return }
                store.deplacerDansGroupe(groupe, de: IndexSet(integer: source), vers: destination)
            }))
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
    /// Flèches puis dépôt-sur-relâchement abandonnés (06/08/2026, v3 puis
    /// v4) : Vassili voulait le ressenti d'un vrai glisser natif, avec les
    /// autres lignes qui se décalent en direct. Ce binding partagé permet à
    /// la poignée de signaler "c'est moi qu'on glisse" et à ContentView de
    /// réordonner dès le survol (LigneDropDelegate.dropEntered) plutôt qu'au
    /// relâchement seul.
    @Binding var idGlisse: String?
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
                    // 06/08/2026, fix v2 : un vrai Button plutôt qu'un geste de
                    // clic maison. Un .onTapGesture/.gesture personnalisé, même
                    // limité à l'en-tête, continuait à intercepter le mouseDown
                    // avant que la List reconnaisse un glissé (1 essai sur 15
                    // fonctionnait). Button coexiste correctement avec le
                    // réordonnancement natif de macOS — c'est le composant que
                    // SwiftUI attend pour ce cas précis.
                    Button(action: basculer) { enTete }
                        .buttonStyle(.plain)
                    if deplie { detail }
                }
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
                        // Double clic ré-attaché ici uniquement (06/08/2026,
                        // fix v2) : zone minuscule (le texte seul), pour ne
                        // jamais gêner le glissé natif de la List sur le
                        // reste de la ligne. contentShape nécessaire car le
                        // Button parent capterait sinon ce tap avant lui.
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            if store.estAVassili(ligne) {
                                demarrerEdition()
                            } else if !ligne.url.isEmpty {
                                ouvrirLien()
                            }
                        }

                    if !ligne.prochaineEtape.isEmpty {
                        Text(ligne.prochaineEtape)
                            .font(store.reglages.police(delta: -2))
                            .foregroundStyle(.secondary)
                            .lineLimit(deplie ? nil : 1)
                    }
                }
            }

            Spacer(minLength: 4)

            // Poignée de glissé : seule cette icône déclenche .onDrag — pas
            // la ligne entière. C'est ce qui règle le conflit avec les autres
            // clics (Button pour déplier, double-clic sur le titre pour
            // éditer) : le glissé n'a plus qu'une seule petite zone dédiée à
            // interpréter, il ne se dispute plus rien avec le reste.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.5))
                .padding(.horizontal, 2)
                .onDrag {
                    idGlisse = ligne.id
                    return NSItemProvider(object: ligne.id as NSString)
                }

            Button { store.basculerEpingle(ligne) } label: {
                Image(systemName: ligne.pin ? "pin.fill" : "pin")
                    .font(.system(size: 10))
                    .foregroundStyle(ligne.pin ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help(ligne.pin ? "Désépingler" : "Épingler")
        }
        // Ligne d'origine estompée pendant le glissé : avec le déplacement
        // en direct au survol (dropEntered dans ContentView), elle glisse
        // déjà de position toute seule — l'estompage confirme visuellement
        // laquelle est "en main", comme le ferait une List native.
        .opacity(idGlisse == ligne.id ? 0.35 : 1)
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
