import Foundation

/// Seuil d'activation d'un rang de rune en fonction de la VALEUR COURANTE d'une stat.
/// Inspiré d'ExoFast : on peut dire "Ra Age entre 45 et 50" ou "Pa Fo à partir de 10".
public enum RuneThreshold: Hashable, Codable, Sendable {
    /// Toujours utiliser ce rang (pas de contrainte de valeur).
    case always
    /// Ne jamais utiliser ce rang (rang désactivé).
    case never
    /// À partir d'une valeur (opérateur `→`). Ex: from(10) → utilise si stat ≥ 10.
    case from(Int)
    /// Jusqu'à une valeur (opérateur `←`). Ex: until(50) → utilise si stat ≤ 50.
    case until(Int)
    /// Entre deux valeurs (inclusif). Ex: between(45, 50) → utilise si 45 ≤ stat ≤ 50.
    case between(Int, Int)

    /// Évalue le seuil pour une valeur courante de stat.
    public func allows(currentValue: Int) -> Bool {
        switch self {
        case .always: return true
        case .never: return false
        case .from(let v): return currentValue >= v
        case .until(let v): return currentValue <= v
        case .between(let lo, let hi): return currentValue >= lo && currentValue <= hi
        }
    }

    /// Représentation textuelle compacte pour l'UI.
    public var displayString: String {
        switch self {
        case .always: return "toujours"
        case .never: return "jamais"
        case .from(let v): return "→ \(v)"
        case .until(let v): return "← \(v)"
        case .between(let lo, let hi): return "\(lo)–\(hi)"
        }
    }
}

/// Règle de sélection de rune pour une stat donnée.
public struct ConfigRule: Hashable, Codable, Sendable {
    public var useBase: Bool
    public var usePA: Bool
    public var useRA: Bool
    /// Distance restante (cible - courant) à partir de laquelle on commence à utiliser PA.
    /// **Legacy** : fallback si `paValueThreshold == .always`.
    public var thresholdPA: Int
    /// Distance restante à partir de laquelle on commence à utiliser RA.
    public var thresholdRA: Int
    /// Sécurité : valeur max qu'on accepte de pousser (au-delà = stop, évite over involontaire).
    public var maxCanHit: Int
    /// Seuil Pa basé sur la VALEUR COURANTE de la stat (style ExoFast).
    /// Si `.always`, on retombe sur la règle classique (distance ≥ thresholdPA).
    public var paValueThreshold: RuneThreshold
    /// Seuil Ra. Idem que paValueThreshold.
    public var raValueThreshold: RuneThreshold

    public init(
        useBase: Bool = true,
        usePA: Bool = true,
        useRA: Bool = true,
        thresholdPA: Int = 20,
        thresholdRA: Int = 60,
        maxCanHit: Int = 9999,
        paValueThreshold: RuneThreshold = .always,
        raValueThreshold: RuneThreshold = .always
    ) {
        self.useBase = useBase
        self.usePA = usePA
        self.useRA = useRA
        self.thresholdPA = thresholdPA
        self.thresholdRA = thresholdRA
        self.maxCanHit = maxCanHit
        self.paValueThreshold = paValueThreshold
        self.raValueThreshold = raValueThreshold
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
    /// Si vrai et qu'on est en scenario exo, alterne PA/PM à chaque combine landed.
    /// Source : ExoFast (alterne automatiquement PA et PM pour doubler les chances).
    public var alternateExoPAPM: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        rules: [StatKind: ConfigRule] = [:],
        defaultRule: ConfigRule = .default,
        alternateExoPAPM: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.rules = rules
        self.defaultRule = defaultRule
        self.alternateExoPAPM = alternateExoPAPM
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
    /// Runes détectées comme épuisées (en inventaire) pendant cette session.
    /// Les stratégies doivent les éviter pour ne pas tourner à vide.
    public let depletedRunes: Set<Rune>

    public init(stats: StatsPreset, config: ConfigPreset, depletedRunes: Set<Rune> = []) {
        self.stats = stats
        self.config = config
        self.depletedRunes = depletedRunes
    }
}
