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
        let scenario = preset.stats.scenario
        switch scenario {
        case .jetParfait, .overVita:
            return maging.decide(snapshot: snapshot, preset: preset, spec: spec)
        case .exoPA:
            return exoPA.decide(snapshot: snapshot, preset: preset, spec: spec)
        case .exoPM:
            return exoPM.decide(snapshot: snapshot, preset: preset, spec: spec)
        case .leveling:
            return leveling.decide(snapshot: snapshot, preset: preset, spec: spec)
        case .exoDoSort1:
            return ExoPercentStrategy(variant: .doSort(percent: 1)).decide(snapshot: snapshot, preset: preset, spec: spec)
        case .exoDoSort2:
            return ExoPercentStrategy(variant: .doSort(percent: 2)).decide(snapshot: snapshot, preset: preset, spec: spec)
        case .exoDoDistance1:
            return ExoPercentStrategy(variant: .doDistance(percent: 1)).decide(snapshot: snapshot, preset: preset, spec: spec)
        case .exoDoDistance2:
            return ExoPercentStrategy(variant: .doDistance(percent: 2)).decide(snapshot: snapshot, preset: preset, spec: spec)
        }
    }
}
