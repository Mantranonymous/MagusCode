namespace MagusBot.Core.Models;

/// <summary>
/// Scénario de FM. Détermine quelle stratégie utiliser et comment auto-générer le preset.
/// Aligné avec PresetScenario.swift.
/// </summary>
public enum PresetScenario
{
    JetParfait,
    ExoPA,
    ExoPM,
    ExoDoSort1,
    ExoDoSort2,
    ExoDoDistance1,
    ExoDoDistance2,
    OverVita,
    Leveling
}

public static class PresetScenarioExtensions
{
    public static string DisplayName(this PresetScenario scenario) => scenario switch
    {
        PresetScenario.JetParfait => "Jet parfait",
        PresetScenario.ExoPA => "Exo PA",
        PresetScenario.ExoPM => "Exo PM",
        PresetScenario.ExoDoSort1 => "Exo +1% Do Sort",
        PresetScenario.ExoDoSort2 => "Exo +2% Do Sort",
        PresetScenario.ExoDoDistance1 => "Exo +1% Do Distance",
        PresetScenario.ExoDoDistance2 => "Exo +2% Do Distance",
        PresetScenario.OverVita => "Over Vitalité",
        PresetScenario.Leveling => "Leveling XP",
        _ => "?"
    };

    public static string ShortName(this PresetScenario scenario) => scenario switch
    {
        PresetScenario.JetParfait => "JP",
        PresetScenario.ExoPA => "Exo PA",
        PresetScenario.ExoPM => "Exo PM",
        PresetScenario.ExoDoSort1 => "+1% Sort",
        PresetScenario.ExoDoSort2 => "+2% Sort",
        PresetScenario.ExoDoDistance1 => "+1% Dist",
        PresetScenario.ExoDoDistance2 => "+2% Dist",
        PresetScenario.OverVita => "Over Vita",
        PresetScenario.Leveling => "Leveling",
        _ => "?"
    };

    /// <summary>Pour les scénarios exo, retourne (characteristicId, targetValue).</summary>
    public static (int CharacteristicId, int Target)? ExoTarget(this PresetScenario scenario) => scenario switch
    {
        PresetScenario.ExoPA => (1, 1),
        PresetScenario.ExoPM => (23, 1),
        PresetScenario.ExoDoSort1 => (123, 1),
        PresetScenario.ExoDoSort2 => (123, 2),
        PresetScenario.ExoDoDistance1 => (120, 1),
        PresetScenario.ExoDoDistance2 => (120, 2),
        _ => null
    };
}
