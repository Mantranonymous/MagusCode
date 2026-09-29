namespace MagusBot.Core.Models;

/// <summary>
/// Preset de configuration : comment résoudre les runes par stat.
/// </summary>
public sealed record ConfigPreset(
    Guid Id,
    string Name,
    IReadOnlyDictionary<StatKind, ConfigRule> Rules,
    ConfigRule DefaultRule,
    bool AlternateExoPaPm,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt)
{
    public static ConfigPreset Create(
        string name,
        IReadOnlyDictionary<StatKind, ConfigRule>? rules = null,
        ConfigRule? defaultRule = null,
        bool alternateExoPaPm = false)
    {
        var now = DateTimeOffset.UtcNow;
        return new ConfigPreset(
            Guid.NewGuid(),
            name,
            rules ?? new Dictionary<StatKind, ConfigRule>(),
            defaultRule ?? ConfigRule.Default,
            alternateExoPaPm,
            now,
            now);
    }

    public ConfigRule Rule(StatKind kind) => Rules.TryGetValue(kind, out var r) ? r : DefaultRule;

    /// <summary>Preset par défaut "Rapide" : utilise les 3 rangs avec règle ×20 classique.</summary>
    public static readonly ConfigPreset BundledFast = Create(
        "Rapide (règle ×20)",
        defaultRule: ConfigRule.Default);

    /// <summary>Preset par défaut "Économe" : ne fait que des runes base + PA (jamais RA).</summary>
    public static readonly ConfigPreset BundledEconomic = Create(
        "Économe (sans RA)",
        defaultRule: new ConfigRule(UseBase: true, UsePa: true, UseRa: false, ThresholdPa: 10));
}
