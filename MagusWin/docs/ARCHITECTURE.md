# Architecture MagusWin

## Vue d'ensemble

```
+-----------------------+
| MagusBot.Cli          |
|  - Program.Main       |
|  - DI + Logging       |
|  - Boucle décision    |
+-----------+-----------+
            |
            v
+-----------+-----------+
| MagusBot.Core         |
|  - Models             |  StatKind, Rune, Stat, Item, ItemSpec,
|                       |  StatsPreset, ConfigPreset, PresetBundle,
|                       |  Decision, BlockReason, GameStateSnapshot
|  - RuneWeights        |  table canonique 52 effets (poids unitaires + bonus)
|  - ReliquatTracker    |  formule du puits darckoune
|  - SuccessProbability |  modèle EasyFM (SC/SN/EC)
|  - Strategies/        |  MagingStrategy V3, ExoStrategy V3,
|                       |  ExoPercentStrategy 3-phases, LevelingStrategy,
|                       |  DecisionEngine (dispatch par scenario)
+-----------+-----------+
            |
   +--------+----------+
   |                   |
   v                   v
+--+----------+   +----+-------------+
| Persistence |   | Network          |
|  - Efitem   |   |  - IGameClient   |  contrat haut-niveau
|    Importer |   |  - StubGameClient|  impl factice (random SC/SN/EC)
+-------------+   |  - DofusGameClient  TODO (vraie impl après RE)
                  |  - Messages/     |  packets (stubs IDs à RE)
                  |  - Codec/        |  encodeur binaire (TODO RE)
                  +------------------+
```

## Couches et dépendances

- `Core` ne dépend de **personne** (sauf `Microsoft.Extensions.Logging.Abstractions`).
- `Persistence` dépend de `Core` uniquement (utilise les models pour les targets).
- `Network` dépend de `Core` uniquement (utilise les models pour exposer un snapshot).
- `Cli` dépend de tout — c'est lui qui assemble la session.

Cette stricte hiérarchie permet de tester `Core` isolément, et de remplacer
`StubGameClient` par `DofusGameClient` (futur) sans toucher la logique métier.

## Flow décision

```
+-------------+  events  +--------------+  states    +-----------------+
| IGameClient |--------->| StateUpdater |----------->| GameStateSnapshot|
+-------------+          +--------------+            +--------+--------+
                                                              |
                                                              v
                                                     +--------+--------+
                                                     | DecisionEngine  |
                                                     |  + PresetBundle |
                                                     |  + ItemSpec     |
                                                     +--------+--------+
                                                              |
                                                              v
                                                     +--------+--------+
                                                     | Decision        |
                                                     |  - ApplyRune    |
                                                     |  - Finished     |
                                                     |  - Blocked      |
                                                     |  - WaitingForUser|
                                                     +--------+--------+
                                                              |
                                                              v
                                                     +--------+--------+
                                                     | IGameClient.    |
                                                     | SendApplyRune   |
                                                     +-----------------+
```

Détails :

1. Le client réseau (réel ou stub) émet `StateChanged` chaque fois que l'état FM
   bouge (nouvelle stat reçue du serveur, reliquat mis à jour, etc.)
2. L'orchestrateur (CLI ou UI) construit un `GameStateSnapshot` immuable
3. Il appelle `DecisionEngine.Decide(snapshot, preset, spec)` qui dispatche
   sur la bonne stratégie selon `preset.Stats.Scenario`
4. La stratégie retourne une `Decision` (sous-type discriminé)
5. Si `ApplyRune` → envoie un `FmActionPacket` (via `IGameClient.SendApplyRuneAsync`)
6. Le serveur répond avec un `FmResultPacket` → re-met-à-jour l'état → goto 1

## Ajouter une nouvelle stratégie

1. Créer une classe qui implémente `IDecisionStrategy` dans
   `src/MagusBot.Core/Strategies/`.
2. Si elle doit être routée via un nouveau scénario, ajouter une valeur dans
   `PresetScenario` enum et son cas dans `DecisionEngine.Decide`.
3. Si la stratégie ajoute des cibles auto, créer une méthode statique
   `StatsPreset.MaNouvelle(spec)` qui produit le bon set de targets.
4. Ajouter au moins un test xUnit qui couvre le cas nominal et un cas bloquant.

Convention : préfère composer (la stratégie délègue à `MagingStrategy` quand
appropriée, comme `ExoStrategy` / `ExoPercentStrategy` le font) plutôt que de
dupliquer la logique de sélection de rune.

## Swap StubGameClient → vraie impl

Le `StubGameClient` est instancié explicitement dans `MagusBot.Cli/Program.cs`.

Pour passer en mode réel :

1. Créer `MagusBot.Network/Real/DofusGameClient.cs` qui implémente `IGameClient`.
2. Dans `Program.cs`, swap la ligne
   ```csharp
   await using var client = new StubGameClient(...);
   ```
   par
   ```csharp
   await using var client = new DofusGameClient(serverEndpoint, accountCreds);
   ```
3. Le reste de la CLI ne change pas — la boucle de décision est agnostique.

Important : injecter le client par DI (`services.AddSingleton<IGameClient, ...>`)
quand on ajoute une UI WPF/Avalonia, pour permettre de toggler stub/réel dans
les préférences utilisateur.

## Différences vs Swift original

| Aspect | Swift (macOS) | C# (.NET 8) |
|---|---|---|
| Source d'état | OCR + capture écran | Packets réseau décodés |
| Action | Simulation de clic CGEvent | Envoi de `FmActionPacket` au serveur |
| Persistence | GRDB (SQLite) | Pas d'équivalent au MVP — à ajouter (EF Core ou SQLite via `Microsoft.Data.Sqlite`) |
| Reference data | DofusDB sync + cache | À ajouter — pourra utiliser DofusDB API HTTP directement |
| UI | SwiftUI macOS | À ajouter (WPF ou Avalonia) — hors scope du MVP |
