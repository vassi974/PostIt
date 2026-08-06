import Cocoa

/// Détecte un double clic sur le bouton du milieu (molette), n'importe où sur
/// macOS — geste dédié pour basculer la fenêtre PostIt. Choisi précisément
/// parce que le double clic droit est déjà pris par ClipboardDoubleClick :
/// réutiliser le même geste ferait que les deux apps se disputent le même
/// événement système, sans garantie de qui gagne. Le bouton du milieu n'a
/// quasiment aucun usage standard sous macOS — terrain libre.
///
/// Nécessite la permission Accessibilité (comme tout CGEventTap global) :
/// Réglages Système → Confidentialité et sécurité → Accessibilité.
///
/// Pas de @MainActor ici : le callback du tap est une fonction C
/// (@convention(c)), incompatible avec l'isolation d'acteur. Le passage sur
/// le thread principal se fait explicitement au moment d'appeler `surDoubleClic`.
final class MiddleClickTap {
    static let shared = MiddleClickTap()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var dernierClicMilieu: Date?
    private let fenetreDouble: TimeInterval = 0.4  // secondes entre les 2 clics

    var surDoubleClic: (() -> Void)?

    private init() {}

    /// Démarre l'écoute globale. Sans permission Accessibilité, `tapCreate`
    /// échoue silencieusement — on prévient plutôt que de laisser l'app
    /// paraître cassée sans explication.
    func demarrer() {
        guard demanderPermission() else {
            print("MiddleClickTap : permission Accessibilité manquante, en attente.")
            return
        }
        creerLeTap()
    }

    private func creerLeTap() {
        let masque = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: masque,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let capteur = Unmanaged<MiddleClickTap>.fromOpaque(refcon).takeUnretainedValue()
                return capteur.traiter(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("MiddleClickTap : impossible de créer le tap.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// N'avale que le 2e clic d'un double clic milieu rapproché — évite un
    /// effet de bord dans l'app au premier plan (ex. fermer un onglet de
    /// navigateur, action fréquente sur clic milieu). Un simple clic milieu
    /// isolé, ou le 1er clic d'une paire, continue son chemin normalement.
    private func traiter(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .otherMouseDown else { return Unmanaged.passRetained(event) }
        let bouton = event.getIntegerValueField(.mouseEventButtonNumber)
        guard bouton == 2 else { return Unmanaged.passRetained(event) }  // 2 = milieu

        let maintenant = Date()
        defer { dernierClicMilieu = maintenant }

        if let dernier = dernierClicMilieu, maintenant.timeIntervalSince(dernier) < fenetreDouble {
            dernierClicMilieu = nil
            let callback = surDoubleClic
            DispatchQueue.main.async { callback?() }
            return nil  // avalé : n'atteint jamais l'app au premier plan
        }
        return Unmanaged.passRetained(event)
    }

    /// `kAXTrustedCheckOptionPrompt: true` affiche automatiquement la boîte
    /// de dialogue système la première fois — pas besoin de la construire
    /// à la main.
    @discardableResult
    private func demanderPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
