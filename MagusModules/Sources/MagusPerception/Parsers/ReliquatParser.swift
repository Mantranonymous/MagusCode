import Foundation
import MagusCore

/// Parse la zone Reliquat. Dofus 3 affiche le reliquat avec décimales :
/// "reliquat : 2.2", "reliquat : 27", "2,2", etc.
public struct ReliquatParser: Sendable {

    public init() {}

    public func parse(text: String) -> Reliquat? {
        let cleaned = OCRCorrection.applyDigitSubstitutions(text)
        guard let v = Self.lastDouble(in: cleaned), v >= 0 else { return nil }
        return Reliquat(density: v)
    }

    /// Récupère le dernier nombre décimal (avec `.` ou `,`) dans la string.
    static func lastDouble(in text: String) -> Double? {
        var groups: [String] = []
        var current = ""
        for c in text {
            if c.isNumber || c == "." || c == "," {
                current.append(c)
            } else if !current.isEmpty {
                groups.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            groups.append(current)
        }
        return groups.last
            .map { $0.replacingOccurrences(of: ",", with: ".") }
            .flatMap { Double($0) }
    }
}
