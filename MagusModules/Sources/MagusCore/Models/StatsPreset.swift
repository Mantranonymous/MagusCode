import Foundation

/// Cible pour une stat donnée dans un preset.
public struct StatTarget: Hashable, Codable, Sendable {
    public let target: Int       // valeur cible
    public let minimum: Int?     // valeur acceptable minimum (au-dessous on remage)
    public let priority: Int     // 1...100, plus haut = plus important
    public let enabled: Bool     // si false, on ignore cette stat

    public init(target: Int, minimum: Int? = nil, priority: Int = 100, enabled: Bool = true) {
        self.target = target
        self.minimum = minimum
        self.priority = priority
        self.enabled = enabled
    }
}

/// Scénario de FM. Détermine quelle stratégie utiliser et comment auto-générer le preset.
public enum PresetScenario: String, Codable, CaseIterable, Sendable {
    case jetParfait        // toutes les stats au max théorique
    case exoPA             // tente d'ajouter un PA exotique
    case exoPM             // tente d'ajouter un PM exotique
    case exoDoSort1        // tente +1% Dommages Sorts (characteristicId 123)
    case exoDoSort2        // tente +2% Dommages Sorts
    case exoDoDistance1    // tente +1% Dommages Distance (characteristicId 120)
    case exoDoDistance2    // tente +2% Dommages Distance
    case overVita          // jet parfait + over Vitalité
    case leveling          // maximise XP métier — clique des grosses runes en boucle

    public var displayName: String {
        switch self {
        case .jetParfait: return "Jet parfait"
        case .exoPA: return "Exo PA"
        case .exoPM: return "Exo PM"
        case .exoDoSort1: return "Exo +1% Do Sort"
        case .exoDoSort2: return "Exo +2% Do Sort"
        case .exoDoDistance1: return "Exo +1% Do Distance"
        case .exoDoDistance2: return "Exo +2% Do Distance"
        case .overVita: return "Over Vitalité"
        case .leveling: return "Leveling XP"
        }
    }

    public var shortName: String {
        switch self {
        case .jetParfait: return "JP"
        case .exoPA: return "Exo PA"
        case .exoPM: return "Exo PM"
        case .exoDoSort1: return "+1% Sort"
        case .exoDoSort2: return "+2% Sort"
        case .exoDoDistance1: return "+1% Dist"
        case .exoDoDistance2: return "+2% Dist"
        case .overVita: return "Over Vita"
        case .leveling: return "Leveling"
        }
    }

    /// Pour les scénarios exo, retourne (characteristicId, targetValue).
    public var exoTarget: (characteristicId: Int, target: Int)? {
        switch self {
        case .exoPA: return (1, 1)
        case .exoPM: return (23, 1)
        case .exoDoSort1: return (123, 1)
        case .exoDoSort2: return (123, 2)
        case .exoDoDistance1: return (120, 1)
        case .exoDoDistance2: return (120, 2)
        default: return nil
        }
    }
}

/// Une étape de FM dans un preset multi-étapes (inspiré ExoFast).
/// MVP : seul le type "Cibles" est supporté. Les étapes Conditions / Conditions+puit
/// arriveront plus tard.
public struct PresetStep: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var targets: [StatKind: StatTarget]

    public init(id: UUID = UUID(), name: String, targets: [StatKind: StatTarget] = [:]) {
        self.id = id
        self.name = name
        self.targets = targets
    }
}

