using MagusBot.Core.Models;

namespace MagusBot.Core.Strategies;

/// <summary>
/// Contrat commun aux différentes stratégies (Maging classique, Exo, Leveling...).
/// </summary>
public interface IDecisionStrategy
{
    string Name { get; }

    Decision Decide(GameStateSnapshot snapshot, PresetBundle preset, ItemSpec? spec);
}
