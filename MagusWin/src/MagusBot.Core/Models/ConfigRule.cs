namespace MagusBot.Core.Models;

/// <summary>
/// Règle de sélection de rune pour une stat donnée.
/// </summary>
public sealed record ConfigRule(
    bool UseBase = true,
    bool UsePa = true,
    bool UseRa = true,
    int ThresholdPa = 20,
    int ThresholdRa = 60,
    int MaxCanHit = 9999,
    RuneThreshold? PaValueThreshold = null,
    RuneThreshold? RaValueThreshold = null)
{
    public RuneThreshold EffectivePaThreshold => PaValueThreshold ?? new RuneThreshold.Always();
    public RuneThreshold EffectiveRaThreshold => RaValueThreshold ?? new RuneThreshold.Always();

    /// <summary>Règle par défaut suivant le guide FM (×20).</summary>
    public static readonly ConfigRule Default = new();
}
