import Foundation
import MagusCore

/// Modèle de probabilité SC/SN/EC pour une pose de rune.
///
/// Porté depuis EasyFM `CalculResultat` (Configuration.csv + lignes 437-556).
/// Formule à 5 cas pondérés : niveau d'item, poids rune, état de la stat,
/// état global du PWRG (poids total de l'item), bonus over/exo.
///
/// **Ces probabilités sont une estimation** — Ankama n'a jamais publié la
/// vraie formule. Le modèle EasyFM est calibré empiriquement et reste
/// la meilleure approximation publique disponible.
public struct SuccessProbabilityModel: Sendable {

    public struct Probabilities: Sendable, Equatable {
        public let sc: Double  // 0-1
        public let sn: Double  // 0-1
        public let ec: Double  // 0-1

        public init(sc: Double, sn: Double, ec: Double) {
            self.sc = sc; self.sn = sn; self.ec = ec
        }

        public var summary: String {
            let pct = { (v: Double) in Int((v * 100).rounded()) }
            return "SC \(pct(sc))% · SN \(pct(sn))% · EC \(pct(ec))%"
        }
    }

    /// Inputs nécessaires au calcul.
    public struct Inputs: Sendable {
        public let rune: Rune
        public let statCurrentValue: Int
        public let statMin: Int
        public let statMax: Int
        public let itemLevel: Int
        /// Poids total actuel de l'item (somme des stats × leur poids unitaire).
        public let pwrgCurrent: Double
        /// Poids total max théorique (somme des stats au max × poids unitaire).
        public let pwrgMax: Double
        /// Poids actuel de la stat ciblée (= currentValue × unitWeight).
        public let pwrgCurrentStat: Double
        public let isExo: Bool
        public let isOver: Bool
        /// Somme des poids over + exo actuellement présents sur l'item.
        public let pwrgOverEtExo: Double

        public init(
            rune: Rune,
            statCurrentValue: Int,
            statMin: Int,
            statMax: Int,
            itemLevel: Int,
            pwrgCurrent: Double,
            pwrgMax: Double,
            pwrgCurrentStat: Double,
            isExo: Bool = false,
            isOver: Bool = false,
            pwrgOverEtExo: Double = 0
        ) {
            self.rune = rune
            self.statCurrentValue = statCurrentValue
            self.statMin = statMin
            self.statMax = statMax
            self.itemLevel = itemLevel
            self.pwrgCurrent = pwrgCurrent
            self.pwrgMax = pwrgMax
            self.pwrgCurrentStat = pwrgCurrentStat
            self.isExo = isExo
            self.isOver = isOver
            self.pwrgOverEtExo = pwrgOverEtExo
        }
    }

    public init() {}

    public func compute(_ inputs: Inputs) -> Probabilities {
        guard let runeWeight = RuneWeights.weight(of: inputs.rune),
              let runeBonus = RuneWeights.bonusPoints(for: inputs.rune.kind, power: inputs.rune.power) else {
            return Probabilities(sc: 0, sn: 0, ec: 1)
        }

        // Cap dur 1 : si pose impossible (over absolu), EC=100%.
        if inputs.pwrgOverEtExo + runeWeight > 100.0 {
            return Probabilities(sc: 0, sn: 0, ec: 1)
        }

        // Cap dur 2 : exo lourd (rune > 50 de poids) → ~1% SC.
        // Concerne Ga Pa (100), Ga Pm (90), Po (51).
        if inputs.isExo && runeWeight > 50.0 {
            return Probabilities(sc: 0.01, sn: 0, ec: 0.99)
        }

        // EtatPWR ∈ [0, 1+] : où en est la stat dans sa range ?
        // 0 = au min, 1 = au max après la pose.
        let span = max(1, inputs.statMax - inputs.statMin)
        let projected = inputs.statCurrentValue + runeBonus
        let etatPWR = Double(projected - inputs.statMin) / Double(span)

        // EtatPWRG ∈ [0, 1+] : où en est le poids total de l'item ?
        let pwrgDenom = max(1.0, inputs.pwrgMax - inputs.pwrgCurrentStat)
        let etatPWRG = inputs.pwrgCurrent / pwrgDenom

        // Coefficients de pondération (EasyFM).
        let coefLvl = max(0.4, 1.0 - (Double(inputs.itemLevel) / 200.0) / 6.0)
        let coefRune = max(0.4, 1.0 - runeWeight / 200.0)
        let coefOvermax: Double = inputs.isOver
            ? max(0.05, (1.0 - (inputs.pwrgOverEtExo + runeWeight) / 100.0) / 2.0)
            : 1.0

        // Formule de base : SC entre 0 et 80, pondéré par les 3 coefs.
        let rawSC = 80.0 - (20.0 * etatPWR + 30.0 * etatPWRG)
        var sc = (rawSC * coefLvl * coefRune * coefOvermax) / 100.0
        sc = max(0, min(1, sc))

        // SN nominale 50%, perturbée par les coefs aussi.
        var sn = 0.50
        if inputs.isOver || inputs.isExo {
            // Mode dégradé : SN beaucoup moindre.
            let rawSN = 50.0 - 16.0 * (etatPWR + etatPWRG) / 2.0
            sn = max(0, min(1, rawSN / 100.0))
        }

        // EC = reste.
        var ec = max(0, 1.0 - sc - sn)

        // Bornes empiriques (hors exo/over) : SC ≥ 15%, EC ≤ 35%.
        if !inputs.isExo && !inputs.isOver {
            if sc < 0.15 {
                let delta = 0.15 - sc
                sc = 0.15
                ec = max(0, ec - delta)
            }
            if ec > 0.35 {
                let delta = ec - 0.35
                ec = 0.35
                sn += delta
            }
        }

        // Renormalisation finale.
        let total = sc + sn + ec
        if total > 0 {
            sc /= total
            sn /= total
            ec /= total
        }

        return Probabilities(sc: sc, sn: sn, ec: ec)
    }
}
