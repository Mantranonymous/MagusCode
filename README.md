# Magus

Assistant de forgemagie pour Dofus — application macOS native (SwiftUI).

## Prérequis

- macOS 14.0 (Sonoma) minimum
- Apple Silicon (M1+)
- Xcode 16+

## Build

```bash
open Magus.xcodeproj
# ⌘R pour lancer
```

Ou via CLI :
```bash
xcodebuild -scheme Magus -configuration Debug build
```

## Structure

| Module | Rôle |
|---|---|
| `MagusApp` | Point d'entrée, configuration |
| `MagusCore` | Modèles domaine (Item, Stat, Rune, Preset) |
| `MagusUI` | Vues SwiftUI, design system |
| `MagusPerception` | Capture écran, OCR, parsing |
| `MagusDecision` | Stratégies, state machines, moteur de règles |
| `MagusExecution` | Overlay, simulation de clics |
| `MagusPersistence` | GRDB (SQLite), repositories |
| `MagusCommon` | Utilitaires, logging |

## Usage personnel

Repo privé, mono-utilisateur. Pas de distribution publique.
