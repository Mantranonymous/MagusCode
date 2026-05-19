import Foundation

/// Identifie une caractéristique (stat) de Dofus de façon générique.
/// Le `characteristicId` correspond à l'ID DofusDB (table ref_characteristics).
/// Le nom d'affichage est résolu dynamiquement via la table de référence.
public struct StatKind: Hashable, Codable, Sendable {
    public let characteristicId: Int

    public init(characteristicId: Int) {
        self.characteristicId = characteristicId
    }
}

extension StatKind: CustomStringConvertible {
    public var description: String { "StatKind(#\(characteristicId))" }
}
