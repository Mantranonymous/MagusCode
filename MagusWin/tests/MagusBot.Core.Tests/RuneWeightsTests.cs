using FluentAssertions;
using MagusBot.Core;
using MagusBot.Core.Models;
using Xunit;

namespace MagusBot.Core.Tests;

/// <summary>
/// Tests de la table canonique des poids de runes. Toute divergence avec le Swift
/// (<c>MagusModules/Sources/MagusCore/Models/RuneWeights.swift</c>) doit faire échouer
/// l'un de ces tests.
/// </summary>
public sealed class RuneWeightsTests
{
    // === Bonus de stat par rune ===

    [Fact]
    public void BonusPoints_Vitalite_ReturnsCorrectValues()
    {
        RuneWeights.BonusPoints(StatKind.Vitalite, RunePower.Base).Should().Be(5);
        RuneWeights.BonusPoints(StatKind.Vitalite, RunePower.Pa).Should().Be(15);
        RuneWeights.BonusPoints(StatKind.Vitalite, RunePower.Ra).Should().Be(50);
    }

    [Fact]
    public void BonusPoints_PA_OnlyBase()
    {
        // PA n'a qu'une rune Base en jeu.
        RuneWeights.BonusPoints(StatKind.PA, RunePower.Base).Should().Be(1);
        RuneWeights.BonusPoints(StatKind.PA, RunePower.Pa).Should().BeNull();
        RuneWeights.BonusPoints(StatKind.PA, RunePower.Ra).Should().BeNull();
    }

    [Fact]
    public void BonusPoints_PM_OnlyBase()
    {
        RuneWeights.BonusPoints(StatKind.PM, RunePower.Base).Should().Be(1);
        RuneWeights.BonusPoints(StatKind.PM, RunePower.Pa).Should().BeNull();
        RuneWeights.BonusPoints(StatKind.PM, RunePower.Ra).Should().BeNull();
    }

    [Fact]
    public void BonusPoints_DommageElementaire_NoRaInDofus3()
    {
        // Dommages élémentaires (88-92) : pas de Ra en Dofus 3.
        var feu = new StatKind(89);
        RuneWeights.BonusPoints(feu, RunePower.Base).Should().Be(1);
        RuneWeights.BonusPoints(feu, RunePower.Pa).Should().Be(3);
        RuneWeights.BonusPoints(feu, RunePower.Ra).Should().BeNull();
    }

    [Fact]
    public void BonusPoints_Initiative_HighDensity()
    {
        RuneWeights.BonusPoints(StatKind.Initiative, RunePower.Base).Should().Be(10);
        RuneWeights.BonusPoints(StatKind.Initiative, RunePower.Pa).Should().Be(30);
        RuneWeights.BonusPoints(StatKind.Initiative, RunePower.Ra).Should().Be(100);
    }

    [Fact]
    public void BonusPoints_Pods_DistinctValues()
    {
        RuneWeights.BonusPoints(StatKind.Pods, RunePower.Base).Should().Be(4);
        RuneWeights.BonusPoints(StatKind.Pods, RunePower.Pa).Should().Be(10);
        RuneWeights.BonusPoints(StatKind.Pods, RunePower.Ra).Should().Be(20);
    }

    [Fact]
    public void BonusPoints_Force_Standard1_3_10()
    {
        RuneWeights.BonusPoints(StatKind.Force, RunePower.Base).Should().Be(1);
        RuneWeights.BonusPoints(StatKind.Force, RunePower.Pa).Should().Be(3);
        RuneWeights.BonusPoints(StatKind.Force, RunePower.Ra).Should().Be(10);
    }

    // === Poids unitaires ===

    [Fact]
    public void UnitWeight_PA_Returns100()
    {
        RuneWeights.UnitWeight(StatKind.PA).Should().Be(100.0);
    }

    [Fact]
    public void UnitWeight_PM_Returns90()
    {
        RuneWeights.UnitWeight(StatKind.PM).Should().Be(90.0);
    }

    [Fact]
    public void UnitWeight_Vitalite_ReturnsPoint25()
    {
        RuneWeights.UnitWeight(StatKind.Vitalite).Should().Be(0.25);
    }

