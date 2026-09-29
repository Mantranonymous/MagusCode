namespace MagusBot.Core.Models;

/// <summary>
/// Décision sortie du Decision Engine. Toujours accompagnée d'une explication
/// lisible (<see cref="Explanation"/>) pour la confiance utilisateur.
/// </summary>
public abstract record Decision
{
    public abstract string Explanation { get; }

    public sealed record ApplyRune(Rune Rune, StatKind On, string Why) : Decision
    {
        public override string Explanation => Why;
    }

    public sealed record ApplyExo(PuteSlot Slot, string Why) : Decision
    {
        public override string Explanation => Why;
    }

    public sealed record ApplyAntiRune(Rune Rune, StatKind On, string Why) : Decision
    {
        public override string Explanation => Why;
    }

    public sealed record Finished(string Why) : Decision
    {
        public override string Explanation => Why;
    }

    public sealed record WaitingForUser(string Reason) : Decision
    {
        public override string Explanation => Reason;
    }

    public sealed record Blocked(BlockReason Reason) : Decision
    {
        public override string Explanation => Reason.Description;
    }
}

/// <summary>Raisons pour lesquelles une décision est bloquée.</summary>
public abstract record BlockReason
{
    public abstract string Description { get; }

    public sealed record NoItem : BlockReason
    {
        public override string Description => "Aucun item détecté sur l'établi";
    }

    public sealed record NoPresetSelected : BlockReason
    {
        public override string Description => "Aucun preset sélectionné";
    }

    public sealed record NoItemSpec : BlockReason
    {
        public override string Description => "Item non sélectionné — choisis-le dans la carte « Item à mager »";
    }

    public sealed record OcrInsufficient(IReadOnlyList<string> Missing) : BlockReason
    {
        public override string Description => $"OCR insuffisant : {string.Join(", ", Missing)}";
    }

    public sealed record RuneOutOfStock(Rune Rune) : BlockReason
    {
        public override string Description => $"Rune {Rune.Power.ShortLabel()} manquante";
    }

    public sealed record NoActionPossible(string Message) : BlockReason
    {
        public override string Description => $"Aucune action possible : {Message}";
    }
}
