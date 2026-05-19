import Foundation
import MagusCore

/// Parse la zone Sink (typiquement "87 %", "Sink 87%", "87%").
public struct SinkParser: Sendable {

    public init() {}

    public func parse(text: String) -> Sink? {
        let cleaned = OCRCorrection.applyDigitSubstitutions(text)
        // Chercher un nombre suivi de %
        guard let pctIdx = cleaned.firstIndex(of: "%") else {
            // Pas de %, on tente quand même de récupérer le premier int dans la range 0-100
            if let n = OCRCorrection.firstInt(in: cleaned), (0...100).contains(n) {
                return Sink(percent: n)
            }
            return nil
        }
        let prefix = String(cleaned[..<pctIdx])
        // Le nombre est en fin de prefix (ex: "Sink 87"). On prend le dernier groupe.
        guard let v = OCRCorrection.lastInt(in: prefix), (0...100).contains(v) else {
            return nil
        }
        return Sink(percent: v)
    }
}
