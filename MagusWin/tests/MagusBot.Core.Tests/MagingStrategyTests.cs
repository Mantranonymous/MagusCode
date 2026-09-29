using FluentAssertions;
using MagusBot.Core.Models;
using MagusBot.Core.Strategies;
using Xunit;

namespace MagusBot.Core.Tests;

/// <summary>
/// Tests de comportement de la stratégie principale. Garde que les invariants
/// critiques (cap over, itération tous candidats, skip stats négatives) sont respectés.
/// </summary>
public sealed class MagingStrategyTests
{
    private readonly MagingStrategy _strategy = new();

    [Fact]
    public void Decide_NoItem_ReturnsBlocked()
    {
        var snapshot = GameStateSnapshot.Empty();
        var preset = MakePreset(new Dictionary<StatKind, StatTarget>
        {
            [StatKind.Force] = new(10)
        });

        var decision = _strategy.Decide(snapshot, preset, null);

        decision.Should().BeOfType<Decision.Blocked>();
        ((Decision.Blocked)decision).Reason.Should().BeOfType<BlockReason.NoItem>();
    }

    [Fact]
    public void Decide_NoTargets_ReturnsBlocked()
    {
        var item = Item.Create("test", stats: new[] { new Stat(StatKind.Force, 5, 1, 10) });
        var snapshot = new GameStateSnapshot(DateTimeOffset.UtcNow, item, Array.Empty<MageHistoryEntry>(), null, null, null);
        var preset = MakePreset(new Dictionary<StatKind, StatTarget>());

        var decision = _strategy.Decide(snapshot, preset, null);

        decision.Should().BeOfType<Decision.Blocked>();
        ((Decision.Blocked)decision).Reason.Should().BeOfType<BlockReason.NoPresetSelected>();
    }

    [Fact]
    public void Decide_AllStatsAtTarget_ReturnsFinished()
    {
        var item = Item.Create("test", stats: new[] { new Stat(StatKind.Force, 10, 1, 10) });
        var snapshot = new GameStateSnapshot(DateTimeOffset.UtcNow, item, Array.Empty<MageHistoryEntry>(), null, null, null);
        var preset = MakePreset(new Dictionary<StatKind, StatTarget>
        {
            [StatKind.Force] = new(Target: 10, Priority: 100)
        });

        var decision = _strategy.Decide(snapshot, preset, null);

        decision.Should().BeOfType<Decision.Finished>();
    }

    [Fact]
    public void Decide_NegativeStat_IsSkipped()
    {
        // Stat négative (ex: Tacle malus) → on ne doit pas la mager.
        var item = Item.Create("test", stats: new[]
        {
            new Stat(StatKind.Tacle, -5, -10, 0),
            new Stat(StatKind.Force, 5, 1, 10),
        });
        var snapshot = new GameStateSnapshot(DateTimeOffset.UtcNow, item, Array.Empty<MageHistoryEntry>(), null, null, null);
        var preset = MakePreset(new Dictionary<StatKind, StatTarget>
        {
            [StatKind.Tacle] = new(Target: 0, Priority: 100),
            [StatKind.Force] = new(Target: 10, Priority: 50),
        });

        var decision = _strategy.Decide(snapshot, preset, null);

        // Force doit être maged, pas Tacle
        decision.Should().BeOfType<Decision.ApplyRune>();
        ((Decision.ApplyRune)decision).On.Should().Be(StatKind.Force);
    }

    [Fact]
    public void Decide_IteratesAllCandidates_IfFirstHasNoViableRune()
    {
        // P29 : Vitalité 99/100 → aucune rune Vi (5/15/50) ne tient
        // sans dépasser. Doit fallback sur Force 5/10 qui elle est viable.
        var item = Item.Create("test", stats: new[]
        {
            new Stat(StatKind.Vitalite, 99, 1, 100),
            new Stat(StatKind.Force, 5, 1, 10),
        });
        var snapshot = new GameStateSnapshot(DateTimeOffset.UtcNow, item, Array.Empty<MageHistoryEntry>(), null, null, null);
        var preset = MakePreset(new Dictionary<StatKind, StatTarget>
        {
            [StatKind.Vitalite] = new(Target: 100, Priority: 100),
            [StatKind.Force] = new(Target: 10, Priority: 90),
        });

        var decision = _strategy.Decide(snapshot, preset, null);

        // Doit poser une rune sur Force (la 2e candidate)
        decision.Should().BeOfType<Decision.ApplyRune>();
        ((Decision.ApplyRune)decision).On.Should().Be(StatKind.Force);
    }

    [Fact]
    public void Decide_RespectsTargetCap_NoInvoluntaryOver()
    {
        // P23.1 : si target = 20, la stratégie ne doit jamais retourner une rune
        // qui pousserait au-delà de 20. Stat = 18, options : Base (+1) ou Pa (+3=21 STOP).
        var item = Item.Create("test", stats: new[] { new Stat(StatKind.Force, 18, 1, 20) });
        var snapshot = new GameStateSnapshot(DateTimeOffset.UtcNow, item, Array.Empty<MageHistoryEntry>(), null, null, null);
        var preset = MakePreset(new Dictionary<StatKind, StatTarget>
        {
            [StatKind.Force] = new(Target: 20, Priority: 100)
        });

        var decision = _strategy.Decide(snapshot, preset, null);

        decision.Should().BeOfType<Decision.ApplyRune>();
        var apply = (Decision.ApplyRune)decision;
        // Base = +1 → 19, Pa = +3 → 21 (interdit). Le pickBestRune va prendre Base.
        apply.Rune.Power.Should().Be(RunePower.Base);
    }

    private static PresetBundle MakePreset(IReadOnlyDictionary<StatKind, StatTarget> targets)
    {
        var stats = StatsPreset.Create("test", PresetScenario.JetParfait, targets: targets);
        return PresetBundle.Create(stats, ConfigPreset.BundledFast);
    }
}
