import Foundation
import MagusCore

/// Mode de session actif (Maging / Exo / Leveling).
public enum SessionMode: String, Codable, CaseIterable, Sendable {
    case maging
    case exo
    case leveling
}

/// Façade principale du moteur de décision. Choisit la stratégie selon le scénario du preset.
public struct DecisionEngine: Sendable {
    private let maging: MagingStrategy
    private let exoPA: ExoStrategy
    private let exoPM: ExoStrategy
    private let leveling: LevelingStrategy

    public init() {
        self.maging = MagingStrategy()
        self.exoPA = ExoStrategy(variant: .exoPA)
        self.exoPM = ExoStrategy(variant: .exoPM)
        self.leveling = LevelingStrategy()
    }

    public func decide(
        mode: SessionMode = .maging,
        snapshot: GameStateSnapshot,
        preset: PresetBundle,
        spec: ItemSpec?
    ) -> Decision {
        switch preset.stats.scenario {
        case .jetParfait, .overVita:
            return maging.decide(snapshot: snapshot, preset: preset, spec: spec)
        case .exoPA:
            return exoPA.decide(snapshot: snapshot, preset: preset, spec: spec)
        case .exoPM:
            return exoPM.decide(snapshot: snapshot, preset: preset, spec: spec)
        case .leveling:
            return leveling.decide(snapshot: snapshot, preset: preset, spec: spec)
        }
    }
}
