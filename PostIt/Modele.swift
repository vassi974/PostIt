import Foundation

// MARK: - Statut

enum Statut: String, Codable, CaseIterable {
    case actif, bloque, en_attente, dormant, termine

    var libelle: String {
        switch self {
        case .actif:      return "En cours"
        case .bloque:     return "Bloqué"
        case .en_attente: return "En attente"
        case .dormant:    return "En sommeil"
        case .termine:    return "Terminé"
        }
    }

    /// Masqué par défaut dans la fenêtre.
    var discret: Bool { self == .dormant || self == .termine }
}

// MARK: - Ligne

/// Une ligne du post-it, quelle que soit sa source.
/// Le schéma est volontairement identique pour Claude, Vassili et les agents :
/// une nouvelle source se branche sans toucher au reste.
struct Ligne: Codable, Identifiable, Equatable {
    var id: String
    var titre: String
    var statut: Statut
    var resume: String = ""
    var prochaineEtape: String = ""
    var bloquePar: String = ""
    var url: String = ""
    var pin: Bool = false
    var pinMaj: String = ""
    var maj: String = ""
    var priorite: Int = 2
    /// Notes de Vassili uniquement : retirée de l'affichage mais conservée,
    /// restaurable depuis le menu — rien ne doit être perdable.
    var corbeille: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, titre, statut, resume, url, pin, priorite, corbeille
        case prochaineEtape = "prochaine_etape"
        case bloquePar = "bloque_par"
        case pinMaj = "pin_maj"
        case maj
    }
}

// MARK: - Fichier source

/// Forme commune à claude.json, vassili.json et tout futur agents.json.
struct FichierSource: Codable {
    var version: Int = 1
    var source: String = ""
    var maj: String = ""
    var lignes: [Ligne] = []
}

// MARK: - Couche d'affichage

struct PinOverride: Codable, Equatable {
    var pin: Bool
    var pinMaj: String

    enum CodingKeys: String, CodingKey {
        case pin
        case pinMaj = "pin_maj"
    }
}

/// Niveau d'affichage imposé par Vassili sur une ligne d'une autre source
/// (typiquement : mettre en sommeil / réveiller une fiche Claude).
/// Même principe que PinOverride : le geste le plus récent gagne.
struct StatutOverride: Codable, Equatable {
    var statut: String
    var maj: String
}

struct ReglagesFenetre: Codable, Equatable {
    var x: Double? = nil
    var y: Double? = nil
    var largeur: Double = 380
    var hauteur: Double = 560
    var toujoursDevant: Bool = true
    var afficherDormants: Bool = false
    var afficherTermines: Bool = false
    // Réglages texte (fenêtre Réglages, ⌘,)
    var taillePolice: Double = 12
    var policeNom: String = ""          // "" = police système
    var deplieParDefaut: Bool = true

    enum CodingKeys: String, CodingKey {
        case x, y, largeur, hauteur
        case toujoursDevant = "toujours_devant"
        case afficherDormants = "afficher_dormants"
        case afficherTermines = "afficher_termines"
        case taillePolice = "taille_police"
        case policeNom = "police"
        case deplieParDefaut = "deplie_par_defaut"
    }
}

/// Écrit par l'app seule. Porte les gestes de Vassili sur **toutes** les lignes,
/// y compris celles de Claude, sans jamais modifier le fichier d'une autre source.
struct FichierAffichage: Codable {
    var version: Int = 1
    var source: String = "affichage"
    var maj: String = ""
    var pinOverrides: [String: PinOverride] = [:]
    var statutOverrides: [String: StatutOverride] = [:]
    var ordreManuel: [String] = []
    var masques: [String] = []
    var fenetre: ReglagesFenetre = ReglagesFenetre()

    enum CodingKeys: String, CodingKey {
        case version, source, maj, masques, fenetre
        case pinOverrides = "pin_overrides"
        case statutOverrides = "statut_overrides"
        case ordreManuel = "ordre_manuel"
    }
}

// MARK: - Horodatage

enum Horodatage {
    private static let formateur: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func maintenant() -> String {
        formateur.string(from: Date())
    }

    /// Nil si la chaîne est vide ou illisible : l'appelant décide quoi en faire.
    static func date(_ s: String) -> Date? {
        s.isEmpty ? nil : formateur.date(from: s)
    }
}

// MARK: - Décodage tolérant

// Une source ne doit avoir à fournir que `id` et `titre`. Tout le reste est
// facultatif : un watchdog qui pousse une alerte en deux lignes doit marcher
// sans connaître le schéma complet. Les inits sont en extension pour garder
// l'initialiseur mémberwise synthétisé.

extension Statut {
    init(from decoder: Decoder) throws {
        let brut = try decoder.singleValueContainer().decode(String.self)
        self = Statut(rawValue: brut) ?? .actif
    }
}

extension Ligne {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        titre = try c.decodeIfPresent(String.self, forKey: .titre) ?? id
        statut = try c.decodeIfPresent(Statut.self, forKey: .statut) ?? .actif
        resume = try c.decodeIfPresent(String.self, forKey: .resume) ?? ""
        prochaineEtape = try c.decodeIfPresent(String.self, forKey: .prochaineEtape) ?? ""
        bloquePar = try c.decodeIfPresent(String.self, forKey: .bloquePar) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        pin = try c.decodeIfPresent(Bool.self, forKey: .pin) ?? false
        pinMaj = try c.decodeIfPresent(String.self, forKey: .pinMaj) ?? ""
        maj = try c.decodeIfPresent(String.self, forKey: .maj) ?? ""
        priorite = try c.decodeIfPresent(Int.self, forKey: .priorite) ?? 2
        corbeille = try c.decodeIfPresent(Bool.self, forKey: .corbeille) ?? false
    }
}

extension FichierSource {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        maj = try c.decodeIfPresent(String.self, forKey: .maj) ?? ""
        lignes = try c.decodeIfPresent([Ligne].self, forKey: .lignes) ?? []
    }
}

extension ReglagesFenetre {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decodeIfPresent(Double.self, forKey: .x)
        y = try c.decodeIfPresent(Double.self, forKey: .y)
        largeur = try c.decodeIfPresent(Double.self, forKey: .largeur) ?? 380
        hauteur = try c.decodeIfPresent(Double.self, forKey: .hauteur) ?? 560
        toujoursDevant = try c.decodeIfPresent(Bool.self, forKey: .toujoursDevant) ?? true
        afficherDormants = try c.decodeIfPresent(Bool.self, forKey: .afficherDormants) ?? false
        afficherTermines = try c.decodeIfPresent(Bool.self, forKey: .afficherTermines) ?? false
        taillePolice = try c.decodeIfPresent(Double.self, forKey: .taillePolice) ?? 12
        policeNom = try c.decodeIfPresent(String.self, forKey: .policeNom) ?? ""
        deplieParDefaut = try c.decodeIfPresent(Bool.self, forKey: .deplieParDefaut) ?? true
    }
}

extension FichierAffichage {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "affichage"
        maj = try c.decodeIfPresent(String.self, forKey: .maj) ?? ""
        pinOverrides = try c.decodeIfPresent([String: PinOverride].self, forKey: .pinOverrides) ?? [:]
        statutOverrides = try c.decodeIfPresent([String: StatutOverride].self, forKey: .statutOverrides) ?? [:]
        ordreManuel = try c.decodeIfPresent([String].self, forKey: .ordreManuel) ?? []
        masques = try c.decodeIfPresent([String].self, forKey: .masques) ?? []
        fenetre = try c.decodeIfPresent(ReglagesFenetre.self, forKey: .fenetre) ?? ReglagesFenetre()
    }
}
