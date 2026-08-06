import SwiftUI
import AppKit
import Combine

@main
struct PostItApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegue
    @StateObject private var store = Store()

    var body: some Scene {
        // Scène `Window` et non `WindowGroup` : une seule fenêtre, jamais de
        // duplication (piège vécu sur ChapterMark v1.4).
        Window("Post-it", id: "postit") {
            ContentView()
                .environmentObject(store)
                .onAppear { delegue.store = store }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .windowArrangement) {
                Button("Recharger") { store.recharger() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            ReglagesView()
                .environmentObject(store)
        }
    }
}

// MARK: - Délégué d'application

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var store: Store? {
        didSet { suivreReglages() }
    }
    private var fenetre: NSWindow?
    private var observation: NSObjectProtocol?
    private var abonnement: AnyCancellable?
    private var itemBarreMenus: NSStatusItem?

    /// Le bouton punaise ne fait que modifier `reglages` : sans cet abonnement,
    /// personne ne redemandait à la fenêtre de changer de niveau, et elle
    /// restait figée sur l'état lu au lancement.
    private func suivreReglages() {
        abonnement = store?.$reglages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] r in self?.appliquerReglages(r) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // La fenêtre n'existe pas encore au tout premier instant : on attend
        // qu'elle soit posée avant de lui appliquer niveau, taille et position.
        DispatchQueue.main.async { [weak self] in self?.attacher() }

        creerIconeBarreMenus()

        MiddleClickTap.shared.surDoubleClic = { [weak self] in self?.basculerVisibilite() }
        MiddleClickTap.shared.demarrer()
    }

    /// Icône permanente dans la barre de menus : ne demande aucune permission
    /// spéciale, contrairement au double clic milieu qui dépend de
    /// l'Accessibilité — donc toujours disponible même si cette dernière
    /// n'a pas encore été accordée ou a été retirée par erreur.
    private func creerIconeBarreMenus() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let bouton = item.button {
            bouton.image = NSImage(systemSymbolName: "note.text",
                                   accessibilityDescription: "Post-it")
            bouton.action = #selector(basculerDepuisBarreMenus)
            bouton.target = self
        }
        itemBarreMenus = item
    }

    @objc private func basculerDepuisBarreMenus() {
        basculerVisibilite()
    }

    /// Montre la fenêtre si elle est cachée ou en arrière-plan ; la cache si
    /// elle est déjà au premier plan — un double clic milieu suffit dans les
    /// deux sens, pas besoin d'un geste différent pour fermer.
    private func basculerVisibilite() {
        guard let w = fenetre else { return }
        if w.isVisible && NSApp.isActive {
            w.orderOut(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    private func attacher() {
        guard let w = NSApplication.shared.windows.first else { return }
        fenetre = w
        w.delegate = self
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.standardWindowButton(.zoomButton)?.isHidden = true

        // Géométrie posée une seule fois, au démarrage. La remettre à chaque
        // changement de réglage ferait sauter la fenêtre à son ancienne place
        // dès qu'on coche une case en pied de liste.
        if let r = store?.reglages {
            var cadre = w.frame
            cadre.size = NSSize(width: r.largeur, height: r.hauteur)
            if let x = r.x, let y = r.y { cadre.origin = NSPoint(x: x, y: y) }
            w.setFrame(cadre, display: true)
            appliquerReglages(r)
        }
    }

    /// Niveau de fenêtre uniquement : c'est la seule chose qui doit suivre les
    /// réglages en direct.
    private func appliquerReglages(_ r: ReglagesFenetre) {
        guard let w = fenetre else { return }

        w.level = r.toujoursDevant ? .floating : .normal
        w.collectionBehavior = r.toujoursDevant
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.fullScreenAuxiliary]
    }

    /// Position et taille écrites au repos, pas pendant le déplacement :
    /// inutile de solliciter le disque à chaque pixel.
    func windowDidEndLiveResize(_ notification: Notification) { memoriser() }
    func windowDidMove(_ notification: Notification) { memoriser() }

    private func memoriser() {
        guard let w = fenetre, let s = store else { return }
        s.enregistrerFenetre(x: w.frame.origin.x, y: w.frame.origin.y,
                             largeur: w.frame.width, hauteur: w.frame.height)
    }
}
