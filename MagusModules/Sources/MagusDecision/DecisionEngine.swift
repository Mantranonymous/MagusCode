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

    public init() {
        self.maging = MagingStrategy()
        self.exoPA = ExoStrategy(variant: .exoPA)
        self.exoPM = ExoStrategy(variant: .exoPM)
    }

    public func decide(
        mode: SessionMode = .maging,
        snapshot: GameStateSnapshot,
        preset: PresetBundle,
        spec: ItemSpec?
    ) -> Decision {
        // Le scénario du preset dispatch vers la bonne stratégie
        switch preset.stats.scenario {
        case .jetParfait, .overVita:
            return maging.decide(snapshot: snapshot, preset: preset, spec: spec)
        case .exoPA:
            return exoPA.decide(snapshot: snapshot, preset: preset, spec: spec)
        case .exoPM:
            return exoPM.decide(snapshot: snapshot, preset: preset, spec: spec)
        }
    }
}
