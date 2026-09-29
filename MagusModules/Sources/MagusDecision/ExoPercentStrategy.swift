import Foundation
import MagusCore

/// Stratégie d'exo en pourcentage (Do Sort, Do Distance, Do Mêlée, Do Arme).
///
/// **Source** : `bot_fm_exo_do_percent_logique.md` (20 mai 2026).
///
/// ## Mécanique
///
/// - **Poids rune** : 15 par 1%
/// - **Cap exo total** : 101 de poids
/// - **Over max théorique** : 6% (15×6=90 < 101)
/// - **Taux SC pur** : ~1% par tentative
/// - **2ᵉ % ne passe QU'EN SC** : SN consomme le puits sans poser le %
///
/// ## Machine à états en 3 phases
///
/// 1. **Phase 1 (drop puits)** : provoquer chute d'une stat lourde pour avoir
///    reliquat ≥ 30 (1%) ou ≥ 60 (2%). Magus ne provoque PAS le drop lui-même
///    au MVP — l'utilisateur reçoit une instruction explicite.
/// 2. **Phase 2 (max lignes)** : tant que reliquat ≥ 15 et lignes non max, on
///    pose des runes pour remplir le tampon anti-EC.
/// 3. **Phase 3 (spam exo)** : tant que reliquat ≥ 15, on spam la rune exo
///    via inventaire calibré. SC → posé.
///
/// ## Règles absolues hard-codées
///
/// 1. Stop si exo target déjà posé (target+ atteinte)
/// 2. Pour exo 2% : nécessite que 1% soit déjà sur l'item
/// 3. Stop si exo 1% saute pendant tentative 2%
/// 4. Cap PWRG total ≤ 101 (refuser sinon)
public struct ExoPercentStrategy: DecisionStrategy {

    public struct Variant: Sendable, Equatable {
        public let characteristicId: Int
        public let targetPercent: Int  // 1 ou 2
        public let displayName: String
        public let slotKind: RegionKind

        public static func doSort(percent: Int) -> Variant {
            Variant(
                characteristicId: 123,
                targetPercent: percent,
                displayName: "+\(percent)% Do Sort",
                slotKind: .runeSlotPaDoSort
            )
        }

        public static func doDistance(percent: Int) -> Variant {
            Variant(
                characteristicId: 120,
                targetPercent: percent,
                displayName: "+\(percent)% Do Distance",
                slotKind: .runeSlotPaDoDistance
            )
        }
    }

    public let variant: Variant
    public var name: String { "Exo \(variant.displayName)" }

    /// Poids d'une rune Do Per % (poids fixe = 15 par 1%, source Millenium).
    private let runeWeight: Double = 15.0
    /// Cap dur PWRG total Ankama.
    private let pwrgCap: Double = 101.0

    private let maging = MagingStrategy()

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

        let exoKind = StatKind(characteristicId: variant.characteristicId)
        let currentExo = item.stat(matching: exoKind)?.value ?? 0
        let goal = variant.targetPercent

        // === Règle absolue 1 : exo atteint → finished ===
        if currentExo >= goal {
            return .finished(explanation: "\(variant.displayName) à \(currentExo) → exo réussi ! ⚠ Ne plus poser de runes.")
        }

        // === Règle absolue 2 : pour le 2%, le 1% doit déjà être posé ===
        if goal == 2 && currentExo < 1 {
            return .blocked(reason: .noActionPossible("""
            Tentative d'exo +2% \(variant.displayName) impossible : \
            le +1% doit déjà être posé sur l'item (actuel: \(currentExo)%). \
            Lance d'abord le scénario +1% \(variant.displayName.replacingOccurrences(of: "+\(goal)% ", with: ""))
            """))
        }

