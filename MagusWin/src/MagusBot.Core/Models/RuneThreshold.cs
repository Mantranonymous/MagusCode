namespace MagusBot.Core.Models;

/// <summary>
/// Seuil d'activation d'un rang de rune en fonction de la VALEUR COURANTE d'une stat.
/// Inspiré d'ExoFast : on peut dire "Ra Age entre 45 et 50" ou "Pa Fo à partir de 10".
/// </summary>
public abstract record RuneThreshold
{
    public abstract bool Allows(int currentValue);
    public abstract string DisplayString { get; }

    /// <summary>Toujours utiliser ce rang (pas de contrainte de valeur).</summary>
    public sealed record Always : RuneThreshold
    {
        public override bool Allows(int currentValue) => true;
        public override string DisplayString => "toujours";
    }

    /// <summary>Ne jamais utiliser ce rang.</summary>
    public sealed record Never : RuneThreshold
    {
        public override bool Allows(int currentValue) => false;
        public override string DisplayString => "jamais";
    }

    /// <summary>À partir d'une valeur. Ex: From(10) → utilise si stat ≥ 10.</summary>
    public sealed record From(int Value) : RuneThreshold
    {
        public override bool Allows(int currentValue) => currentValue >= Value;
        public override string DisplayString => $"→ {Value}";
    }

    /// <summary>Jusqu'à une valeur. Ex: Until(50) → utilise si stat ≤ 50.</summary>
    public sealed record Until(int Value) : RuneThreshold
    {
        public override bool Allows(int currentValue) => currentValue <= Value;
        public override string DisplayString => $"← {Value}";
    }

    /// <summary>Entre deux valeurs (inclusif).</summary>
    public sealed record Between(int Low, int High) : RuneThreshold
    {
        public override bool Allows(int currentValue) => currentValue >= Low && currentValue <= High;
        public override string DisplayString => $"{Low}–{High}";
    }
}
