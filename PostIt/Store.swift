import Foundation
import SwiftUI

/// Source de vérité de l'app.
///
/// Règle d'or : **un fichier, un propriétaire.**
/// - `claude.json` (et tout autre fichier source) est lu, jamais écrit.
/// - `vassili.json` et `affichage.json` sont écrits par l'app seule.
/// Personne ne peut donc écraser le travail d'un autre.
@MainActor
final class Store: ObservableObject {

    static let dossier = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/Memoire Claude/postit", isDirectory: true)

    static let fichierVassili = dossier.appendingPathComponent("vassili.json")
    static let fichierAffichage = dossier.appendingPathComponent("affichage.json")

    /// Lignes fusionnées, filtrées et triées — ce que la vue affiche.
    @Published private(set) var lignes: [Ligne] = []
    @Published var reglages = ReglagesFenetre()
    @Published private(set) var erreur: String? = nil

    private var sources: [String: [Ligne]] = [:]   // nom de fichier -> lignes
    private var affichage = FichierAffichage()
    private var empreintes: [String: Date] = [:]   // nom de fichier -> date de modif
    private var minuteur: Timer?

    init() {
        recharger()
        demarrerSurveillance()
    }

    // MARK: - Lecture

    /// Relit tous les fichiers du dossier et recompose la liste.
    func recharger() {
        let fm = FileManager.default
        guard let contenu = try? fm.contentsOfDirectory(
            at: Self.dossier, includingPropertiesForKeys: nil) else {
            erreur = "Dossier introuvable : \(Self.dossier.path)"
            return
        }

        sources.removeAll()
        var soucis: [String] = []

        for url in contenu where url.pathExtension == "json" {
            let nom = url.lastPathComponent
            guard let data = try? Data(contentsOf: url) else { continue }

            if nom == "affichage.json" {
                if let f = try? JSONDecoder().decode(FichierAffichage.self, from: data) {
                    affichage = f
                    reglages = f.fenetre
                } else {
                    soucis.append(nom)
                }
            } else {
                // Toute autre source suit le même schéma : claude.json, vassili.json,
                // et demain agents.json sans une ligne de code de plus.
                if let f = try? JSONDecoder().decode(FichierSource.self, from: data) {
                    sources[nom] = f.lignes
                } else {
                    soucis.append(nom)
                }
            }
        }

        erreur = soucis.isEmpty ? nil : "Fichier illisible : \(soucis.joined(separator: ", "))"
        recomposer()
    }

    // MARK: - Fusion et tri

    private func recomposer() {
        var toutes = sources.values.flatMap { $0 }

        // 1. Overrides de Vassili : épinglage et niveau d'affichage. Dans les
        //    deux cas, le geste le plus récent gagne — donc si Claude met à
        //    jour une fiche APRÈS la mise en sommeil (ex. dossier débloqué),
        //    c'est la fiche qui l'emporte et elle réapparaît. Voulu.
        for i in toutes.indices {
            if let ov = affichage.pinOverrides[toutes[i].id] {
                let dSource = Horodatage.date(toutes[i].pinMaj) ?? .distantPast
                let dOverride = Horodatage.date(ov.pinMaj) ?? .distantPast
                if dOverride >= dSource {
                    toutes[i].pin = ov.pin
                    toutes[i].pinMaj = ov.pinMaj
                }
            }
            if let so = affichage.statutOverrides[toutes[i].id],
               let statut = Statut(rawValue: so.statut) {
                let dSource = Horodatage.date(toutes[i].maj) ?? .distantPast
                let dOverride = Horodatage.date(so.maj) ?? .distantPast
                if dOverride >= dSource {
                    toutes[i].statut = statut
                }
            }
        }

        // 2. Retirées : masquage explicite (lignes Claude) et corbeille (notes)
        toutes.removeAll { affichage.masques.contains($0.id) || $0.corbeille }

        // 3. Filtres de confort (les lignes épinglées passent outre : si c'est
        //    épinglé, c'est que quelqu'un veut le voir).
        toutes.removeAll { l in
            guard !l.pin else { return false }
            if l.statut == .dormant && !reglages.afficherDormants { return true }
            if l.statut == .termine && !reglages.afficherTermines { return true }
            return false
        }

        lignes = trier(toutes)
    }

    /// Épinglés d'abord. Dans chaque groupe : l'ordre manuel s'il existe, sinon
    /// priorité puis date de mise à jour. Une ligne jamais vue arrive **en bas**
    /// de son groupe : elle ne doit pas bousculer un ordre choisi à la main.
    private func trier(_ entree: [Ligne]) -> [Ligne] {
        let rang = Dictionary(uniqueKeysWithValues:
            affichage.ordreManuel.enumerated().map { ($0.element, $0.offset) })

        func avant(_ a: Ligne, _ b: Ligne) -> Bool {
            if a.pin != b.pin { return a.pin }
            let ra = rang[a.id], rb = rang[b.id]
            switch (ra, rb) {
            case let (x?, y?): return x < y
            case (_?, nil):    return true
            case (nil, _?):    return false
            default: break
            }
            if a.priorite != b.priorite { return a.priorite < b.priorite }
            let da = Horodatage.date(a.maj) ?? .distantPast
            let db = Horodatage.date(b.maj) ?? .distantPast
            if da != db { return da > db }
            return a.titre.localizedCaseInsensitiveCompare(b.titre) == .orderedAscending
        }

        return entree.sorted(by: avant)
    }

