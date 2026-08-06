import Foundation
import SQLite3

/// Recherche plein texte dans l'archive exportée officiellement (Réglages >
/// Confidentialité > Export data sur claude.ai). Lecture seule : cette classe
/// n'écrit jamais dans l'index, elle est reconstruite par
/// ~/Scripts/indexer_archives.py.
struct ResultatRecherche: Identifiable {
    var id: String { convUUID + String(rowid) }
    let rowid: Int64
    let convUUID: String
    let titre: String
    let auteur: String
    let extrait: String
}

final class ArchiveRecherche {
    private static let chemin = NSString(string:
        "~/Documents/Memoire Claude/archives-conversations/index.sqlite"
    ).expandingTildeInPath

    static var disponible: Bool {
        FileManager.default.fileExists(atPath: chemin)
    }

    /// Recherche floue : le tokenizer 'porter' de l'index regroupe déjà les
    /// familles de mots (bloqué/blocage/bloquant). Ici on ajoute la
    /// tolérance aux mots partiels avec un préfixe sur chaque terme.
    static func rechercher(_ requete: String, limite: Int = 30) -> [ResultatRecherche] {
        let mots = requete
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
        guard !mots.isEmpty else { return [] }
        let motsFTS = mots.map { "\"\($0)\"*" }.joined(separator: " ")

        var db: OpaquePointer?
        guard sqlite3_open_v2(chemin, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT m.rowid, c.uuid, c.titre, m.auteur,
                   snippet(messages, 2, '⟦', '⟧', '…', 10)
            FROM messages m JOIN conversations c ON c.uuid = m.conv_uuid
            WHERE messages MATCH ?
            ORDER BY rank
            LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, motsFTS, -1, SQLITE_TRANSIENT_SWIFT)
        sqlite3_bind_int(stmt, 2, Int32(limite))

        var resultats: [ResultatRecherche] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            resultats.append(ResultatRecherche(
                rowid: sqlite3_column_int64(stmt, 0),
                convUUID: String(cString: sqlite3_column_text(stmt, 1)),
                titre: String(cString: sqlite3_column_text(stmt, 2)),
                auteur: String(cString: sqlite3_column_text(stmt, 3)),
                extrait: String(cString: sqlite3_column_text(stmt, 4))
            ))
        }
        return resultats
    }
}

private let SQLITE_TRANSIENT_SWIFT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
