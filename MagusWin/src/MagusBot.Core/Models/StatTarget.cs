namespace MagusBot.Core.Models;

/// <summary>Cible pour une stat donnée dans un preset.</summary>
public sealed record StatTarget(
    int Target,
    int? Minimum = null,
    int Priority = 100,
    bool Enabled = true);
