using MagusBot.Core.Models;

namespace MagusBot.Core.Strategies;

/// <summary>Mode de session actif (Maging / Exo / Leveling).</summary>
public enum SessionMode
{
    Maging,
    Exo,
    Leveling
}

/// <summary>
/// Façade principale du moteur de décision. Choisit la stratégie selon le scénario du preset.
/// </summary>
public sealed class DecisionEngine
{
    private readonly MagingStrategy _maging;
    private readonly ExoStrategy _exoPa;
    private readonly ExoStrategy _exoPm;
    private readonly LevelingStrategy _leveling;

    public DecisionEngine()
    {
        _maging = new MagingStrategy();
        _exoPa = new ExoStrategy(new ExoStrategy.Variant.ExoPa());
        _exoPm = new ExoStrategy(new ExoStrategy.Variant.ExoPm());
        _leveling = new LevelingStrategy();
    }

    public Decision Decide(
        GameStateSnapshot snapshot,
        PresetBundle preset,
        ItemSpec? spec,
        SessionMode mode = SessionMode.Maging)
    {
        var scenario = preset.Stats.Scenario;
        return scenario switch
        {
            PresetScenario.JetParfait => _maging.Decide(snapshot, preset, spec),
            PresetScenario.OverVita => _maging.Decide(snapshot, preset, spec),
            PresetScenario.ExoPA => _exoPa.Decide(snapshot, preset, spec),
            PresetScenario.ExoPM => _exoPm.Decide(snapshot, preset, spec),
            PresetScenario.Leveling => _leveling.Decide(snapshot, preset, spec),
            PresetScenario.ExoDoSort1 =>
                new ExoPercentStrategy(ExoPercentStrategy.Variant.DoSort(1)).Decide(snapshot, preset, spec),
            PresetScenario.ExoDoSort2 =>
                new ExoPercentStrategy(ExoPercentStrategy.Variant.DoSort(2)).Decide(snapshot, preset, spec),
            PresetScenario.ExoDoDistance1 =>
                new ExoPercentStrategy(ExoPercentStrategy.Variant.DoDistance(1)).Decide(snapshot, preset, spec),
            PresetScenario.ExoDoDistance2 =>
                new ExoPercentStrategy(ExoPercentStrategy.Variant.DoDistance(2)).Decide(snapshot, preset, spec),
            _ => _maging.Decide(snapshot, preset, spec)
        };
    }
}
