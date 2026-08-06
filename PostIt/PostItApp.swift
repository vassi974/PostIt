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
    /// Clic gauche = bascule la fenêtre. Clic droit = menu avec "Quitter" —
    /// seul moyen de vraiment fermer l'app, puisque la croix rouge et ⌘W ne
    /// font plus que masquer (même principe que TurzxDeck).
    private func creerIconeBarreMenus() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let bouton = item.button {
            bouton.image = NSImage(systemSymbolName: "note.text",
                                   accessibilityDescription: "Post-it")
            bouton.action = #selector(clicIconeBarreMenus(_:))
            bouton.target = self
            bouton.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        itemBarreMenus = item
    }

    @objc private func clicIconeBarreMenus(_ sender: NSStatusBarButton) {
        guard let evenement = NSApp.currentEvent else { return }
        if evenement.type == .rightMouseUp {
            afficherMenuBarreMenus()
        } else {
            basculerVisibilite()
        }
    }

    private func afficherMenuBarreMenus() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Ouvrir Post-it",
                                action: #selector(basculerVisibilite), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quitter",
                                action: #selector(quitterVraiment), keyEquivalent: ""))
        for entree in menu.items { entree.target = self }

        itemBarreMenus?.menu = menu
        itemBarreMenus?.button?.performClick(nil)
        itemBarreMenus?.menu = nil  // sinon le clic gauche rouvre le menu au lieu de basculer
    }

    @objc private func quitterVraiment() {
        NSApp.terminate(nil)
    }

    /// Montre la fenêtre si elle est cachée ou en arrière-plan ; la cache si
    /// elle est déjà au premier plan — un double clic milieu suffit dans les
    /// deux sens, pas besoin d'un geste différent pour fermer.
    @objc private func basculerVisibilite() {
        guard let w = fenetre else { return }
        if w.isVisible && NSApp.isActive {
            w.orderOut(nil)
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
        }
    }

    /// La croix rouge et ⌘W ne ferment plus vraiment l'app : la fenêtre se
    /// masque et l'icône Dock disparaît (seule l'icône barre de menus reste),
    /// même principe que TurzxDeck. Vrai quitter : clic droit sur l'icône
    /// barre de menus → Quitter.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }

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
