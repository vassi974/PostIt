# PostIt — pense-bête permanent

☕ [buymeacoffee.com/vassi974](https://buymeacoffee.com/vassi974) · [🇫🇷 Français](#français) · [🇬🇧 English](#english)

---

## Français

Fenêtre flottante macOS + bandeau pour écran USB TURZX, conçue pour ne plus perdre le fil
entre une dizaine de dossiers en cours à la fois — notes personnelles et suivi de conversations
Claude mélangés dans une seule liste.

Dev perso, partagé avec le cœur — si l'outil te sert, un café est toujours apprécié :
☕ [buymeacoffee.com/vassi974](https://buymeacoffee.com/vassi974)

### Le principe

Trois fichiers JSON en source de vérité (`~/Documents/Memoire Claude/postit/`), chacun avec un
seul propriétaire :

- `claude.json` — dossiers suivis par Claude (statut, prochaine étape, ce qui bloque, lien
  direct vers la conversation d'origine)
- `vassili.json` — notes libres saisies dans l'app
- `affichage.json` — épinglage, ordre manuel, réglages de fenêtre — écrit par l'app seule

Personne n'écrit dans le fichier d'un autre. L'app fusionne les trois à l'affichage.

### Installation rapide (.dmg)

Télécharge le `.dmg` depuis la page [Releases](../../releases) de ce repo, ouvre-le, glisse
`PostIt.app` dans `Applications`, puis lance l'app.

L'app n'est pas notariée par Apple (pas de compte développeur payant) : au premier lancement,
macOS va probablement dire qu'elle vient d'un développeur non identifié. Fais un **clic droit
sur l'app > Ouvrir** (au lieu d'un double-clic normal) pour autoriser l'exception, une seule
fois.

### Ce qui est implémenté

- **Trois sources fusionnées** (`Store.swift`) : lecture de tous les fichiers JSON du dossier,
  fusion en une liste unique, tri épinglés d'abord puis priorité/date, surveillance du dossier
  toutes les 2s pour se rafraîchir sans redémarrage.
- **Séparation visuelle épinglés/reste** (`ContentView.swift`) : bloc teinté distinct pour les
  épinglés, header "AUTRES" pour le reste — glisser-déposer indépendant dans chaque bloc.
- **Édition en place** des notes personnelles (titre + corps de texte libre), double-clic pour
  ouvrir l'éditeur, double-clic sur une fiche Claude pour ouvrir directement la conversation
  d'origine via `claude://claude.ai/chat/<uuid>`.
- **Sommeil / réveil / corbeille** : rien n'est jamais perdu — une note supprimée part en
  corbeille restaurable, une fiche masquée reste dans son fichier d'origine.
- **Réglages texte** (`ReglagesView.swift`) : police (parmi celles installées), taille,
  déplié par défaut — persistés dans `affichage.json`.
- **Recherche plein texte** (`ArchiveRecherche.swift`) : requête directe en SQLite (FTS5,
  tokenizer 'porter') sur une archive de conversations Claude construite depuis l'export
  officiel du compte — aucune clé de session, aucun accès tiers au compte.
- **Bandeau écran USB TURZX** (`~/Scripts/postit_bandeau.py`, hors de ce repo) : génère un
  PNG transparent des lignes épinglées, régénéré toutes les 20s par LaunchAgent, se recale
  automatiquement sur le bon widget même après réimport dans l'éditeur TurzxDeck.

### Pas encore fait

- Icône de fenêtre custom pour le champ de recherche (actuellement loupe système agrandie).
- Widget natif dans TurzxDeck plutôt qu'une image PNG régénérée en boucle — fonctionne, mais
  un vrai widget « liste » serait plus propre.
- Mise à jour automatique de l'archive de recherche : c'est un geste manuel (relancer un export
  Anthropic + `indexer_archives.py`), pas du temps réel.

### Comment builder

```
cd PostIt
xcodebuild -project PostIt.xcodeproj -target PostIt -configuration Release build
```

Nécessite Xcode. Le catalogue d'icônes (`Assets.xcassets/AppIcon.appiconset`) est déjà inclus.

---

## English

Floating macOS window + USB screen banner (TURZX), built to stop losing track of a dozen
ongoing threads at once — personal notes and Claude conversation tracking mixed into one list.

Personal project, shared with love — if this tool is useful to you, a coffee is always
appreciated: ☕ [buymeacoffee.com/vassi974](https://buymeacoffee.com/vassi974)

### The idea

Three JSON files as source of truth (`~/Documents/Memoire Claude/postit/`), each with a single
owner:

- `claude.json` — items tracked by Claude (status, next step, what's blocking, direct link back
  to the source conversation)
- `vassili.json` — free-form notes typed in the app
- `affichage.json` — pinning, manual order, window settings — written by the app only

Nobody writes into another source's file. The app merges all three for display.

### Quick install (.dmg)

Download the `.dmg` from this repo's [Releases](../../releases) page, open it, drag
`PostIt.app` into `Applications`, then launch it.

The app isn't notarized by Apple (no paid developer account): on first launch, macOS will
likely say it's from an unidentified developer. **Right-click the app > Open** (instead of a
normal double-click) to allow the one-time exception.

### What's implemented

- **Three sources merged** (`Store.swift`): reads every JSON file in the folder, merges into
  one list, sorted pinned-first then priority/date, watches the folder every 2s to refresh
  without a restart.
- **Visual split pinned/rest** (`ContentView.swift`): distinct tinted block for pinned items,
  "AUTRES" header for the rest — independent drag-and-drop within each block.
- **In-place editing** of personal notes (title + free text body), double-click to open the
  editor, double-click on a Claude card to open the source conversation directly via
  `claude://claude.ai/chat/<uuid>`.
- **Sleep / wake / trash**: nothing is ever truly lost — a deleted note goes to a restorable
  trash, a hidden card stays intact in its source file.
- **Text settings** (`ReglagesView.swift`): font (from installed fonts), size, expanded by
  default — persisted in `affichage.json`.
- **Full-text search** (`ArchiveRecherche.swift`): direct SQLite query (FTS5, 'porter'
  tokenizer) against a Claude conversation archive built from the official account export —
  no session token, no third-party account access.
- **TURZX USB screen banner** (`~/Scripts/postit_bandeau.py`, outside this repo): generates a
  transparent PNG of pinned items, regenerated every 20s via LaunchAgent, self-heals onto the
  right widget even after re-importing in the TurzxDeck editor.

### Not done yet

- Custom search field icon (currently an enlarged system magnifying glass).
- Native TurzxDeck widget instead of a looping regenerated PNG — works, but a real "list"
  widget would be cleaner.
- Automatic search-archive refresh: it's a manual step (re-run an Anthropic export +
  `indexer_archives.py`), not real-time.

### How to build

```
cd PostIt
xcodebuild -project PostIt.xcodeproj -target PostIt -configuration Release build
```

Requires Xcode. The icon catalog (`Assets.xcassets/AppIcon.appiconset`) is already included.
