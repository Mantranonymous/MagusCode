namespace MagusBot.Core.Models;

/// <summary>
/// Spec d'une stat sur un item : qu'est-ce qu'elle peut donner au min et au max.
/// </summary>
public sealed record StatSpec(
    StatKind Kind,
    string DisplayName,
    int MinValue,
    int MaxValue,
    int Order = 0)
{
    /// <summary>Largeur de la range (utile pour pondérer la difficulté).</summary>
    public int RangeSpan => MaxValue - MinValue;

    /// <summary>
    /// Vrai si la stat est "over-able" — il vaut la peine de tenter un over
    /// (ex: Portée 1→2 sur un anneau, Invocation 1→2).
    /// </summary>
    public bool IsOverable => Kind.CharacteristicId is 19 or 156;

    /// <summary>
    /// Toute stat existante sur l'item est mageable : même les "fixes" peuvent
    /// tomber pendant le maging (SN qui les drop), et il faut alors les remettre
    /// à leur valeur initiale via une rune.
    /// </summary>
    public bool IsMageable => true;

    /// <summary>Vrai si la stat a un range avec variance (jet mageable au sens classique).</summary>
    public bool HasVariableRange => MaxValue > MinValue;
}
