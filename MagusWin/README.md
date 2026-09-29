# MagusWin

Port C# .NET 8 du bot de forgemagie Dofus 3 **Magus** (originellement Swift/macOS). Objectif : remplacer la couche OCR + auto-clic par un **bot socket** qui parle directement le protocole réseau Dofus 3.

## État honnête

**Ce dépôt est un scaffold avec la logique métier portée à 100 % depuis le projet Swift, mais le bot n'est pas encore fonctionnel.**

La couche métier (decision engine, stratégies, table des poids canoniques, modèle de probabilités) est prête et testée. La couche réseau est uniquement un stub — il faut faire le reverse engineering du protocole Dofus 3 Unity pour avoir un bot qui parle vraiment au serveur. Voir [`docs/REVERSE_ENGINEERING.md`](docs/REVERSE_ENGINEERING.md).

Sans RE → tu peux uniquement exécuter la CLI en mode stub (boucle de décision avec un faux client réseau qui simule des SC/SN/EC aléatoires).

## Stack

- **Runtime** : .NET 8 (LTS)
- **Langage** : C# 12, `nullable enable`, `ImplicitUsings`
- **Plateforme cible** : Windows (le bot socket ciblera `Dofus.exe` Windows)
- **Tests** : xUnit + FluentAssertions
- **Logging** : `Microsoft.Extensions.Logging.ILogger<T>`
- **Pas de dépendance UI au MVP** (CLI uniquement)

## Build

```pwsh
# Restauration + build
dotnet restore
dotnet build

# Tests
dotnet test

# Run CLI (mode stub)
dotnet run --project src/MagusBot.Cli
```

Cible une machine Windows pour le run final (le stub fonctionne aussi sur Mac/Linux).

## Architecture

3 couches :

```
+---------------------------------+
|  MagusBot.Cli                   |  point d'entrée, DI, boucle de décision
+----+--------------+-------------+
     |              |
     v              v
+----+----+   +-----+--------+
|  Core   |   |   Network    |   stratégies + modèles | client jeu (stub ou réel)
+----+----+   +-----+--------+
     |              |
     v              v
+---------------------------------+
|  Persistence (imports .efitem)  |
+---------------------------------+
```

Voir [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) pour le détail.

## Avancement par module

| Module | État | Notes |
|---|---|---|
| `MagusBot.Core/Models` | Complet | StatKind / Rune / Stat / Item / ItemSpec / preset / decision portés à 100 % depuis le Swift. |
| `MagusBot.Core/RuneWeights` | Complet | Table canonique 52 effets, identique au Swift, testée. |
| `MagusBot.Core/ReliquatTracker` | Complet | Formule darckoune + SafetyLevel. |
| `MagusBot.Core/SuccessProbabilityModel` | Complet | Modèle EasyFM porté. |
| `MagusBot.Core/Strategies/MagingStrategy` (V3) | Complet | Puits-aware, itération tous candidats (P29), anti-over (P23.1), skip stats négatives (P14.1). |
| `MagusBot.Core/Strategies/ExoStrategy` (V3) | Complet | Méthode lissage + tampon sacrificielles. |
| `MagusBot.Core/Strategies/ExoPercentStrategy` | Complet | 3 phases (drop / lisser / spam) avec règles absolues. |
| `MagusBot.Core/Strategies/LevelingStrategy` | Complet | Maximise densité de rune posée. |
| `MagusBot.Core/Strategies/DecisionEngine` | Complet | Dispatch par scenario. |
| `MagusBot.Persistence/EfitemImporter` | Complet | Parser binaire ExoFast v2 (chains + 2-byte eid). |
| `MagusBot.Network/IGameClient` | Complet | Interface haut-niveau stable. |
| `MagusBot.Network/Stub/StubGameClient` | Complet | Simule l'item + résultats SC/SN/EC. |
| `MagusBot.Network/Messages/*` | Stub | Squelettes en attente d'IDs réels. |
| `MagusBot.Network/Codec/PacketCodec` | TODO RE | Encoding/decoding binaire à faire. |
| `MagusBot.Network/Codec/PacketRegistry` | Squelette | Prêt à recevoir les IDs. |
| `MagusBot.Cli` | Complet (stub mode) | Boucle de décision opérationnelle. |
| `MagusBot.Core.Tests/RuneWeightsTests` | Complet | 18 tests sur la table canonique. |

## Roadmap

### Avant le RE — déjà fait
- [x] Port modèles domaine
- [x] Port RuneWeights canonique (avec tests de garde)
- [x] Port stratégies (Maging V3, Exo V3, ExoPercent, Leveling)
- [x] Port EfitemImporter
- [x] StubGameClient + CLI test loop

### Pendant le RE (à faire par toi)
- [ ] Setup outillage (Il2CppDumper, mitmproxy, Wireshark, dnSpy/Ghidra)
- [ ] Dump `GameAssembly.dll` + `global-metadata.dat` → headers C#
- [ ] Capture MITM passive de 1-2h sur un compte secondaire
- [ ] Identifier les 3 packets MVP (`ItemSelected`, `FmAction`, `FmResult`)
- [ ] Implémenter `PacketCodec` (sérialisation binaire + crypto si présente)
- [ ] Remplir `PacketRegistry` avec les IDs trouvés
- [ ] Créer `DofusGameClient` (vraie impl de `IGameClient`)
- [ ] Tester en parallèle : MITM passif + bot replay → compare résultats

### Après le bot fonctionnel
- [ ] UI WPF/Avalonia pour pilotage en live (équivalent du SwiftUI macOS)
- [ ] Import bibliothèque presets DofusDB
- [ ] Stats de session persistantes (SQLite)
- [ ] Anti-detect : pauses humanisées, alternance d'actions

Voir [`docs/REVERSE_ENGINEERING.md`](docs/REVERSE_ENGINEERING.md) pour le guide pas-à-pas.

## Comment contribuer

Pour porter un manque depuis le Swift :

1. Identifier le fichier Swift dans `MagusModules/Sources/`
2. Créer le pendant C# dans le bon projet (`Core/Persistence/Network`)
3. Conserver les commentaires importants du Swift (notamment dans `RuneWeights`,
   `MagingStrategy` P29, `ExoStrategy` V3 lissage)
4. Ajouter au moins un test de comportement dans `MagusBot.Core.Tests`
5. Vérifier qu'aucune valeur numérique n'a divergé du Swift (la table de poids
   est la **seule source de vérité**)

## Avertissements légaux

Ce projet automatise des actions in-game sur Dofus 3 — c'est contre les CGU d'Ankama. Usage **personnel uniquement, sur compte secondaire**. Ne distribue pas de binaires compilés, ne contribue pas de code permettant d'autres usages que celui de l'auteur original. L'auteur décline toute responsabilité.
