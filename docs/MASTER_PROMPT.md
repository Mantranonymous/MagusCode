# Magus — Master Prompt pour Claude Code

> **Usage :** colle ce document entier comme premier message dans une nouvelle session Claude Code, au sein d'un dossier vide qui deviendra le repo. Demande à Claude Code de lire ce document, de poser ses questions s'il en a, puis d'attaquer la **Phase 0**. À chaque nouvelle phase, redonne-lui le contexte en référençant ce fichier + le `CLAUDE.md` qui sera créé.

---

## 1. Vision produit

**Magus** est une application macOS native qui assiste la forgemagie dans le jeu Dofus. Elle observe l'écran du jeu via OCR, comprend l'état de l'item en cours de maging, et soit (a) indique visuellement à l'utilisateur quelle rune appliquer via un overlay transparent, soit (b) automatise complètement le clic. Trois modes de travail :

- **Maging** : optimise un item vers un objectif précis (jet, exo, ou les deux)
- **Leveling** : optimise l'XP/heure du métier forgemage jusqu'au niveau 200
- **File d'attente** : enchaîne plusieurs items avec presets différents en batch

L'application est destinée à un **usage personnel** (mono-utilisateur, mono-personnage, repo privé). Pas de cloud, pas de telemetry, pas de partage communautaire au MVP. Priorité absolue : que ça marche très bien pour un seul user (le propriétaire).

---

## 2. Stack technique imposée

| Couche | Choix | Justification |
|---|---|---|
| **Langage** | Swift 5.9+ | Single language, intégration OS native, Claude Code l'écrit très bien |
| **UI** | SwiftUI (macOS 14+) | Match le design system, productif, natif |
| **Architecture UI** | MVVM | Standard, lisible, suffisant à cette taille |
| **OCR principal** | Apple Vision (`VNRecognizeTextRequest`) | Ultra rapide sur Apple Silicon, gratuit, natif |
| **OCR fallback** | Qwen2.5-VL 7B via **MLX Swift** | Fallback sur régions difficiles (petits chiffres flous) |
| **Capture écran** | ScreenCaptureKit | Moderne, performant, permissions propres |
| **Fenêtres / Accessibility** | AXUIElement (Accessibility API) | Pour tracker la fenêtre Dofus |
| **Input simulation** | CGEvent (CoreGraphics) | Mode auto, ciblage par fenêtre |
| **Overlay** | NSWindow `borderless` + `floating` + `ignoresMouseEvents` | Standard Mac |
| **Persistance** | SQLite via **GRDB.swift** | Local, performant, type-safe |
| **Build** | Xcode 15+, Swift Package Manager | Dépendances en SPM uniquement |
| **Cible OS** | macOS 14.0 (Sonoma) minimum | Permet d'utiliser les APIs modernes sans concession |
| **Cible matériel** | Apple Silicon uniquement (M1+) | Pas de support Intel, simplifie tout |

**Décisions par défaut (modifiables) :**
- Pas de framework UI tiers (pas de TCA, pas de SwiftLint au MVP)
- Tests : XCTest, structure prête mais pas de coverage obligatoire au MVP
- Langues : français primary, structure i18n en place pour ajout futur EN
- Pas d'auto-update au MVP (Sparkle ajouté en V1.1)

---

## 3. Architecture cible

```
┌─────────────────────────────────────────────────────────┐
│                        UI Layer                          │
│   SwiftUI Views · ViewModels · Design System            │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│                   Application Layer                      │
│   AppState · ModeCoordinators · SessionManager          │
└─────────────────────────┬───────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
┌───────▼──────┐   ┌──────▼──────┐   ┌──────▼──────┐
│  Perception  │   │   Decision   │   │  Execution  │
│   (Capture   │   │  (Strategies │   │  (Overlay + │
│   + OCR +    │   │   + Rules    │   │  AutoClick) │
│   Parsing)   │   │   + State    │   │             │
│              │   │   machines)  │   │             │
└──────────────┘   └─────────────┘   └─────────────┘
                          │
                          ▼
                  ┌──────────────┐
                  │  Persistence │
                  │ (GRDB SQLite)│
                  └──────────────┘
```

**Modules Swift (organisation en `Sources/`)** :

