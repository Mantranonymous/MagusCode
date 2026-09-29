import Foundation
import MagusCore

/// Stratégie d'exo (PA / PM) V3 — méthode "lissage + tampon de stats sacrificielles".
///
/// **Principe correct** (validé par les pros FM Dofus) :
/// Pour un exo PA/PM sur item **sans PA/PM natif**, il ne faut PAS briser l'item à 0
/// puis tenter l'exo — sinon dès la première EC sur une rune de remontée, l'exo
/// dégage (il n'y a pas d'autre stat de poids ≥ pour absorber la chute).
///
/// La vraie méthode :
/// 1. **Lissage** : pousser TOUTES les stats au max (y compris les "sacrificielles"
///    comme prospection, résistances fixes, esquives, tacles, retraits)
/// 2. **Spam** : marteler Ga PA/PM via l'inventaire dans cet état "plein"
/// 3. **Absorption** : quand un EC tombe pendant le spam, les pertes sont absorbées
///    par les stats sacrificielles (au max → cible facile) avant de toucher l'exo
/// 4. **Recovery** : si une stat HIGH PRIORITY tombe (PA natif, CC, Do), MagingStrategy
///    la remet en priorité absolue avant de re-spam l'exo
///
/// Machine à états :
/// - `alreadyDone` : `targetStat.value > 0` → finished
/// - `nativeFell` : la stat exo est native mais à 0 → délègue MagingStrategy
/// - `needsLissage` : une stat est sous son max → délègue MagingStrategy
/// - `spamExo` : tout est lissé → spam Ga PA/PM
public struct ExoStrategy: DecisionStrategy {

    public enum Variant: Sendable, Equatable {
        case exoPA
        case exoPM
        /// Exo générique sur une stat non native (Do Sort, Do Distance, etc.).
        /// `target` = pourcentage à atteindre (1 ou 2 typiquement).
        case custom(characteristicId: Int, target: Int, label: String)

        var targetKind: StatKind {
            switch self {
            case .exoPA: return StatKind(characteristicId: 1)
            case .exoPM: return StatKind(characteristicId: 23)
            case .custom(let cid, _, _): return StatKind(characteristicId: cid)
            }
        }

        var targetValue: Int {
            switch self {
            case .exoPA, .exoPM: return 1
            case .custom(_, let t, _): return t
            }
        }

        var displayName: String {
            switch self {
            case .exoPA: return "PA"
            case .exoPM: return "PM"
            case .custom(_, _, let label): return label
            }
        }
    }

    public let variant: Variant
    public var name: String { "Exo \(variant.displayName)" }

    private let maging = MagingStrategy()
    private let probaModel = SuccessProbabilityModel()

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
        let currentValue = item.stat(matching: targetKind)?.value ?? 0
        let goal = variant.targetValue

        // Cas 1 : exo atteint (>= cible) → finished
        if currentValue >= goal {
            return .finished(explanation: "\(variant.displayName) à \(currentValue) → exo réussi !")
        }

        // Cas 2 : la stat exo est NATIVE sur l'item mais elle est tombée à 0 → maging classique
        // pour la remettre. La rune normale fait le job (pas un vrai exo).
        if spec.spec(matching: targetKind) != nil {
            return maging.decide(snapshot: snapshot, preset: preset, spec: spec)
        }

        // Cas 3 : on est en vrai exo. Vérifier si le lissage est complet.
        // **CHANGEMENT MAJEUR vs V2** : on n'inspecte plus le PWRG total (faux).
        // L'approche pro = item PLEIN au max sur toutes les lignes, sacrificielles incluses.
        if let lissageDecision = needsLissage(item: item, snapshot: snapshot, preset: preset, spec: spec) {
            return lissageDecision
        }

        // Cas 4 : tout est lissé → on spam l'exo.
        let exoRune = Rune(kind: targetKind, power: .base)
        guard let runeWeight = RuneWeights.weight(of: exoRune) else {
            return .blocked(reason: .noActionPossible("Rune Ga \(variant.displayName) introuvable"))
        }
        let pwrgCurrent = totalWeight(of: item)

        let probas = probaModel.compute(.init(
            rune: exoRune,
            statCurrentValue: 0,
            statMin: 0,
            statMax: 1,
            itemLevel: spec.level,
            pwrgCurrent: pwrgCurrent,
            pwrgMax: 100,
            pwrgCurrentStat: 0,
            isExo: true,
            isOver: false,
            pwrgOverEtExo: pwrgCurrent
        ))

        let explanation = """
        Exo \(variant.displayName) — spam Ga \(variant.displayName) dans l'inventaire. \
        Item lissé : PWRG \(formatNumber(pwrgCurrent)) (tampons sacrificiels actifs). \
        Poids rune: \(formatNumber(runeWeight)). \(probas.summary). \
        Budget moyen ~100 runes (taux SC ~1%).
        """

        return .applyRune(exoRune, on: targetKind, explanation: explanation)
    }

    // MARK: - Lissage (déclenche maging si une stat n'est pas au max)

    /// Vérifie que toutes les stats utiles (y compris sacrificielles) sont au max.
    /// Une stat est considérée "à monter" si :
    /// - elle est dans le preset avec target > value courante
    /// - ce n'est pas la stat exo elle-même
    /// - sa valeur courante n'est pas négative (les malus ne se remontent pas)
    private func needsLissage(
        item: Item,
        snapshot: GameStateSnapshot,
        preset: PresetBundle,
        spec: ItemSpec
    ) -> Decision? {
        // Sont "à lisser" toutes les stats du preset dont la valeur < target ET ≥ 0
        let unfinished = item.stats.contains { stat in
            if stat.kind == variant.targetKind { return false }
            if stat.value < 0 { return false }
            guard let t = preset.stats.targets[stat.kind], t.enabled else { return false }
            return stat.value < t.target
        }
        guard unfinished else { return nil }
        // Délègue à MagingStrategy avec le vrai snapshot (pas un fake) pour qu'il puisse
        // utiliser l'historique, le reliquat, etc.
        return maging.decide(snapshot: snapshot, preset: preset, spec: spec)
    }

    // MARK: - Helpers

    /// Poids total de l'item = Σ(stat.value × poids_unitaire) pour les stats positives.
    private func totalWeight(of item: Item) -> Double {
        item.stats.reduce(0) { sum, stat in
            guard stat.value > 0 else { return sum }
            return sum + Double(stat.value) * RuneWeights.unitWeight(of: stat.kind)
        }
    }

    private func formatNumber(_ d: Double) -> String {
        d.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", d)
            : String(format: "%.1f", d)
    }
}
