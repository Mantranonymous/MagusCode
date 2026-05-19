# CLAUDE.md — Contexte permanent du projet Magus

> Ce fichier est lu par Claude Code au début de chaque session. Il contient le contexte minimal pour reprendre le travail efficacement. **Ne pas le supprimer.** Le mettre à jour à la fin de chaque phase.

---

## Projet

**Magus** — Assistant de forgemagie pour Dofus, application macOS native (SwiftUI).
Mono-utilisateur, mono-personnage, repo privé, usage personnel.

Le master prompt complet est dans `docs/MASTER_PROMPT.md` (à conserver dans le repo).

## Stack

- Swift 5.9+, SwiftUI, macOS 14+ (Sonoma), Apple Silicon uniquement
- Architecture MVVM, modules SPM internes
- OCR : Apple Vision principal, MLX Swift (Qwen2.5-VL) en fallback
- Capture : ScreenCaptureKit
- Input : CGEvent
- Persistance : GRDB.swift (SQLite)

## Structure des modules

```
Magus/
├── MagusApp/          ← entry point, AppDelegate
├── MagusUI/           ← vues SwiftUI, design system
├── MagusCore/         ← domain models (Item, Stat, Rune, Preset...)
├── MagusPerception/   ← capture, OCR, parsing
├── MagusDecision/     ← strategies, state machines, rule engine
├── MagusExecution/    ← overlay, click simulation
├── MagusPersistence/  ← GRDB models, repositories
└── MagusCommon/       ← utilities partagées
```

Règle de dépendance : `UI → Core` uniquement. `Perception` et `Decision` ne se connaissent pas.

## Phase en cours

> **À MAINTENIR À JOUR** par Claude Code à chaque fin de phase.

- [x] **Phase 0** — Foundations ✅ (2026-05-19)
- [x] **Phase 1** — Capture & OCR Pipeline ✅ (2026-05-19)
- [ ] **Phase 2** — Domain Model & Parsing
- [ ] **Phase 3** — Decision Engine
- [ ] **Phase 4** — UI Foundation & Design System
- [ ] **Phase 5** — Modes Implementation (UI)
- [ ] **Phase 6** — Overlay In-Game
- [ ] **Phase 7** — Auto-clic
- [ ] **Phase 8** — VLM Fallback & Polish

## Conventions importantes

- **Pas de force-unwrap** (`!`)
- **async/await** partout, jamais de `completionHandler` neuf
- **1 type par fichier** sauf petites enums liées
- **SwiftUI Previews obligatoires** pour toute nouvelle vue
- **Toutes les strings UI** via `String(localized:)`
- **Pas de couleurs/fonts hardcodées** hors `MagusUI/Theme`
- **Commits en français** : format `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`
- **Tests** : XCTest, fichiers miroirs avec suffixe `Tests.swift`

## Design system

- Couleurs canoniques dans `MagusUI/Theme/Colors.swift`
- Typographie : Instrument Sans (UI), JetBrains Mono (chiffres), Instrument Serif italique (accents)
- Palette dark par défaut : bg `#0A0B0E`, accent `#7C8EFF`, success `#4ADE80`, gold `#D4A574`

## Permissions macOS requises

- Screen Recording (capture de la fenêtre Dofus)
- Accessibility (tracking de la fenêtre et input simulation)
- App Sandbox **désactivé** (incompatible avec accessibility + overlay au MVP)

Demandes gérées dans `MagusPerception/PermissionManager.swift`.

## Hors scope strict (à NE PAS implémenter)

- Multi-comptes, sync cloud, telemetry, leaderboard
- Dofus Retro/Touch, multi-résolutions auto
- Mac App Store, notarization, Sparkle auto-update
- i18n EN au MVP (structure prête, traduction plus tard)

## Démarrage rapide

```bash
# Première fois
xcodegen generate  # si projet généré via Xcodegen, sinon ouvrir Magus.xcodeproj directement
open Magus.xcodeproj

# Build & run
xcodebuild -scheme Magus -configuration Debug build
# ou via Xcode : ⌘R
```

## Comportement attendu de Claude Code

1. **Au début de chaque session** : lire ce fichier, identifier la phase en cours
2. **Avant d'écrire du code** : annoncer le plan en bullets, attendre validation
3. **Implémenter par petites unités** : commit après chaque unité cohérente
4. **Tester ce qui peut l'être** : ne pas attendre la fin pour ajouter les tests
5. **En cas de doute** : poser une question précise avec contexte plutôt que deviner
6. **À la fin d'une phase** : montrer la démo, valider les critères, mettre à jour ce fichier

## Notes de session

> Espace pour Claude Code et l'utilisateur : décisions importantes, dettes techniques connues, idées pour plus tard.

- **Phase 0 (2026-05-19)** : Structure validée — Magus.xcodeproj écrit manuellement (pas de xcodegen), local Swift package `MagusModules/` pour les 7 modules, GRDB 7.10.0 intégré. MLX Swift différé (ajout en P8 quand nécessaire). Swift 6.2.3 + Swift 5 language mode pour concurrency targeted. App build OK en Debug avec ad-hoc signing.
- **Décision build CLI** : pour les builds en CLI, utiliser `xcodebuild -scheme Magus -configuration Debug build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` (évite la signature qui demande un Apple Developer account).
- **Phase 1 (2026-05-19)** : Capture + OCR opérationnels. PermissionManager + WindowFinder + ScreenCapture (SCK) + RegionRepository (GRDB) + Theme + CalibrationView (stylisée, drag-to-draw) + OCRPipeline (Vision, TaskGroup parallèle) + AppState wire-up. Dofus 3 (Unity) ciblé via `com.Ankama.Dofus`.
- **Décision RegionKind** : 4 régions texte (Stats, Historique, Sink, Niveau métier) + 2 régions visuelles (RuneInventory, BarreXP). Les visuelles seront traitées par analyseur pixel en P2/P3, pas OCR. `OCRPipeline` filtre déjà via `kind.dataType == .text`.
- **À faire en P2** : intégrer DofusDB (module `MagusReferenceData`, cache SQLite local + refresh hebdo) + parsers (stats/sink/jobLevel/history) + `GameStateSnapshot` + `StateDiff` + corrections OCR robustes.

---

*Dernière mise à jour : fin Phase 1 — 2026-05-19*
