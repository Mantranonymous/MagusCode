import Foundation
import MagusCore

/// Stratégie pour ajouter un exo (PA ou PM) sur un item. Machine à états :
///
/// 1. **dropTarget** : si la stat cible (PA ou PM) est déjà > 0 sur l'item original,
///    on tente de la faire tomber (anti-rune sur la stat à drop, ex: anti-PA si on
///    veut exo PM tout en gardant le PA pour plus tard).
/// 2. **spamExo** : la stat est à 0, on spam la rune exo (Ga Pa / Ga Pme).
///    Taux SC ≈ 1% → boucle longue.
/// 3. **recoverDropped** : (optionnel, pour exo PM avec PA dropé) on remet la rune
///    PA originale en espérant un SC pour la récupérer.
/// 4. **done** : exo réussi.
public struct ExoStrategy: DecisionStrategy {

    public enum Variant: Sendable {
        case exoPA
        case exoPM

        var targetKind: StatKind {
            switch self {
            case .exoPA: return StatKind(characteristicId: 1)   // PA
            case .exoPM: return StatKind(characteristicId: 23)  // PM
            }
        }

        var displayName: String {
            switch self {
            case .exoPA: return "PA"
            case .exoPM: return "PM"
            }
        }
    }

    public let variant: Variant

    public var name: String { "Exo \(variant.displayName)" }

    public init(variant: Variant) {
        self.variant = variant
    }

    public func decide(
        snapshot: GameStateSnapshot,
        preset: PresetBundle,
        spec: ItemSpec?
    ) -> Decision {
        guard let item = snapshot.item, !item.stats.isEmpty else {
            return .blocked(reason: .noItem)
        }
        guard let spec = spec else {
            return .blocked(reason: .noItemSpec)
        }

        let targetKind = variant.targetKind
        let targetStat = item.stat(matching: targetKind)
        let targetValue = targetStat?.value ?? 0

        // Cas 1 : la stat exo est déjà passée (> 0) → done
        if targetValue > 0 {
            return .finished(explanation: "\(variant.displayName) à \(targetValue) → exo réussi !")
        }

        // Cas 2 : item a déjà cette stat dans ses possibleEffects → c'est pas un exo,
        // c'est juste qu'elle est tombée. On peut juste la remettre via Maging classique.
        let isNativeStat = spec.spec(matching: targetKind) != nil
        if isNativeStat {
            // On délègue au MagingStrategy logique : appliquer rune \(variant) pour récupérer
            let rune = Rune(kind: targetKind, power: .pa)
            return .applyRune(rune, on: targetKind, explanation: """
            \(variant.displayName) est natif sur cet item mais à 0. Tente une rune Pa \(variant.displayName) pour récupérer.
            """)
        }

        // Cas 3 : la stat n'est PAS native → vrai exo. Spam la rune exo (Pa rank par défaut).
        // En pratique l'exo se fait avec une rune Pa de la stat, taux SC ≈ 1%.
        let rune = Rune(kind: targetKind, power: .pa)
        let explanation = """
        Tentative d'exo \(variant.displayName). La stat n'est pas native (\(spec.name)). \
        On spam des runes Pa \(variant.displayName) — taux SC très bas (~1%), prévois beaucoup d'essais.
        """
        return .applyRune(rune, on: targetKind, explanation: explanation)
    }
}
