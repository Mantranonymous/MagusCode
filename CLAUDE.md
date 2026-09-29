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
- [x] **Phase 2** — Domain Model & Parsing ✅ (2026-05-19)
- [x] **Phase 3** — Decision Engine ✅ (2026-05-19) — MagingStrategy v2 + ExoStrategy + LevelingStrategy
- [x] **Phase 4** — UI partiel ✅ (Theme tokens + PresetEditor + composants), fonts custom et raffinements restants
- [x] **Phase 5** — Sidebar nav 3 routes + File d'attente d'items ✅ (2026-05-19)
- [x] **Phase 6** — Overlay In-Game ✅ (2026-05-19)
- [x] **Phase 7** — Auto-clic + Human motion + Hotkey panic ✅ (2026-05-19)
- [x] **Phase 8** — Onboarding + Diagnostics + FileLogger + AppIcon ✅ partiel (2026-05-19), VLM fallback restant
- [x] **Phase 9** — Encodage savoir métier FM Dofus 3 ✅ (2026-05-20) — RuneWeights canoniques (52 effets), ReliquatTracker, SuccessProbabilityModel (porté d'EasyFM), MagingStrategy V3 puits-aware avec cap over 101, RiskSimulator (prédit chutes EC/SN), ExoStrategy V2 avec lissage obligatoire, détection runes épuisées via historique FM
- [x] **Phase 10** — Surfaces UX des features P9 ✅ (2026-05-20) — Probas SC/SN/EC + prédictions chute dans la card action, section runes épuisées + bouton reset, compteurs session live (SC/SN/EC/temps restant)
- [x] **Phase 11 complet** — Features inspirées ExoFast ✅ (2026-05-20) — tie-breaking par nb de runes (P11.1), alternance auto Exo PA/PM (P11.2), pauses anti-detect 5-15s / 20-40s (P11.3), bouton "Remplir depuis l'item" (P11.4), alertes sonores 4 niveaux (P11.5), workflow multi-étapes MVP "Cibles" avec auto-advance (P11.6), seuils Pa/Ra par stat avec opérateurs from/until/between (P11.7), export/import JSON .magus (P11.8), import .efitem ExoFast (P11.9 best-effort)
- [x] **Phase 12** — Click rune en inventaire pour exos ✅ (2026-05-20) — 3 nouvelles RegionKind calibrables (runeSlotGaPa/GaPme/Po). Pour exo PA/PM/Portée : Magus double-clic la rune calibrée en inventaire au lieu de chercher dans la table FM (la stat n'y est pas affichée si non native).
- [x] **Phase 13** — Fixes UX & bugs ✅ (2026-05-20) — fix bug click row qui matchait mauvaise stat (Dommage Feu → Portée) en utilisant StatDictionary pour résoudre le kind exact (P13.1), toast banner + indicateur "PRESET ACTIF" sur la card item (P13.2), édition inline des targets + checkbox enable/disable directement dans la card Item à mager (P13.3), stats overables comme mageables + scroll inline (P13.4), parser .efitem reverse complet v2 avec chains + eid 2-byte (P13.5).
- [x] **Phase 14** — Règles métier inspirées Padgref.efitem ✅ (2026-05-20) — skip auto des stats négatives (Tacle/Esquive en malus) (P14.1), priorités boostées PA/PM=120, PO/Invo=110 pour garantir leur remontée prioritaire si chute (P14.2), `smartConfig` génère seuils Pa/Ra par stat (Pa from ≥10, Ra entre max-raBonus et max-1) appliqué automatiquement à la sélection d'item (P14.3).
- [x] **Phase 15** — Amélioration OCR ✅ (2026-05-20) — upscaling Lanczos 2x configurable (P15.1), customWords depuis StatDictionary FR pour booster la reconnaissance (P15.2), section OCR dans Préférences avec slider scale + toggle binarisation (P15.3).
- [x] **Phase 16** — VLM réel Qwen2.5-VL 3B ✅ (2026-05-20) — dépendance MLX Swift + mlx-swift-examples (Metal Toolchain requis, ~1.5GB) (P16.1), VLMFallback singleton avec Qwen2.5-VL 3B 4-bit (~2GB téléchargé au 1er usage via HuggingFace), prompt FR pour OCR table FM, bbox synthétiques line-based (P16.2). Activable via toggle existant en Préférences (P16.3).
- [x] **Phase 17** — Mode Turbo + UX exo ✅ (2026-05-20) — Toggle Mode Turbo : throttle 250ms (au lieu de 500), click interval 0.8s (au lieu de 1.5s), skip pauses anti-detect, click direct sans Bézier (P17.1). Message explicite ExoStrategy expliquant l'usage des Orbes régénérants (P17.2 — invalidé par P18, voir ci-dessous).
- [x] **Phase 18** — ExoStrategy V3 méthode pro "lissage + tampon sacrificielles" ✅ (2026-05-20) — Refonte complète : SUPPRIMÉ le check PWRG>100 (faux conceptuellement). La vraie méthode FM = monter TOUTES les stats au max (y compris sacrificielles : prospection, résistances fixes, esquives, tacles, retraits) puis spam Ga PA/PM. Pendant le spam, les EC absorbent les pertes sur les sacrificielles avant de toucher l'exo. MagingStrategy reprend la priorité si une stat HIGH PRIORITY chute (PA natif, CC, Do, etc.) avant de re-spam.
- [x] **Phase 19** — UX fancy édition inline ✅ (2026-05-20) — StatRowEditable refait : pill toggle, barre de progression colorée (rouge/orange/bleu/vert selon ratio value/target), badge priorité coloré, section expand avec champ Min + slider Priority + boutons "Max"/"Min" actions rapides. Édition complète inline depuis la card "Item à mager" même si preset importé.
- [x] **Phase 20** — Scénarios Exo Do Sort/Distance ✅ (2026-05-20) — 4 nouveaux scénarios : exoDoSort1, exoDoSort2, exoDoDistance1, exoDoDistance2. ExoStrategy.Variant étendu avec `.custom(cid, target, label)` générique. PresetScenario.exoTarget retourne (cid, target) pour le routing. 2 nouvelles RegionKind calibrables (runeSlotPaDoSort/PaDoDistance) pour pose en inventaire. perfectExo.exoCustom() génère un preset avec stats sacrificielles + cible exo prioritaire.
- [x] **Phase 21** — ExoPercentStrategy 3 phases ✅ (2026-05-20) — Nouvelle stratégie dédiée pour exo % suivant le doc `bot_fm_exo_do_percent_logique.md` : Phase 1 (drop puits, ≥30 pour 1% / ≥60 pour 2%), Phase 2 (max lignes pour tampon anti-EC), Phase 3 (spam SC). Règles absolues hard-codées : stop si exo atteint, 1% requis avant 2%, cap PWRG 101, instructions explicites quand reliquat insuffisant. Routing via DecisionEngine vers ExoPercentStrategy(.doSort/.doDistance, percent).
- [x] **Phase 22** — Calibration skip-friendly UX ✅ (2026-05-20) — Sidebar groupée en 2 sections : "Zones requises" et "Optionnelles (skippables)". Header avec compteurs séparés requises/optionnelles. Toolbar canvas avec indicateur "OPTIONNEL" + bouton "Passer" quand zone optionnelle. Save toujours actif si requises définies, indépendamment des optionnelles. Les optionnelles peuvent être ajoutées plus tard sans tout recalibrer.
- [x] **Phase 23** — Fixes critiques targets + UI ✅ (2026-05-20) — (P23.1) Plus d'over involontaire : MagingStrategy refuse de poser une rune qui ferait dépasser `target.target` (le cap_over système n'est utilisé que si target > maxValue volontaire). (P23.2) setScenario PRÉSERVE les targets custom du preset importé : ajoute juste les cibles exo nécessaires sans écraser. (P23.3) Sélecteur de scénario passe d'un HStack de 9 pills overflow en un Menu déroulant compact avec icônes SF Symbol par scénario.
- [x] **Phase 24** — Disambig Critique + guard click safety ✅ (2026-05-20) — DofusDB "Critique" (18) renommé "% Critique", "Critiques" (86) renommé "Dommages Critiques", "Sorts (%)" renommé "Do Sort %", "Distance (%)" renommé "Do Distance %". Guard dans tryAutoClick : refuse de cliquer hors de la fenêtre Dofus (tolérance 20px) + stopSession + log d'erreur. Logging amélioré dans importEfitem : trace chaque target appliqué/ajouté + toast détaillé.
- [x] **Phase 25** — Mode observation réseau passive ✅ partiel (2026-05-22) — Module `MagusNetwork` : TCP proxy `NWListener` forward-only + `PacketDecoder` Protobuf (best-effort tant que .pb.swift non générés) + `NetworkStateBuilder` qui hydratera `GameStateSnapshot` depuis les paquets observés. Frida helper Node.js (`Sources/MagusNetwork/Frida/frida-spawn-dofus.js`) spawn Dofus.app + hook libc `connect()` pour rediriger vers le proxy local. **Aucune injection ni forge de paquet** — le `ClickEngine` reste responsable de toutes les actions. Toggle UI "Observation réseau passive" dans Préférences. `AppSettings` étendu (`networkObservationEnabled`, `networkProxyPort`, `networkDofusPath`). `AppState.networkObserver` + merge réseau→OCR dans `lastParsedSnapshot`. **RESTE** : générer les `.pb.swift` via `brew install protobuf swift-protobuf` puis `Protos/generate.sh`, `npm install` dans `Sources/MagusNetwork/Frida/`, confirmer le framing en live (varint vs uint32BE), et hydrater vraiment `NetworkStateBuilder` avec les vrais types générés.

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
- **Phase 2 (2026-05-19)** : Nouveau module `MagusReferenceData` (DofusDB client + sync + cache). Domain models complets (Item, Stat, Rune, Pute, Sink, History, GameStateSnapshot, StatDictionary, StateDiff). Parsers OCR (Stats/Sink/JobLevel/History) + corrections caractères. 40 unit tests verts. Bouton "Capturer fixture" pour collecte facile.
- **Phase 2.5 prévue avant P3** : ajustements domain après lecture du guide FM Dofus 3 (voir mémoire `forgemagie-domain`) — corriger `Rune.Power` (base/pa/ra), ajouter `Métier` (6 métiers FM), `Reliquat`, `ItemProfile` (Concessions/Puits/Brisages), `OverInfo`, renommer Result en SC/SN/EC. Ajouter `.reliquat` à RegionKind (région texte calibrable, Dofus 3 affiche le reliquat dans l'UI).
- **Phase 2.5 (2026-05-19)** : Corrections domain post-guide FM appliquées. Rune.Power (base/pa/ra avec densités 1/3/10), Métier enum (6 métiers + mapping itemTypeId), Reliquat (Double car valeurs décimales type 2.2), ItemProfile (Concessions/Puits/Brisages), OverInfo (cap 101). MageHistoryEntry.Result renommé criticalSuccess/neutralSuccess/criticalFail. Sink supprimé (n'existe pas en Dofus 3, c'était Puits=Reliquat). Region.reliquat ajoutée + ReliquatParser. Fix calibration UX (offset drag + resize handles + move via drag intérieur).
- **Phase 2.6 (2026-05-19)** : Identification item via DofusDB. ItemSpec + StatSpec, ReferenceRepository.searchItems + itemSpec (join items × item_effects × effects × characteristics). UI sheet de sélection avec autocomplete. Carte "Item à mager" qui affiche stats mageables + stats fixes (PA, Fuite) avec valeurs OCR matchées. SpecGuidedExtractor : pour stats manquantes du spec, cherche le nom dans OCR brut et extrait valeur in-range (rejet out-of-range pour éviter de prendre des headers/runes counts). DisplayName embelli : "Dommage Terre" pour id 88-92, "Résistance X %" pour id 33-37, "Résistance X" pour id 54-58. Aliases dictionary : résistances %/fixe distingués via présence de "%" dans la ligne OCR.
- **Décision DofusDB stats** : il existe 2 entrées par stat principale (id 10 "Force" vs id 127 "Force %", etc.) — normalize() conserve "%" et parens pour distinguer.
- **Phase 3 (2026-05-19)** : Decision Engine. Models StatsPreset/ConfigPreset/Decision/PresetBundle. MagingStrategy V2 (skip over, skip max, reliquat-aware, tri par urgency). ExoStrategy (variants exoPA/exoPM). DecisionEngine dispatch via PresetScenario. 4 scénarios auto-générés depuis ItemSpec : jetParfait / exoPA / exoPM / overVita. Carte "Action recommandée" en haut du Home.
- **Phase 6 (2026-05-19)** : OverlayWindow (NSWindow level CGShieldingWindowLevel, ignoresMouseEvents, suit Dofus). OverlayContent (badge avec icône+titre+sous-titre, bordure colorée). ClickMarkerWindow (réticule rouge pulsant à la position du futur click).
- **Phase 7 (2026-05-19)** : ClickEngine (CGEvent via .cghidEventTap + NSRunningApplication.activate avant click + setIntegerValueField mouseEventClickState). ClickTargetResolver (row Y via OCR bbox + result.imageSize, col X via régions calibrables statsBaseColumn/statsPaColumn/statsRaColumn ou fractions empiriques). 3 modes : Guided / Démo (sans exec) / Auto. Safety : popup warning, lock Auto si colonnes pas calibrées, anti-régression 2× → emergency stop, no-change 5× → stop, max 600 clicks/session, max 30min.
- **Phase 5 partiel (2026-05-19)** : Sidebar nav 3 routes (Activité / Bibliothèque / Réglages). Inspector visible seulement sur Activité. Indicateur session active dans le sidebar.

---

*Dernière mise à jour : fin marathon Phase 3 → 8 — 2026-05-19*

- **Marathon final (2026-05-19)** : LevelingStrategy + scenario Leveling. File d'attente (QueueItem + UI add/remove/start/stop). PresetEditor sheet (toggle + slider priority + target par stat). FileLogger + LogBuffer en mémoire. DiagnosticsWindow (⌥⌘D, 5 tabs : Logs/Parsé/OCR brut/Decision/Système). OnboardingSheet 4 étapes (welcome/permissions/DofusDB/calibration). App icon générée par script Swift (10 résolutions PNG).
