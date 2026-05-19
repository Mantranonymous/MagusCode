import Foundation

/// Règle de sélection de rune pour une stat donnée.
public struct ConfigRule: Hashable, Codable, Sendable {
    public var useBase: Bool
    public var usePA: Bool
    public var useRA: Bool
    /// Distance restante (cible - courant) à partir de laquelle on commence à utiliser PA.
    public var thresholdPA: Int
    /// Distance restante à partir de laquelle on commence à utiliser RA.
    public var thresholdRA: Int
    /// Sécurité : valeur max qu'on accepte de pousser (au-delà = stop, évite over involontaire).
    public var maxCanHit: Int

    public init(
        useBase: Bool = true,
        usePA: Bool = true,
        useRA: Bool = true,
        thresholdPA: Int = 20,
        thresholdRA: Int = 60,
        maxCanHit: Int = 9999
    ) {
        self.useBase = useBase
        self.usePA = usePA
        self.useRA = useRA
        self.thresholdPA = thresholdPA
        self.thresholdRA = thresholdRA
        self.maxCanHit = maxCanHit
    }

    /// Règle par défaut suivant le guide FM (×20).
    public static let `default` = ConfigRule()
}

/// Preset de configuration : comment résoudre les runes par stat.
public struct ConfigPreset: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var rules: [StatKind: ConfigRule]
    /// Règle appliquée par défaut quand aucune règle spécifique n'existe pour la stat.
    public var defaultRule: ConfigRule
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        rules: [StatKind: ConfigRule] = [:],
        defaultRule: ConfigRule = .default,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.rules = rules
        self.defaultRule = defaultRule
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func rule(for kind: StatKind) -> ConfigRule {
        rules[kind] ?? defaultRule
    }

    /// Preset par défaut "Rapide" : utilise les 3 rangs avec règle ×20 classique.
    public static let bundledFast = ConfigPreset(
        name: "Rapide (règle ×20)",
        defaultRule: .default
    )

    /// Preset par défaut "Économe" : ne fait que des runes base + PA (jamais RA).
    public static let bundledEconomic = ConfigPreset(
        name: "Économe (sans RA)",
        defaultRule: ConfigRule(useBase: true, usePA: true, useRA: false, thresholdPA: 10)
    )
}

/// Bundle d'un preset stats + config, passé au DecisionEngine.
public struct PresetBundle: Sendable, Hashable {
    public let stats: StatsPreset
    public let config: ConfigPreset

    public init(stats: StatsPreset, config: ConfigPreset) {
        self.stats = stats
        self.config = config
    }
}