        // === Règle absolue 4 : cap PWRG total ===
        let pwrgCurrent = totalWeight(of: item)
        if pwrgCurrent + runeWeight > pwrgCap {
            return .blocked(reason: .noActionPossible("""
            PWRG total (\(formatNumber(pwrgCurrent))) + rune (\(formatNumber(runeWeight))) \
            > cap \(formatNumber(pwrgCap)). \
            Provoque la chute d'une stat lourde (PA poids 100, PM 90, PO 51) \
            via spam de runes sur stats voisines au max pour libérer de la place.
            """))
        }

        let reliquat = snapshot.reliquat?.density ?? 0
        let reliquatMinForAttempt: Double = goal == 1 ? 15 : 15  // 15 = poids 1 rune
        let reliquatMinPhase1: Double = goal == 1 ? 30 : 60      // doc

        // === Phase 1 : Préparation du puits ===
        // Si reliquat insuffisant pour tenter (< 15) ou pour un cycle correct (< 30/60),
        // on demande à l'user de provoquer un drop. Magus pourrait l'automatiser mais MVP.
        if reliquat < reliquatMinForAttempt {
            return .blocked(reason: .noActionPossible("""
            Reliquat insuffisant (\(formatNumber(reliquat))/\(formatNumber(reliquatMinPhase1))). \
            **Phase 1 — Drop puits** : provoque la chute d'une stat lourde.
            • Idéal pour \(goal)% \(variant.displayName) : puits ~\(formatNumber(reliquatMinPhase1))+
            • Méthode : pose des runes lourdes sur tes stats AU MAX (Sa, CC, Do)
            • Quand une stat lourde chute (PA→100, PM→90, PO→51), puits se remplit
            • Une fois reliquat ≥ \(formatNumber(reliquatMinForAttempt)), relance la session
            """))
        }

        // === Phase 2 : Maximisation des lignes (tampon anti-EC) ===
        // Si on a du reliquat ET des lignes pas au max, on remplit le tampon AVANT
        // de tenter l'exo. Les lignes pleines absorbent les EC.
        if let lissageDecision = needsLissage(item: item, snapshot: snapshot, preset: preset, spec: spec, exoKind: exoKind) {
            return lissageDecision
        }

        // === Phase 3 : Spam de l'exo ===
        let exoRune = Rune(kind: exoKind, power: .pa)  // rune Pa Do Sort/Dist (poids 15)
        let snConsumesReliquatNote: String
        if goal == 1 {
            snConsumesReliquatNote = "SC ou SN posent le 1% (SN consomme du puits)"
        } else {
            snConsumesReliquatNote = "⚠ Seul SC pose le 2%, SN consomme inutilement le puits"
        }

        let cyclesEstimes: Int = goal == 1 ? Int(reliquat / runeWeight) : Int(reliquat / runeWeight)
        let explanation = """
        \(variant.displayName) — Phase 3 (spam). \
        Reliquat \(formatNumber(reliquat)), PWRG \(formatNumber(pwrgCurrent))/\(formatNumber(pwrgCap)). \
        Tentatives possibles ce cycle: \(cyclesEstimes). \(snConsumesReliquatNote).
        """

        return .applyRune(exoRune, on: exoKind, explanation: explanation)
    }

    // MARK: - Helpers

    /// Vérifie si on doit lisser les stats secondaires avant de tenter l'exo.
    /// Critère : il existe au moins une stat sous son target avec value ≥ 0.
    private func needsLissage(
        item: Item,
        snapshot: GameStateSnapshot,
        preset: PresetBundle,
        spec: ItemSpec,
        exoKind: StatKind
    ) -> Decision? {
        let unfinished = item.stats.contains { stat in
            if stat.kind == exoKind { return false }
            if stat.value < 0 { return false }
            guard let t = preset.stats.targets[stat.kind], t.enabled else { return false }
            return stat.value < t.target
        }
        guard unfinished else { return nil }
        // Délègue à MagingStrategy avec le snapshot complet (utilise reliquat/historique)
        return maging.decide(snapshot: snapshot, preset: preset, spec: spec)
    }

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
