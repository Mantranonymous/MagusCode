namespace MagusBot.Core.Models;

/// <summary>Résultat d'un combine de FM. Reflète l'historique côté Dofus.</summary>
public enum CombineResult
{
    /// <summary>SC — Succès Critique : la rune passe sans contrepartie.</summary>
    CriticalSuccess,
    /// <summary>SN — Succès Neutre : la rune passe mais retire son poids ailleurs.</summary>
    NeutralSuccess,
    /// <summary>EC — Échec Critique : la rune échoue ET retire son poids.</summary>
    CriticalFail,
    Unknown
}

public enum CombineKind
{
    SmRune,
    RaRune,
    PaRune,
    SmInverse,
    RaInverse,
    PaInverse,
    PuteExo,
    PuteInverse,
    Unknown
}

public static class CombineResultExtensions
{
    public static string ShortLabel(this CombineResult result) => result switch
    {
        CombineResult.CriticalSuccess => "SC",
        CombineResult.NeutralSuccess => "SN",
        CombineResult.CriticalFail => "EC",
        _ => "?"
    };
}

/// <summary>Une entrée dans l'historique des combines forgemagie.</summary>
public sealed record MageHistoryEntry(
    Guid Id,
    CombineResult Result,
    CombineKind Kind,
    StatKind? TargetStat = null,
    int Delta = 0,
    string Raw = "")
{
    public static MageHistoryEntry Create(
        CombineResult result,
        CombineKind kind,
        StatKind? targetStat = null,
        int delta = 0,
        string raw = "")
        => new(Guid.NewGuid(), result, kind, targetStat, delta, raw);
}
