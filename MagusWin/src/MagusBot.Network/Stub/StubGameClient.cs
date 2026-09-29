using MagusBot.Core;
using MagusBot.Core.Models;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;

namespace MagusBot.Network.Stub;

/// <summary>
/// Implémentation factice de <see cref="IGameClient"/> qui simule un état d'item
/// + résultats aléatoires SC/SN/EC pondérés. Permet de tester la boucle de
/// décision end-to-end sans avoir besoin d'un client réseau réel.
///
/// Distribution des résultats (paramétrable) :
/// <list type="bullet">
/// <item>SC ~ 15%</item>
/// <item>SN ~ 50%</item>
/// <item>EC ~ 35%</item>
/// </list>
/// </summary>
public sealed class StubGameClient : IGameClient
{
    private readonly ILogger<StubGameClient> _logger;
    private readonly Random _rng;
    private readonly object _lock = new();
    private GameStateSnapshot _snapshot;
    private bool _connected;

    /// <summary>Probabilité SC (0-1).</summary>
    public double ScProbability { get; init; } = 0.15;
    /// <summary>Probabilité SN (0-1).</summary>
    public double SnProbability { get; init; } = 0.50;
    /// <summary>Probabilité EC = 1 - SC - SN.</summary>
    public double EcProbability => Math.Max(0, 1 - ScProbability - SnProbability);

    public bool IsConnected => _connected;

    public event EventHandler<FmResultEventArgs>? ResultReceived;
    public event EventHandler<StateChangedEventArgs>? StateChanged;

    public StubGameClient(ILogger<StubGameClient>? logger = null, int? seed = null, GameStateSnapshot? initial = null)
    {
        _logger = logger ?? NullLogger<StubGameClient>.Instance;
        _rng = seed is { } s ? new Random(s) : new Random();
        _snapshot = initial ?? CreateDefaultSnapshot();
    }

    public Task ConnectAsync(CancellationToken ct = default)
    {
        _connected = true;
        _logger.LogInformation("StubGameClient connected. Item: {ItemName}", _snapshot.Item?.Name ?? "(none)");
        return Task.CompletedTask;
    }

    public Task<GameStateSnapshot> GetSnapshotAsync(CancellationToken ct = default)
    {
        lock (_lock)
        {
            return Task.FromResult(_snapshot);
        }
    }

    public async Task SendApplyRuneAsync(Rune rune, StatKind on, CancellationToken ct = default)
    {
        if (!_connected) throw new InvalidOperationException("Client not connected");
        var weight = RuneWeights.Weight(rune) ?? 0;
        var bonus = RuneWeights.BonusPoints(rune.Kind, rune.Power) ?? 0;
        _logger.LogDebug("Apply rune {Power} on stat #{Cid} (bonus +{Bonus}, weight {Weight})",
            rune.Power, on.CharacteristicId, bonus, weight);

        // Petit délai pour simuler la latence
        await Task.Delay(50, ct);

        var result = RollOutcome();
        ApplyResultLocally(rune, on, result, bonus, weight);

        var args = new FmResultEventArgs
        {
            Result = result,
            Rune = rune,
            TargetStat = on,
            Delta = result switch
            {
                CombineResult.CriticalSuccess => bonus,
                CombineResult.NeutralSuccess => bonus,
                CombineResult.CriticalFail => 0,
                _ => 0
            },
            ReliquatDelta = result switch
            {
                CombineResult.CriticalSuccess => -weight,
                CombineResult.NeutralSuccess => 0,
                CombineResult.CriticalFail => weight,
                _ => 0
            },
            Snapshot = _snapshot
        };
        ResultReceived?.Invoke(this, args);
        StateChanged?.Invoke(this, new StateChangedEventArgs { Snapshot = _snapshot });
    }

    public ValueTask DisposeAsync()
    {
        _connected = false;
        return ValueTask.CompletedTask;
    }

    /// <summary>Remplace le snapshot courant (utile pour les tests).</summary>
    public void SetSnapshot(GameStateSnapshot snapshot)
    {
        lock (_lock)
        {
            _snapshot = snapshot;
        }
        StateChanged?.Invoke(this, new StateChangedEventArgs { Snapshot = snapshot });
    }

    private CombineResult RollOutcome()
    {
        var roll = _rng.NextDouble();
        if (roll < ScProbability) return CombineResult.CriticalSuccess;
        if (roll < ScProbability + SnProbability) return CombineResult.NeutralSuccess;
        return CombineResult.CriticalFail;
    }

    private void ApplyResultLocally(Rune rune, StatKind on, CombineResult result, int bonus, double weight)
    {
        lock (_lock)
        {
            if (_snapshot.Item is not { } item) return;

            // 1. Mise à jour de la stat ciblée
            var newStats = item.Stats.ToList();
            var idx = newStats.FindIndex(s => s.Kind == on);
            if (idx < 0)
            {
                // Stat absente : on l'ajoute (cas exo PA/PM non native)
                if (result is CombineResult.CriticalSuccess or CombineResult.NeutralSuccess)
                {
                    newStats.Add(new Stat(on, bonus, 0, null));
                }
            }
            else
            {
                var s = newStats[idx];
                var delta = result switch
                {
                    CombineResult.CriticalSuccess => bonus,
                    CombineResult.NeutralSuccess => bonus,
                    _ => 0
                };
                newStats[idx] = s with { Value = s.Value + delta };
            }

            // 2. Mise à jour du reliquat
            var reliquat = _snapshot.Reliquat ?? new Reliquat(0);
            reliquat = result switch
            {
                CombineResult.CriticalSuccess => reliquat.Consuming(weight),
                CombineResult.NeutralSuccess => reliquat,
                CombineResult.CriticalFail => reliquat.Gaining(weight),
                _ => reliquat
            };

            // 3. Historique
            var newHistory = _snapshot.History.ToList();
            newHistory.Add(MageHistoryEntry.Create(
                result,
                CombineKind.SmRune,
                on,
                result == CombineResult.CriticalFail ? 0 : bonus,
                $"stub:{rune.Power.ShortLabel()}"));

            // 4. Rebuild snapshot
            var newItem = item with { Stats = newStats };
            _snapshot = _snapshot with
            {
                Item = newItem,
                Reliquat = reliquat,
                History = newHistory,
                Timestamp = DateTimeOffset.UtcNow
            };
        }
    }

    /// <summary>Génère un snapshot par défaut "Amulette de l'aventurier" partiellement magée.</summary>
    private static GameStateSnapshot CreateDefaultSnapshot()
    {
        var item = Item.Create(
            name: "Amulette du Bouftou (stub)",
            referenceItemId: 1234,
            level: 100,
            stats: new List<Stat>
            {
                new(StatKind.Vitalite,    60,  1,  80),
                new(StatKind.Force,       12,  1,  20),
                new(StatKind.Sagesse,      4,  1,  10),
                new(StatKind.Chance,       8,  1,  15),
                new(StatKind.Critique,     0,  0,   3),
            });

        return new GameStateSnapshot(
            DateTimeOffset.UtcNow,
            item,
            new List<MageHistoryEntry>(),
            new Reliquat(12.0),
            JobLevel: 100,
            JobName: "Forgemagie");
    }
}