    /// Vrai si la ligne vient d'un fichier que l'app a le droit de modifier.
    func estAVassili(_ ligne: Ligne) -> Bool {
        sources["vassili.json"]?.contains { $0.id == ligne.id } ?? false
    }

    // MARK: - Écriture atomique

    /// Fichier temporaire puis `replaceItemAt` : une interruption ne peut pas
    /// laisser un JSON tronqué sur le disque. Même technique que ChapterMark.
    private func ecrire<T: Encodable>(_ valeur: T, vers url: URL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? enc.encode(valeur) else {
            erreur = "Encodage impossible : \(url.lastPathComponent)"
            return
        }
        let tmp = Self.dossier.appendingPathComponent(".postit-\(UUID().uuidString).tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: url)
            }
            noterEmpreinte(url)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            erreur = "Écriture impossible : \(url.lastPathComponent)"
        }
    }

    private func sauverAffichage() {
        affichage.maj = Horodatage.maintenant()
        affichage.fenetre = reglages
        ecrire(affichage, vers: Self.fichierAffichage)
        recomposer()
    }

    private func sauverVassili() {
        var f = FichierSource()
        f.source = "vassili"
        f.maj = Horodatage.maintenant()
        f.lignes = sources["vassili.json"] ?? []
        ecrire(f, vers: Self.fichierVassili)
        recomposer()
    }

    // MARK: - Gestes de l'utilisateur

    /// Épingle ou désépingle **n'importe quelle** ligne, quelle que soit sa source.
    /// On n'écrit jamais dans le fichier d'un autre : le geste va dans l'override.
    func basculerEpingle(_ ligne: Ligne) {
        affichage.pinOverrides[ligne.id] = PinOverride(
            pin: !ligne.pin, pinMaj: Horodatage.maintenant())
        sauverAffichage()
    }

    /// Retire une ligne de l'affichage. Une note de Vassili part à la corbeille
    /// (conservée, restaurable) ; une ligne d'une autre source est masquée —
    /// son fichier d'origine reste intact. Dans les deux cas : rien de perdu.
    func supprimer(_ ligne: Ligne) {
        if estAVassili(ligne) {
            if let i = sources["vassili.json"]?.firstIndex(where: { $0.id == ligne.id }) {
                sources["vassili.json"]?[i].corbeille = true
                sources["vassili.json"]?[i].maj = Horodatage.maintenant()
            }
            sauverVassili()
        } else {
            if !affichage.masques.contains(ligne.id) { affichage.masques.append(ligne.id) }
            sauverAffichage()
        }
    }

    // MARK: - Restauration

    /// Tout ce qui a été retiré de l'affichage, toutes sources confondues.
    var lignesRetirees: [Ligne] {
        var resultat: [Ligne] = []
        for (nom, lignes) in sources {
            for l in lignes {
                if nom == "vassili.json" ? l.corbeille : affichage.masques.contains(l.id) {
                    resultat.append(l)
                }
            }
        }
        return resultat.sorted {
            $0.titre.localizedCaseInsensitiveCompare($1.titre) == .orderedAscending
        }
    }

    func restaurer(_ ligne: Ligne) {
        if let i = sources["vassili.json"]?.firstIndex(where: { $0.id == ligne.id }) {
            sources["vassili.json"]?[i].corbeille = false
            sources["vassili.json"]?[i].maj = Horodatage.maintenant()
            sauverVassili()
        }
        if affichage.masques.contains(ligne.id) {
            affichage.masques.removeAll { $0 == ligne.id }
            sauverAffichage()
        }
        recomposer()
    }

    func toutRestaurer() {
        for l in lignesRetirees { restaurer(l) }
    }

    func ajouterNote(_ titre: String) {
        let texte = titre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty else { return }
        var ligne = Ligne(id: "v-\(UUID().uuidString.prefix(8))", titre: texte, statut: .actif)
        ligne.maj = Horodatage.maintenant()
        ligne.pinMaj = ligne.maj
        ligne.priorite = 1
        sources["vassili.json", default: []].append(ligne)
        sauverVassili()
    }

    func renommerNote(_ ligne: Ligne, en titre: String) {
        modifierNote(ligne, titre: titre, corps: ligne.resume)
    }

    /// Édition complète d'une note : titre + corps de texte libre.
    /// Réservé aux notes de Vassili — les fiches Claude s'éditent en conversation.
    func modifierNote(_ ligne: Ligne, titre: String, corps: String) {
        let t = titre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, estAVassili(ligne) else { return }
        guard let i = sources["vassili.json"]?.firstIndex(where: { $0.id == ligne.id }) else { return }
        sources["vassili.json"]?[i].titre = t
        sources["vassili.json"]?[i].resume = corps.trimmingCharacters(in: .whitespacesAndNewlines)
        sources["vassili.json"]?[i].maj = Horodatage.maintenant()
        sauverVassili()
    }

    /// Réordonne un sous-ensemble précis (épinglés OU reste) après un
    /// glisser-déposer dans ce groupe, puis recompose l'ordre global en
    /// concaténant épinglés + reste. Nécessaire depuis la séparation
    /// visuelle en deux blocs (06/08/2026) : l'IndexSet fourni par onMove
    /// est relatif au sous-groupe affiché, pas à `lignes` en entier — lui
    /// appliquer directement décalait les lignes vers le mauvais groupe.
    func deplacerDansGroupe(_ groupe: [Ligne], de source: IndexSet, vers destination: Int) {
        var reordonne = groupe
        reordonne.move(fromOffsets: source, toOffset: destination)

        let idsGroupe = Set(groupe.map(\.id))
        let autres = lignes.filter { !idsGroupe.contains($0.id) }

        // Reconstitue l'ordre complet dans le même sens que l'affichage :
        // épinglés d'abord, puis le reste — peu importe quel groupe vient
        // d'être réordonné.
        let epinglesFinal = reordonne.first?.pin == true ? reordonne : autres.filter(\.pin) + reordonne
        let resteFinal = reordonne.first?.pin == true ? autres.filter { !$0.pin } : reordonne

        affichage.ordreManuel = (epinglesFinal + resteFinal).map(\.id)
        sauverAffichage()
    }

    func basculerFiltre(dormants: Bool? = nil, termines: Bool? = nil) {
        if let d = dormants { reglages.afficherDormants = d }
        if let t = termines { reglages.afficherTermines = t }
        sauverAffichage()
    }

    /// Niveau d'affichage choisi par Vassili : actif (visible) ou dormant
    /// (masqué, récupérable via la case Sommeil). Vassili pilote ce niveau
    /// pour TOUTES les lignes ; comme pour l'épinglage, le geste passe par un
    /// override — on n'écrit jamais dans le fichier d'une autre source.
    func basculerSommeil(_ ligne: Ligne) {
        let nouveau: Statut = ligne.statut == .dormant ? .actif : .dormant
        if estAVassili(ligne) {
            if let i = sources["vassili.json"]?.firstIndex(where: { $0.id == ligne.id }) {
                sources["vassili.json"]?[i].statut = nouveau
                sources["vassili.json"]?[i].maj = Horodatage.maintenant()
            }
            sauverVassili()
        } else {
            affichage.statutOverrides[ligne.id] = StatutOverride(
                statut: nouveau.rawValue, maj: Horodatage.maintenant())
            sauverAffichage()
        }
    }

    /// Appelé par la fenêtre Réglages après modification du texte/comportement.
    func sauverReglages() {
        sauverAffichage()
    }

    func enregistrerFenetre(x: Double, y: Double, largeur: Double, hauteur: Double) {
        reglages.x = x; reglages.y = y
        reglages.largeur = largeur; reglages.hauteur = hauteur
        sauverAffichage()
    }

    func basculerToujoursDevant() {
        reglages.toujoursDevant.toggle()
        sauverAffichage()
    }

    // MARK: - Surveillance du dossier

    /// Comparaison des dates de modification toutes les deux secondes.
    /// FSEvents serait plus élégant mais ne voit pas toujours un `replaceItemAt`
    /// venu d'un autre processus ; sur trois petits fichiers, un `stat` périodique
    /// coûte moins qu'un rendu SwiftUI et ne rate rien.
    private func demarrerSurveillance() {
        noterToutesLesEmpreintes()
        minuteur = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.verifierChangements() }
        }
    }

    private func noterEmpreinte(_ url: URL) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        empreintes[url.lastPathComponent] = attrs?[.modificationDate] as? Date
    }

    private func noterToutesLesEmpreintes() {
        guard let contenu = try? FileManager.default.contentsOfDirectory(
            at: Self.dossier, includingPropertiesForKeys: nil) else { return }
        for url in contenu where url.pathExtension == "json" { noterEmpreinte(url) }
    }

    private func verifierChangements() {
        guard let contenu = try? FileManager.default.contentsOfDirectory(
            at: Self.dossier, includingPropertiesForKeys: nil) else { return }

        var courantes: [String: Date] = [:]
        for url in contenu where url.pathExtension == "json" {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            courantes[url.lastPathComponent] = attrs?[.modificationDate] as? Date
        }

        if courantes != empreintes {
            empreintes = courantes
            recharger()
        }
    }

    deinit { minuteur?.invalidate() }
}
