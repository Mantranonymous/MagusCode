namespace MagusBot.Core.Models;

/// <summary>
/// Bundle d'un preset stats + config, passé au DecisionEngine.
/// </summary>
public sealed record PresetBundle(
    StatsPreset Stats,
    ConfigPreset Config,
    IReadOnlySet<Rune> DepletedRunes)
{
    public static PresetBundle Create(StatsPreset stats, ConfigPreset config, IReadOnlySet<Rune>? depletedRunes = null)
        => new(stats, config, depletedRunes ?? new HashSet<Rune>());
}
