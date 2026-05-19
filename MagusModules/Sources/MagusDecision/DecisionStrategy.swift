import Foundation
import MagusCore

/// Contrat commun aux différentes stratégies (Maging classique, Exo, Leveling...).
public protocol DecisionStrategy: Sendable {
    var name: String { get }

    func decide(
        snapshot: GameStateSnapshot,
        preset: PresetBundle,
        spec: ItemSpec?
    ) -> Decision
}
