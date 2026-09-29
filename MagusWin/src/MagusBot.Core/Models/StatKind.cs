namespace MagusBot.Core.Models;

/// <summary>
/// Identifie une caractéristique (stat) Dofus de façon générique.
/// Le <see cref="CharacteristicId"/> correspond à l'ID DofusDB (table ref_characteristics).
/// Le nom d'affichage est résolu dynamiquement via la table de référence.
/// </summary>
public readonly record struct StatKind(int CharacteristicId)
{
    public override string ToString() => $"StatKind(#{CharacteristicId})";

    // Constantes pratiques pour les stats courantes.
    public static readonly StatKind PA = new(1);
    public static readonly StatKind PM = new(23);
    public static readonly StatKind Portee = new(19);
    public static readonly StatKind Vitalite = new(11);
    public static readonly StatKind Force = new(10);
    public static readonly StatKind Chance = new(13);
    public static readonly StatKind Agilite = new(14);
    public static readonly StatKind Intelligence = new(15);
    public static readonly StatKind Sagesse = new(12);
    public static readonly StatKind Prospection = new(48);
    public static readonly StatKind Dommages = new(16);
    public static readonly StatKind Critique = new(18);
    public static readonly StatKind Soins = new(49);
    public static readonly StatKind Initiative = new(44);
    public static readonly StatKind Puissance = new(25);
    public static readonly StatKind Pods = new(40);
    public static readonly StatKind Invocations = new(26);
    public static readonly StatKind Fuite = new(78);
    public static readonly StatKind Tacle = new(79);
    public static readonly StatKind DommagesDistance = new(120);
    public static readonly StatKind DommagesSort = new(123);
}
