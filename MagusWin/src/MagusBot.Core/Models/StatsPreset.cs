namespace MagusBot.Core.Models;

/// <summary>
/// Une étape de FM dans un preset multi-étapes (inspiré ExoFast).
/// MVP : seul le type "Cibles" est supporté.
/// </summary>
public sealed record PresetStep(
    Guid Id,
    string Name,
    IReadOnlyDictionary<StatKind, StatTarget> Targets)
{
    public static PresetStep Create(string name, IReadOnlyDictionary<StatKind, StatTarget>? targets = null)
        => new(Guid.NewGuid(), name, targets ?? new Dictionary<StatKind, StatTarget>());
}

/// <summary>
/// Preset utilisateur : pour cet item, quelles sont les cibles par stat.
/// </summary>
public sealed record StatsPreset(
    Guid Id,
    string Name,
    PresetScenario Scenario,
    int? ItemSpecId,
    IReadOnlyDictionary<StatKind, StatTarget> Targets,
    IReadOnlyList<PresetStep> Steps,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt)
{
    public static StatsPreset Create(
        string name,
        PresetScenario scenario = PresetScenario.JetParfait,
        int? itemSpecId = null,
        IReadOnlyDictionary<StatKind, StatTarget>? targets = null,
        IReadOnlyList<PresetStep>? steps = null)
    {
        var now = DateTimeOffset.UtcNow;
        return new StatsPreset(
            Guid.NewGuid(),
            name,
            scenario,
            itemSpecId,
            targets ?? new Dictionary<StatKind, StatTarget>(),
            steps ?? Array.Empty<PresetStep>(),
            now,
            now);
    }

    public IReadOnlyDictionary<StatKind, StatTarget> EffectiveTargets(int stepIndex)
    {
        if (Steps.Count == 0) return Targets;
        if (stepIndex < 0 || stepIndex >= Steps.Count) return new Dictionary<StatKind, StatTarget>();
        return Steps[stepIndex].Targets;
    }

    public string? StepName(int index) =>
        index >= 0 && index < Steps.Count ? Steps[index].Name : null;

    public bool IsMultiStep => Steps.Count > 0;
    public int StepCount => Steps.Count;

    /// <summary>Génère un preset selon le scénario choisi.</summary>
    public static StatsPreset Make(PresetScenario scenario, ItemSpec spec) => scenario switch
    {
        PresetScenario.JetParfait => PerfectJet(spec),
        PresetScenario.ExoPA => ExoPa(spec),
        PresetScenario.ExoPM => ExoPm(spec),
        PresetScenario.ExoDoSort1 => ExoCustom(PresetScenario.ExoDoSort1, 123, 1, "+1% Do Sort", spec),
        PresetScenario.ExoDoSort2 => ExoCustom(PresetScenario.ExoDoSort2, 123, 2, "+2% Do Sort", spec),
        PresetScenario.ExoDoDistance1 => ExoCustom(PresetScenario.ExoDoDistance1, 120, 1, "+1% Do Distance", spec),
        PresetScenario.ExoDoDistance2 => ExoCustom(PresetScenario.ExoDoDistance2, 120, 2, "+2% Do Distance", spec),
        PresetScenario.OverVita => OverVita(spec),
        PresetScenario.Leveling => Leveling(spec),
        _ => PerfectJet(spec)
    };

    /// <summary>
    /// Génère un preset exo générique pour une stat non native (Do Sort, Do Distance, etc.).
    /// Toutes les stats natives sont poussées au max (tampon sacrificiel) + cible exo en plus.
    /// </summary>
    public static StatsPreset ExoCustom(PresetScenario scenario, int characteristicId, int target, string label, ItemSpec spec)
    {
        var targets = new Dictionary<StatKind, StatTarget>();
        foreach (var s in spec.Stats)
        {
            int value;
            int priority;
            if (s.HasVariableRange)
            {
                value = s.MaxValue;
                priority = 80;
            }
            else if (s.IsOverable)
            {
                value = s.MaxValue + 1;
                priority = 90;
            }
            else
            {
                value = s.MaxValue;
                priority = 50;
            }
            targets[s.Kind] = new StatTarget(value, s.MinValue, priority);
        }
        var exoKind = new StatKind(characteristicId);
        // Cible exo : caractéristique non native avec target = pourcentage souhaité (top priorité)
        targets[exoKind] = new StatTarget(target, null, 120);

        return Create($"Exo {label} — {spec.Name}", scenario, spec.Id, targets);
    }

    /// <summary>
    /// Leveling : on s'en fout du jet, on veut maximiser XP. Toutes les stats mageables
    /// ciblées au max avec priorité égale.
    /// </summary>
    public static StatsPreset Leveling(ItemSpec spec)
    {
        var targets = new Dictionary<StatKind, StatTarget>();
        foreach (var s in spec.Stats.Where(s => s.IsMageable))
            targets[s.Kind] = new StatTarget(s.MaxValue, s.MinValue, 50);
        return Create($"Leveling XP — {spec.Name}", PresetScenario.Leveling, spec.Id, targets);
    }

    /// <summary>
    /// Jet parfait : pour chaque stat de l'item, target + priorité adaptées.
    /// Priorités :
    /// - 120 : PA / PM (irremplaçables une fois perdus → top priorité)
    /// - 110 : Portée / Invocation (overable précieux)
    /// - 100 : stats avec variance (Vita, Fo, Sa, etc.)
    /// - 60  : stats fixes 1-1 (maintien seulement)
    /// </summary>
    public static StatsPreset PerfectJet(ItemSpec spec)
    {
        var targets = new Dictionary<StatKind, StatTarget>();
        foreach (var s in spec.Stats)
        {
            int target;
            int priority;
            if (s.HasVariableRange)
            {
                target = s.MaxValue;
                priority = 100;
            }
            else if (s.IsOverable)
            {
                // Overable (PO/Invo) : target = max + 1 et priorité haute car ces stats
                // sont coûteuses à remettre si elles tombent.
                target = s.MaxValue + 1;
                priority = 110;
            }
            else
            {
                target = s.MaxValue;
                priority = 60;
            }
            // PA / PM : priorité absolue. Si elles tombent, on les remet en premier.
            if (s.Kind.CharacteristicId is 1 or 23)
                priority = 120;
            targets[s.Kind] = new StatTarget(target, s.MinValue, priority);
        }
        return Create($"Jet parfait — {spec.Name}", PresetScenario.JetParfait, spec.Id, targets);
    }

    /// <summary>
    /// Génère un <see cref="ConfigPreset"/> avec des seuils Pa/Ra smart par stat,
    /// inspiré des règles ExoFast (ex: "Ra Age entre 45 et 50").
    /// </summary>
    public static ConfigPreset SmartConfig(ItemSpec spec, string baseName = "Smart")
    {
        var rules = new Dictionary<StatKind, ConfigRule>();
        foreach (var s in spec.Stats.Where(s => s.HasVariableRange))
        {
            var raBonus = RuneWeights.BonusPoints(s.Kind, RunePower.Ra);
            if (raBonus is null) continue;
            var maxV = s.MaxValue;
            var paFrom = Math.Min(10, maxV / 6);
            var raStart = Math.Max(paFrom + 1, maxV - raBonus.Value);
            var raEnd = Math.Max(raStart + 1, maxV - 1);
            rules[s.Kind] = new ConfigRule(
                UseBase: true,
                UsePa: true,
                UseRa: true,
                ThresholdPa: 20,
                ThresholdRa: 60,
                PaValueThreshold: new RuneThreshold.From(paFrom),
                RaValueThreshold: new RuneThreshold.Between(raStart, raEnd));
        }
        return ConfigPreset.Create($"{baseName} — {spec.Name}", rules, ConfigRule.Default);
    }

    /// <summary>Exo PA : cible PA en priorité absolue, autres stats à leur max avec priorité moyenne.</summary>
    public static StatsPreset ExoPa(ItemSpec spec)
    {
        var targets = new Dictionary<StatKind, StatTarget>();
        foreach (var s in spec.Stats.Where(s => s.IsMageable))
            targets[s.Kind] = new StatTarget(s.MaxValue, s.MinValue, 50);
        targets[StatKind.PA] = new StatTarget(1, 1, 100);
        return Create($"Exo PA — {spec.Name}", PresetScenario.ExoPA, spec.Id, targets);
    }

    /// <summary>Exo PM (id 23).</summary>
    public static StatsPreset ExoPm(ItemSpec spec)
    {
        var targets = new Dictionary<StatKind, StatTarget>();
        foreach (var s in spec.Stats.Where(s => s.IsMageable))
            targets[s.Kind] = new StatTarget(s.MaxValue, s.MinValue, 50);
        targets[StatKind.PM] = new StatTarget(1, 1, 100);
        return Create($"Exo PM — {spec.Name}", PresetScenario.ExoPM, spec.Id, targets);
    }

    /// <summary>Over Vita : jet parfait + Vita poussée au-delà du max.</summary>
    public static StatsPreset OverVita(ItemSpec spec)
    {
        var targets = new Dictionary<StatKind, StatTarget>();
        foreach (var s in spec.Stats.Where(s => s.IsMageable))
        {
            var isVita = s.Kind.CharacteristicId == 11;
            targets[s.Kind] = new StatTarget(
                isVita ? s.MaxValue + 50 : s.MaxValue,
                s.MinValue,
                isVita ? 100 : 70);
        }
        return Create($"Over Vita — {spec.Name}", PresetScenario.OverVita, spec.Id, targets);
    }
}
