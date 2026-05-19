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
    case jetParfait     // toutes les stats au max théorique
    case exoPA          // tente d'ajouter un PA exotique
    case exoPM          // tente d'ajouter un PM exotique
    case overVita       // jet parfait + over Vitalité
    case leveling       // maximise XP métier — clique des grosses runes en boucle

    public var displayName: String {
        switch self {
        case .jetParfait: return "Jet parfait"
        case .exoPA: return "Exo PA"
        case .exoPM: return "Exo PM"
        case .overVita: return "Over Vitalité"
        case .leveling: return "Leveling XP"
        }
    }

    public var shortName: String {
        switch self {
        case .jetParfait: return "JP"
        case .exoPA: return "Exo PA"
        case .exoPM: return "Exo PM"
        case .overVita: return "Over Vita"
        case .leveling: return "Leveling"
        }
    }
}

/// Preset utilisateur : pour cet item, quelles sont les cibles par stat.
public struct StatsPreset: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var scenario: PresetScenario
    public var itemSpecId: Int?
    public var targets: [StatKind: StatTarget]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        scenario: PresetScenario = .jetParfait,
        itemSpecId: Int? = nil,
        targets: [StatKind: StatTarget] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.scenario = scenario
        self.itemSpecId = itemSpecId
        self.targets = targets
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Génère un preset selon le scénario choisi.
    public static func make(scenario: PresetScenario, for spec: ItemSpec) -> StatsPreset {
        switch scenario {
        case .jetParfait: return perfectJet(for: spec)
        case .exoPA: return exoPA(for: spec)
        case .exoPM: return exoPM(for: spec)
        case .overVita: return overVita(for: spec)
        case .leveling: return leveling(for: spec)
        }
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

    /// Jet parfait : chaque stat mageable a target = maxValue, priorité 100.
    public static func perfectJet(for spec: ItemSpec) -> StatsPreset {
        var targets: [StatKind: StatTarget] = [:]
        for s in spec.stats where s.isMageable {
            targets[s.kind] = StatTarget(
                target: s.maxValue,
                minimum: s.minValue,
                priority: 100,
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