/// Preset utilisateur : pour cet item, quelles sont les cibles par stat.
///
/// Deux modes :
/// - **Single-step** (legacy) : `targets` non vide, `steps` vide → comportement actuel
/// - **Multi-step** (ExoFast-style) : `steps` non vide → DecisionEngine itère sur chaque étape
public struct StatsPreset: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var scenario: PresetScenario
    public var itemSpecId: Int?
    public var targets: [StatKind: StatTarget]
    /// Étapes séquentielles. Si non vide, prend le dessus sur `targets`.
    public var steps: [PresetStep]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        scenario: PresetScenario = .jetParfait,
        itemSpecId: Int? = nil,
        targets: [StatKind: StatTarget] = [:],
        steps: [PresetStep] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.scenario = scenario
        self.itemSpecId = itemSpecId
        self.targets = targets
        self.steps = steps
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Targets effectives à utiliser pour la décision, selon l'étape courante.
    /// Fallback sur `targets` legacy si pas de steps.
    public func effectiveTargets(at stepIndex: Int) -> [StatKind: StatTarget] {
        if steps.isEmpty { return targets }
        guard stepIndex >= 0, stepIndex < steps.count else { return [:] }
        return steps[stepIndex].targets
    }

    /// Nom de l'étape courante, ou vide si single-step.
    public func stepName(at index: Int) -> String? {
        guard index >= 0, index < steps.count else { return nil }
        return steps[index].name
    }

    public var isMultiStep: Bool { !steps.isEmpty }
    public var stepCount: Int { steps.count }

    /// Génère un preset selon le scénario choisi.
    public static func make(scenario: PresetScenario, for spec: ItemSpec) -> StatsPreset {
        switch scenario {
        case .jetParfait: return perfectJet(for: spec)
        case .exoPA: return exoPA(for: spec)
        case .exoPM: return exoPM(for: spec)
        case .exoDoSort1: return exoCustom(scenario: .exoDoSort1, characteristicId: 123, target: 1, label: "+1% Do Sort", for: spec)
        case .exoDoSort2: return exoCustom(scenario: .exoDoSort2, characteristicId: 123, target: 2, label: "+2% Do Sort", for: spec)
        case .exoDoDistance1: return exoCustom(scenario: .exoDoDistance1, characteristicId: 120, target: 1, label: "+1% Do Distance", for: spec)
        case .exoDoDistance2: return exoCustom(scenario: .exoDoDistance2, characteristicId: 120, target: 2, label: "+2% Do Distance", for: spec)
        case .overVita: return overVita(for: spec)
        case .leveling: return leveling(for: spec)
        }
    }

    /// Génère un preset exo générique pour une stat non native (Do Sort, Do Distance, etc.).
    /// Toutes les stats natives sont poussées au max (tampon sacrificiel) + cible exo en plus.
    public static func exoCustom(
        scenario: PresetScenario,
        characteristicId: Int,
        target: Int,
        label: String,
        for spec: ItemSpec
    ) -> StatsPreset {
        var targets: [StatKind: StatTarget] = [:]
        // Stats natives au max (tampon sacrificiel pour exo)
        for s in spec.stats {
            let value: Int
            var priority: Int
            if s.hasVariableRange {
                value = s.maxValue
                priority = 80
            } else if s.isOverable {
                value = s.maxValue + 1
                priority = 90
            } else {
                value = s.maxValue
                priority = 50
            }
            targets[s.kind] = StatTarget(
                target: value,
                minimum: s.minValue,
                priority: priority,
                enabled: true
            )
        }
        // Cible exo : caractéristique non native avec target = pourcentage souhaité
        let exoKind = StatKind(characteristicId: characteristicId)
        targets[exoKind] = StatTarget(
            target: target,
            minimum: nil,
            priority: 120,  // top priorité
            enabled: true
        )
        return StatsPreset(
            name: "Exo \(label) — \(spec.name)",
            scenario: scenario,
            itemSpecId: spec.id,
            targets: targets
        )
    }

    /// Leveling : on s'en fout du jet, on veut maximiser XP. Toutes les stats mageables
    /// ciblées au max avec priorité égale → stratégie pousse les grosses runes en boucle.
    public static func leveling(for spec: ItemSpec) -> StatsPreset {
        var targets: [StatKind: StatTarget] = [:]
        for s in spec.stats where s.isMageable {
            targets[s.kind] = StatTarget(
                target: s.maxValue,
                minimum: s.minValue,
                priority: 50,
                enabled: true
            )
        }
        return StatsPreset(
            name: "Leveling XP — \(spec.name)",
            scenario: .leveling,
            itemSpecId: spec.id,
            targets: targets
        )
    }

    /// Jet parfait : pour chaque stat de l'item, target + priorité adaptées.
    /// Priorités :
    /// - 120 : PA / PM (irremplaçables une fois perdus → top priorité)
    /// - 110 : Portée / Invocation (overable précieux)
    /// - 100 : stats avec variance (Vita, Fo, Sa, etc.)
    /// - 60  : stats fixes 1-1 (maintien seulement)
    public static func perfectJet(for spec: ItemSpec) -> StatsPreset {
        var targets: [StatKind: StatTarget] = [:]
        for s in spec.stats {
            let target: Int
            var priority: Int
            if s.hasVariableRange {
                target = s.maxValue
                priority = 100
            } else if s.isOverable {
                // Overable (PO/Invo) : target = max + 1 et priorité haute car ces stats
                // sont coûteuses à remettre si elles tombent.
                target = s.maxValue + 1
                priority = 110
            } else {
                target = s.maxValue
                priority = 60
            }
            // PA / PM : priorité absolue. Si elles tombent, on les remet en premier.
            if s.kind.characteristicId == 1 || s.kind.characteristicId == 23 {
                priority = 120
            }
            targets[s.kind] = StatTarget(
                target: target,
                minimum: s.minValue,
                priority: priority,
                enabled: true
            )
        }
        return StatsPreset(
            name: "Jet parfait — \(spec.name)",
            scenario: .jetParfait,
            itemSpecId: spec.id,
            targets: targets
        )
    }

    /// Génère un `ConfigPreset` avec des seuils Pa/Ra smart par stat,
    /// inspiré des règles ExoFast (ex: "Ra Age entre 45 et 50").
    ///
    /// Convention :
    /// - Pa from current ≥ 10 (early Pa pour économiser)
    /// - Ra entre (max - raBonus) et (max - 1) — fenêtre étroite pour éviter overs
    public static func smartConfig(for spec: ItemSpec, baseName: String = "Smart") -> ConfigPreset {
        var rules: [StatKind: ConfigRule] = [:]
        for s in spec.stats where s.hasVariableRange {
            guard let raBonus = RuneWeights.bonusPoints(for: s.kind, power: .ra) else { continue }
            let maxV = s.maxValue
            // Pa : activée dès qu'on a 10+ de stat (sous 10 → on pose des base)
            let paFrom = min(10, maxV / 6)
            // Ra : fenêtre étroite près du max, taille = max - raBonus à max - 1
            // Ex: Force max 60, raBonus 10 → Ra entre 50 et 59
            let raStart = max(paFrom + 1, maxV - raBonus)
            let raEnd = max(raStart + 1, maxV - 1)
            rules[s.kind] = ConfigRule(
                useBase: true,
                usePA: true,
                useRA: true,
                thresholdPA: 20,
                thresholdRA: 60,
                paValueThreshold: .from(paFrom),
                raValueThreshold: .between(raStart, raEnd)
            )
        }
        return ConfigPreset(
            name: "\(baseName) — \(spec.name)",
            rules: rules,
            defaultRule: .default,
            alternateExoPAPM: false
        )
    }

    /// Exo PA : on cherche à ajouter +1 PA exotique. Cible PA en priorité absolue,
    /// les autres stats à leur max avec priorité moyenne. La stratégie
    /// (ExoStrategy) gère la machine à états brise-spam-recover.
    public static func exoPA(for spec: ItemSpec) -> StatsPreset {
        var targets: [StatKind: StatTarget] = [:]
        for s in spec.stats where s.isMageable {
            targets[s.kind] = StatTarget(
                target: s.maxValue,
                minimum: s.minValue,
                priority: 50,
                enabled: true
            )
        }
        // PA target = 1 (exo), priorité max
        let paKind = StatKind(characteristicId: 1)
        targets[paKind] = StatTarget(target: 1, minimum: 1, priority: 100, enabled: true)
        return StatsPreset(
            name: "Exo PA — \(spec.name)",
            scenario: .exoPA,
            itemSpecId: spec.id,
            targets: targets
        )
    }

    /// Exo PM : idem mais sur PM (characteristicId 23).
    public static func exoPM(for spec: ItemSpec) -> StatsPreset {
        var targets: [StatKind: StatTarget] = [:]
        for s in spec.stats where s.isMageable {
            targets[s.kind] = StatTarget(
                target: s.maxValue,
                minimum: s.minValue,
                priority: 50,
                enabled: true
            )
        }
        let pmKind = StatKind(characteristicId: 23)
        targets[pmKind] = StatTarget(target: 1, minimum: 1, priority: 100, enabled: true)
        return StatsPreset(
            name: "Exo PM — \(spec.name)",
            scenario: .exoPM,
            itemSpecId: spec.id,
            targets: targets
        )
    }

    /// Over Vita : jet parfait + Vita poussée au-delà du max (cap 505 = 101 × densité 5).
    public static func overVita(for spec: ItemSpec) -> StatsPreset {
        var targets: [StatKind: StatTarget] = [:]
        for s in spec.stats where s.isMageable {
            let isVita = s.kind.characteristicId == 11
            targets[s.kind] = StatTarget(
                target: isVita ? s.maxValue + 50 : s.maxValue,
                minimum: s.minValue,
                priority: isVita ? 100 : 70,
                enabled: true
            )
        }
        return StatsPreset(
            name: "Over Vita — \(spec.name)",
            scenario: .overVita,
            itemSpecId: spec.id,
            targets: targets
        )
    }
}