- `MagusApp/` — point d'entrée, AppDelegate, configuration globale
- `MagusUI/` — toutes les vues SwiftUI, design system, composants réutilisables
- `MagusCore/` — domain models (Item, Stat, Rune, Preset, Session…)
- `MagusPerception/` — capture écran, OCR (Vision + MLX), parsing
- `MagusDecision/` — moteurs de décision (strategies, state machines, rule engine)
- `MagusExecution/` — overlay rendering, CGEvent simulation
- `MagusPersistence/` — GRDB models, migrations, repositories
- `MagusCommon/` — utilities, extensions, logging

**Principe** : `MagusUI` ne dépend que de `MagusCore` (pas de logique métier dans la vue). `MagusDecision` ne dépend pas de `MagusPerception` (les deux consomment et produisent des types de `MagusCore`). Découpage testable.

---

## 4. Plan de développement par phases

Travailler **strictement dans l'ordre**. Chaque phase a des critères d'acceptance — ne pas passer à la suivante sans validation explicite de l'utilisateur. À la fin de chaque phase, livrer : code + tests + démo (screenshot ou GIF de ce qui marche) + ce qui a été appris.

---

### Phase 0 — Foundations

**Objectif :** repo propre, projet Xcode qui build, structure modulaire, contexte permanent en place.

**Tâches :**
1. `git init` + `.gitignore` adapté (Xcode, Swift, SPM, DerivedData, secrets)
2. Création projet Xcode : app macOS "Magus", SwiftUI, target macOS 14, App Sandbox **désactivé** au MVP (overlay et accessibility en ont besoin)
3. Configurer Swift Package Manager : créer les targets internes (`MagusCore`, `MagusUI`, `MagusPerception`, `MagusDecision`, `MagusExecution`, `MagusPersistence`, `MagusCommon`)
4. Ajouter les dépendances externes initiales :
   - `GRDB.swift` (persistance)
   - `mlx-swift` + `mlx-swift-examples` (préparé pour VLM, pas utilisé en P0)