    [Fact]
    public void UnitWeight_Initiative_ReturnsPoint1()
    {
        RuneWeights.UnitWeight(StatKind.Initiative).Should().Be(0.1);
    }

    [Fact]
    public void UnitWeight_UnknownStat_FallbackTo1()
    {
        var unknown = new StatKind(9999);
        RuneWeights.UnitWeight(unknown).Should().Be(1.0);
    }

    // === Cap over ===

    [Fact]
    public void MaxOverPoints_Vitalite_Returns404()
    {
        // 101 / 0.25 = 404
        RuneWeights.MaxOverPoints(StatKind.Vitalite).Should().Be(404);
    }

    [Fact]
    public void MaxOverPoints_PA_Returns1()
    {
        // 101 / 100 = 1.01 → 1
        RuneWeights.MaxOverPoints(StatKind.PA).Should().Be(1);
    }

    [Fact]
    public void MaxOverPoints_Initiative_Returns1010()
    {
        // 101 / 0.1 = 1010
        RuneWeights.MaxOverPoints(StatKind.Initiative).Should().Be(1010);
    }

    // === Poids total d'une rune ===

    [Fact]
    public void Weight_PaVi_Returns3_75()
    {
        // 15 (bonus PaVi) * 0.25 (poids Vita) = 3.75
        var rune = new Rune(StatKind.Vitalite, RunePower.Pa);
        RuneWeights.Weight(rune).Should().BeApproximately(3.75, 0.0001);
    }

    [Fact]
    public void Weight_BasePA_Returns100()
    {
        var rune = new Rune(StatKind.PA, RunePower.Base);
        RuneWeights.Weight(rune).Should().Be(100.0);
    }

    [Fact]
    public void Weight_RaForce_Returns10()
    {
        // 10 * 1.0 = 10
        var rune = new Rune(StatKind.Force, RunePower.Ra);
        RuneWeights.Weight(rune).Should().Be(10.0);
    }

    [Fact]
    public void Weight_NonExistentRune_ReturnsNull()
    {
        var paOnPa = new Rune(StatKind.PA, RunePower.Pa);
        RuneWeights.Weight(paOnPa).Should().BeNull();
    }

    // === Available runes ===

    [Fact]
    public void AvailableRunes_PA_OnlyBase()
    {
        var runes = RuneWeights.AvailableRunes(StatKind.PA);
        runes.Should().HaveCount(1);
        runes[0].Power.Should().Be(RunePower.Base);
    }

    [Fact]
    public void AvailableRunes_DommageFeu_BaseAndPa()
    {
        var feu = new StatKind(89);
        var runes = RuneWeights.AvailableRunes(feu);
        runes.Should().HaveCount(2);
        runes.Select(r => r.Power).Should().Contain(new[] { RunePower.Base, RunePower.Pa });
    }

    [Fact]
    public void AvailableRunes_Vitalite_BasePaRa()
    {
        var runes = RuneWeights.AvailableRunes(StatKind.Vitalite);
        runes.Should().HaveCount(3);
    }

    // === BaseOnlyStats / BaseAndPaOnlyStats integrity ===

    [Fact]
    public void BaseOnlyStats_ContainsExpectedIds()
    {
        var expected = new[] { 1, 23, 19, 16, 18, 49, 33, 34, 35, 36, 37 };
        foreach (var id in expected)
            RuneWeights.BaseOnlyStats.Should().Contain(id, $"stat {id} must be base-only in Dofus 3");
    }

    [Fact]
    public void BaseAndPaOnlyStats_ContainsExpectedIds()
    {
        var expected = new[] { 88, 89, 90, 91, 92, 48, 78, 79 };
        foreach (var id in expected)
            RuneWeights.BaseAndPaOnlyStats.Should().Contain(id, $"stat {id} must allow base+Pa only in Dofus 3");
    }

    [Fact]
    public void Constants_MaxOverWeightPerStat_Is101()
    {
        // Hard guard contre une modif accidentelle du cap d'over.
        RuneWeights.MaxOverWeightPerStat.Should().Be(101.0);
    }
}