5. Créer `CLAUDE.md` à la racine (cf. annexe à la fin de ce doc)
6. Créer le `README.md` minimal (privé, juste pour soi)
7. Première fenêtre SwiftUI : layout 3 colonnes vide (sidebar 220 / workspace flex / inspector 320), background dark `#0A0B0E`, fenêtre non-redimensionnable en-dessous de 1100×700
8. Setup `Logger` (`os.Logger`) avec catégories par module
9. Configuration des entitlements/Info.plist :
   - `NSScreenCaptureUsageDescription`
   - `NSAppleEventsUsageDescription`
   - Accessibility (sera demandée à l'usage)

**Critères d'acceptance :**
- ✅ `xcodebuild` réussit sans warning
- ✅ Lancement de l'app affiche la fenêtre 3-colonnes vide stylée
- ✅ Tous les modules SPM compilent indépendamment
- ✅ `CLAUDE.md` complet, le projet est self-documenting

---

### Phase 1 — Capture & OCR Pipeline

**Objectif :** capturer la fenêtre Dofus en continu, OCR-iser des régions définies, retourner du texte avec scores de confiance.

**Tâches :**
1. **Window discovery** (`MagusPerception/WindowFinder.swift`)
   - Utiliser `AXUIElement` + `CGWindowListCopyWindowInfo` pour trouver la fenêtre Dofus par bundle ID (`com.ankama.dofus`) ou par titre fallback
   - Exposer un `Publisher<WindowInfo>` qui émet la position/taille en temps réel
2. **Permission flow** (`MagusPerception/PermissionManager.swift`)
   - Vérifier au lancement : Screen Recording, Accessibility
   - UI explicative si manquant, deep-link vers System Settings (`x-apple.systempreferences:`)
3. **Capture engine** (`MagusPerception/ScreenCapture.swift`)
   - ScreenCaptureKit : capturer uniquement la fenêtre Dofus (pas tout l'écran)
   - Stream à fréquence variable (30fps actif, 5fps idle)
   - Output : `CVPixelBuffer` ou `CGImage`
4. **Region system** (`MagusCore/Region.swift` + `MagusPerception/RegionCropper.swift`)
   - Modèle `Region` : nom, bounds relatives (0-1) à la fenêtre Dofus
   - Stockage des régions dans SQLite par "résolution profile"
5. **Calibration UI** (basique pour cette phase)
   - Vue de calibration qui affiche la capture de la fenêtre Dofus
   - L'utilisateur trace des rectangles pour définir : Stats, Historique, Sink, Inventaire runes, Niveau métier, Barre XP
   - Sauvegarde du profil de calibration
6. **Apple Vision OCR** (`MagusPerception/VisionOCR.swift`)
   - Wrapper async/await autour de `VNRecognizeTextRequest`
   - Configurable : `recognitionLevel` (.accurate vs .fast), langues, custom words
   - Retourne `OCRResult` (texte, bbox, confidence) par observation
7. **MLX VLM stub** (`MagusPerception/VLMFallback.swift`)
   - Squelette pour Qwen2.5-VL via MLX Swift, **pas activé** en P1
   - Interface `OCREngine` que Vision et VLM implémentent toutes deux
8. **Speculative parallel OCR** (`MagusPerception/OCRPipeline.swift`)
   - Reproduire le pattern de l'article Inkybot : lancer OCR de N régions en parallèle (`TaskGroup`)
   - Retourner un `GameStateSnapshot` agrégé

**Critères d'acceptance :**
- ✅ Permissions demandées et gérées proprement (l'app guide l'utilisateur)
- ✅ Fenêtre Dofus capturable en temps réel, latence < 50ms par frame
- ✅ Calibration UI fonctionnelle : on peut définir 6 régions et les voir overlay-ées sur la capture
- ✅ OCR de 6 régions en parallèle prend < 200ms total sur M4
- ✅ Test manuel : Dofus ouvert avec un item posé sur l'établi → l'app affiche les stats lues correctement

---

### Phase 2 — Domain Model & Parsing

**Objectif :** transformer le texte brut OCR en un modèle de domaine propre, robuste aux erreurs OCR mineures.

**Tâches :**
1. **Domain models** (`MagusCore/Models/`)
   - `Item` : nom, niveau, type (anneau/cape/etc.), stats[], exos[], niveau ajout
   - `Stat` : nom (enum `StatKind`), valeur, min, max
   - `StatKind` : enum exhaustif (Vitalité, Force, Intelligence, …, Tacle, Fuite, Retrait PA, etc.)
   - `Rune` : type (`SM`/`PA`/`RA` + stat ciblée), stockage runes par type
   - `Pute` : type d'exo (PA, PM, RA, Crit, Inv, Dommages, Portée)
   - `MageHistoryEntry` : type combine, résultat (succès/échec), gain/perte, timestamp
   - `Sink` : pourcentage actuel + historique
2. **Parsers** (`MagusPerception/Parsers/`)
   - `StatLineParser` : regex + tolérance OCR (e.g. "Vitalité 180 (150-200)" → `Stat(.vitalité, 180, 150, 200)`)
   - `HistoryParser` : extrait les lignes d'historique combine
   - `SinkParser` : extrait "%" + valeur
   - `RuneInventoryParser` : associe quantité ↔ type de rune
   - `JobLevelParser` : niveau métier + % XP
   - Tous **idempotents et purs**, testables sans I/O
3. **Stat dictionary** (`MagusCore/StatDictionary.swift`)
   - Mapping `String → StatKind` avec aliases (forme courte, fautes OCR fréquentes)
   - Mapping inverse pour l'affichage
4. **State diff** (`MagusCore/StateDiff.swift`)
   - Compare deux `GameStateSnapshot` consécutifs
   - Détecte : combine landed (history changed), stat changed, item swapped, jobs leveled
5. **OCR robustness** (`MagusPerception/OCRCorrection.swift`)
   - Mapping caractères ambigus (`l↔1`, `O↔0`, `S↔5`, `B↔8`)
   - Si un nombre n'est pas dans la range attendue (min ≤ x ≤ max), retry avec corrections
6. **Tests massifs**
   - Fixtures : ~50 captures d'écran réelles dans `Tests/Fixtures/`
   - Tests des parsers sur ces fixtures, coverage ≥ 90% sur cette couche

**Critères d'acceptance :**
- ✅ Sur 50 captures de référence, le parsing produit le bon `GameStateSnapshot` à 100%
- ✅ Suite de tests unitaires verte
- ✅ Détection de combine landed via diff fonctionne sur séquence de captures
- ✅ Robust aux erreurs OCR triviales (1↔l, 0↔O)

---

### Phase 3 — Decision Engine

**Objectif :** étant donné un `GameStateSnapshot` + un preset, retourner la prochaine action à faire.

**Tâches :**
1. **Preset models** (`MagusCore/Presets/`)
   - `StatsPreset` : par stat, target/min/priority/enabled
   - `ConfigPreset` : par stat, useSM/usePA/useRA + thresholds + max-can-hit
   - `LevelingScenario` : table niveau → item recommandé + stratégie de rune
   - Sérialisable JSON pour future feature d'import/export
2. **Strategy protocol** (`MagusDecision/Strategy.swift`)
   ```swift
   protocol DecisionStrategy {
       func decide(state: GameStateSnapshot, presets: PresetBundle) -> Decision
   }
   enum Decision {
       case applyRune(Rune)
       case applyExo(Pute)
       case applyAntiRune(Rune) // pour casser
       case finished
       case waitingForUser(reason: String)
       case blocked(reason: BlockReason)
   }
   ```
3. **MagingStrategy** (`MagusDecision/MagingStrategy.swift`)
   - Implémente `TargetResolve` (cf. article Inkybot) :
     - Candidats = stats en-dessous de leur cible
     - Tri par distance au max (descendant)
     - Résolution rune via config (RA → PA → SM avec thresholds)
   - Respecte la contrainte d'oversink
4. **ExoStrategy** (`MagusDecision/ExoStrategy.swift`)
   - Machine à états : `BROKEN → EXO → REMAGE → DONE`
   - Transitions basées sur sink %, présence de l'exo cible, jet courant
   - Configurable : seuil sink pour tenter, exo cible, stratégie post-exo
5. **LevelingStrategy** (`MagusDecision/LevelingStrategy.swift`)
   - Optimiseur XP/heure : score chaque rune candidate par (XP attendue × probabilité succès) / coût
   - Détecte transitions d'item via le scénario actif (niveau métier atteint → recommande nouvel item)
   - Émet `waitingForUser(reason: "Pose l'item X")` quand transition nécessaire
6. **Composite engine** (`MagusDecision/DecisionEngine.swift`)
   - Dispatcher : sélectionne la bonne strategy selon le mode actif (Maging/Exo/Leveling)
   - Gère les transitions de mode (e.g. Maging avec exo = ExoStrategy puis MagingStrategy)
7. **Rule explainability** (important pour la confiance utilisateur)
   - Chaque `Decision` est accompagné d'une `Explanation` (string) : "Vita est la stat la plus loin de son max (180/200), runes PA dispo, sink à 87% donc forge favorable"
   - Affiché dans l'UI sous l'action recommandée
8. **Tests**
   - Scénarios de tests : item neuf, item presque fini, exo réussi, exo raté, leveling transition, runes épuisées…

**Critères d'acceptance :**
- ✅ Sur 20 scénarios de test (snapshots fictifs + presets), les décisions correspondent aux attentes documentées
- ✅ Chaque décision a une explication lisible
- ✅ Détection "item fini" fiable
- ✅ Le moteur ne suggère **jamais** une action illégale (oversink, rune absente du stock)

---

### Phase 4 — UI Foundation & Design System

**Objectif :** poser le design system en SwiftUI + construire la coquille de l'app navigable.

**Tâches :**
1. **Design tokens** (`MagusUI/Theme/`)
   - `Colors` : reprendre exactement la palette du mockup (`#0A0B0E`, `#7C8EFF`, `#4ADE80`, `#D4A574`, etc.)
   - `Typography` : embarquer Instrument Sans + JetBrains Mono + Instrument Serif comme resources, définir styles (`.titleL`, `.titleM`, `.body`, `.mono`, `.label`, etc.)
   - `Spacing` : échelle 4/8/12/16/20/24/32
   - `Radius` : 4/6/8/12/14
   - `Shadows` : `.sm`, `.md`, `.lg`
2. **Components atomiques** (`MagusUI/Components/`)
   - `Card`, `Button` (primary/secondary/danger), `Badge`, `Tag`, `StatusDot`, `IconButton`
   - `MetricStat` (label + value + delta)
   - `ProgressBar`, `ProgressRing`
   - `Toggle` (style mode Simple/Avancé)
   - `KbdHint` (badge `⌘K`)
3. **Layout shell** (`MagusUI/Shell/`)
   - `AppShell` : layout 3 colonnes
   - `Sidebar` : navigation par sections (Activité, Bibliothèque, Réglages)
   - `Topbar` : breadcrumb + actions
   - `Inspector` : panneau droit contextuel
   - `ActionBar` : barre du bas avec actions principales
4. **Navigation state** (`MagusUI/Navigation/`)
   - `AppCoordinator` : route active, mode actif
   - SwiftUI `@Observable` pour state global léger
5. **Mode toggle Simple/Avancé**
   - Implémenter le toggle visible dans la sidebar
   - En mode Simple : masque les options avancées (seuils fins, scripts custom, calibration manuelle)
   - En mode Avancé : tout est visible
   - Préférence persistée
6. **Mock data layer**
   - `PreviewData` : fixtures pour SwiftUI Previews
   - Toutes les vues ont au moins une Preview fonctionnelle

**Critères d'acceptance :**
- ✅ Le rendu de l'app à vide reproduit visuellement le mockup HTML fourni
- ✅ Navigation entre sections de la sidebar fonctionne
- ✅ Toggle Simple/Avancé masque/montre les bonnes choses
- ✅ Tous les composants ont une SwiftUI Preview
- ✅ Aucun warning de hardcoded color/font hors du Theme

---

### Phase 5 — Modes Implementation (UI)

**Objectif :** câbler les vues métier pour les 3 modes, connectées au moteur de décision (mais sans exécution réelle encore).

**Tâches :**
1. **Dashboard Maging** (`MagusUI/Modes/Maging/`)
   - Reproduire le mockup : hero "Action recommandée", tableau des stats, ring de progression, action bar
   - Brancher sur `DecisionEngine` avec un `GameStateSnapshot` mocké
2. **Editor de preset** (Stats + Config)
   - Vue dédiée pour éditer un `StatsPreset` et un `ConfigPreset`
   - Bibliothèque de presets (liste, dupliquer, supprimer, renommer)
   - Import/export JSON
3. **Onglet Leveling**
   - Vue scénario actif (niveau actuel, ETA niveau 200, XP/heure)
   - Liste des scénarios pré-configurés (4-5 bundlés : "Éco F2P", "Rapide kamas-illimité", "Anti-runes")
   - Editor de scénario custom (table niveau → item → rune strategy)
4. **File d'attente**
   - Liste d'items avec preset Stats + preset Config par item
   - Drag-to-reorder
   - "Démarrer la file" : enchaîne items en mode auto
   - "Mode sans échec" : skip item si IA pas sûre
5. **Inspector contextuel**
   - S'adapte au mode actif : montre l'item courant, historique récent, session stats
6. **Bibliothèque de presets bundlés**
   - 15-20 presets d'items populaires pré-fournis (à valider avec moi via la meta jeu actuelle)
   - 3-5 presets de Config par défaut ("Rapide", "Économe", "Risque min")

**Critères d'acceptance :**
- ✅ Les 3 modes ont leur vue principale fonctionnelle
- ✅ Création/édition/suppression de presets persiste en SQLite
- ✅ Switch entre les modes préserve le contexte de session
- ✅ Mode Simple cache bien la complexité, Mode Avancé expose tout

---

### Phase 6 — Overlay In-Game

**Objectif :** afficher un overlay transparent au-dessus de la fenêtre Dofus qui encadre la rune recommandée.

**Tâches :**
1. **Overlay window** (`MagusExecution/OverlayWindow.swift`)
   - `NSWindow` : `borderless`, `level = .floating`, `isOpaque = false`, `backgroundColor = .clear`, `ignoresMouseEvents = true`, `collectionBehavior` adapté
2. **Window tracking**
   - Reprendre `WindowFinder` de P1 pour suivre la position/taille de Dofus
   - Repositionner l'overlay en temps réel
3. **Renderer** (`MagusExecution/OverlayRenderer.swift`)
   - SwiftUI dans l'overlay : rectangle vert animé autour de la rune cible
   - Indication textuelle discrète "Applique : Pute Vitalité PA"
   - Compteur de session miniature dans un coin
4. **Activation logic**
   - Overlay actif uniquement si :
     - Mode "Overlay" sélectionné (vs "Automatique")
     - Fenêtre Dofus est focused ou au-dessus
     - Bot en session active
5. **Targeting**
   - `DecisionEngine` produit une `Decision` qui mappe vers une position d'inventaire de runes
   - Calculer la bbox de la cellule de rune via la calibration de P1

**Critères d'acceptance :**
- ✅ Lance la session en mode Overlay → un rectangle vert apparaît au-dessus de la bonne rune dans Dofus
- ✅ Rectangle suit le mouvement de la fenêtre Dofus en temps réel
- ✅ Clic dans Dofus : passe au travers de l'overlay (ignoresMouseEvents)
- ✅ Au combine suivant, l'overlay s'update correctement

---

### Phase 7 — Auto-clic (mode automatique)

**Objectif :** en mode Auto, le bot exécute lui-même les clics.

**Tâches :**
1. **Click engine** (`MagusExecution/ClickEngine.swift`)
   - `CGEvent` pour souris : mouseMove + mouseDown + mouseUp
   - Ciblage par fenêtre : utiliser `CGEventPostToPid` plutôt que global pour pouvoir cliquer même si Dofus n'est pas top-most
2. **Human-like motion**
   - Trajectoires Bézier entre deux points (3-4 points de contrôle randomisés)
   - Vitesse non-uniforme (easing)
   - Jitter aux endpoints (±2px gaussien)
3. **Click timing**
   - Distribution log-normale pour intervalles entre clics, médiane configurable (par défaut 600ms)
   - Micro-pauses occasionnelles (1-3% des clics → pause 2-5s)
   - Longue pause stochastique (0.1% → 30s-2min) — utile pour imiter "regarder son téléphone"
4. **Safety guards**
   - Hotkey **panic stop** global : `⌥⌘.` arrête tout immédiatement
   - Limite de temps de session configurable (défaut 90min puis pause obligatoire)
   - Détection de désynchro : si N combines consécutifs ne produisent pas le changement attendu, stop + alerte
5. **Mode toggle**
   - Selector "Overlay / Automatique" en haut de chaque mode
   - Disclaimer à la première activation Auto : "Le mode automatique présente un risque de bannissement plus élevé."

**Critères d'acceptance :**
- ✅ En mode Auto, Dofus en arrière-plan, le bot mage correctement
- ✅ Hotkey panic-stop coupe immédiatement
- ✅ Mouvements souris visuellement crédibles (trajectoires courbées, pas téléportation)
- ✅ Limite de session respectée

---

### Phase 8 — VLM fallback & Polish

**Objectif :** activer la couche VLM, peaufiner UX, gérer les cas limites.

**Tâches :**
1. **VLM activation** (`MagusPerception/VLMFallback.swift`)
   - Charger Qwen2.5-VL 7B via MLX au lancement (lazy : seulement si activé en réglages)
   - Routing : si Apple Vision retourne confidence < seuil sur une région critique, retry avec VLM
   - Logger les cas de fallback pour itération
2. **Settings / Préférences**
   - Vue Réglages : permissions, calibration, langue, mode VLM (off/auto/always)
   - Reset preset bundle, clear cache OCR
3. **Onboarding première session**
   - Wizard : permissions → calibration assistée → test OCR → session démo
4. **Logging & diagnostics**
   - Log structuré (`os.Logger` + fichier rotatif)
   - Vue "Diagnostics" cachée derrière `⌥⌘D` pour debug
5. **App icon & branding**
   - Icône macOS multi-résolutions (1024 down to 16)
   - Naming dans Info.plist : "Magus"
6. **Manual test checklist**
   - Document `TESTING.md` : checklist manuelle exhaustive à passer avant chaque release

**Critères d'acceptance :**
- ✅ VLM fallback fonctionne sur cas durs identifiés en P2
- ✅ Première utilisation guidée de bout en bout sans friction
- ✅ Logs exploitables pour debug post-session
- ✅ App build en Release, signée localement, lance proprement

---

## 5. Conventions

### Code
- **Swift API design guidelines** strictes
- Naming : `camelCase` pour vars/funcs, `PascalCase` pour types, `SCREAMING_SNAKE_CASE` proscrit
- Pas de force-unwrap (`!`) sauf cas IBOutlet legacy (n'existe pas en SwiftUI)
- `guard` early-return systématique
- `async/await` partout, pas de `completionHandler`-style nouveau code
- `actor` pour les couches stateful concurrentes (OCRPipeline, ClickEngine)
- Pas de singletons except `Logger`. Injection de dépendances par init.

### Structure
- 1 type par fichier (sauf petites enums/structs liées)
- Tests : `XCTest`, fichiers `*Tests.swift` miroirs des fichiers source
- Fixtures dans `Tests/Fixtures/` (captures PNG + JSON attendus)
- Resources (fonts, images) par module dans `Resources/`

### Git
- Commits en français, format conventional : `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`
- Branches : `main` stable, `feature/<phase>-<courte-description>` pour le travail en cours
- Pas de force-push sur `main`

### UI
- Toutes les chaînes UI passent par `String(localized:)` même en V1 FR-only
- Pas de hardcoded color/font/spacing hors du `Theme`
- SwiftUI Previews obligatoires pour toute nouvelle vue
- Accessibility : `accessibilityLabel` sur tout élément interactif

---

## 6. Hors scope MVP (à NE PAS faire)

Explicitement exclu pour éviter le scope creep :

- ❌ Multi-comptes ou multi-personnages parallèles
- ❌ Sync cloud des presets
- ❌ Hall of Fame, leaderboard, social
- ❌ Telemetry/analytics
- ❌ Support Dofus Retro, Dofus Touch, Dofus Unity beta
- ❌ Support multi-résolutions automatique (calibration unique par utilisateur OK)
- ❌ Mac App Store distribution
- ❌ Notarization Apple
- ❌ Sparkle auto-updates
- ❌ Mode bilingue EN
- ❌ Plugins / SDK script personnalisé externe
- ❌ Réseau / API / serveur tiers

Ces items pourront être ajoutés en V2+ après validation MVP.

---

## 7. Comment travailler avec ce prompt

**Pour Claude Code, à chaque session :**

1. Lire `CLAUDE.md` à la racine du repo en premier
2. Identifier la phase en cours (en demandant à l'utilisateur si pas clair)
3. Lire les fichiers concernés par la phase
4. **Avant d'écrire du code** : exposer le plan d'attaque de la phase en bullets et demander validation
5. Implémenter par petites unités cohérentes, en commitant souvent
6. À la fin d'une unité : montrer le diff, expliquer ce qui a été fait, lancer les tests
7. En cas de blocage technique : poser une question précise plutôt que partir dans une mauvaise direction
8. En fin de phase : présenter une démo, valider les critères d'acceptance, mettre à jour `CLAUDE.md`

**Pour l'utilisateur :**

- Donne à Claude Code l'accès à un dossier vide pour démarrer
- Phase 0 d'abord, valide-la, puis dis "On passe en Phase 1"
- N'hésite pas à demander à Claude Code d'expliquer ses choix
- Si une décision te semble douteuse, challenge-la — Claude Code ajuste bien
- Garde des sessions courtes (1-2 heures de coding effectif) pour éviter la dérive de contexte

---

## 8. Première instruction à Claude Code

> Lis ce master prompt en entier. Pose-moi toutes les questions que tu juges nécessaires avant de commencer la Phase 0. Une fois mes réponses obtenues, exécute la Phase 0 en intégralité, en t'arrêtant à chaque étape majeure pour me montrer ce que tu as fait. À la fin de la Phase 0, présente-moi les critères d'acceptance un par un avec démonstration, et attends ma validation explicite avant toute Phase suivante.

---

## Annexe — Contenu de `CLAUDE.md` à créer en P0

Voir fichier séparé `CLAUDE.md` fourni avec ce master prompt.
