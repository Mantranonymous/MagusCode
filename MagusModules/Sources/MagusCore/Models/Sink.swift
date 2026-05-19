import Foundation

/// Pourcentage de Sink (favorabilité de la forge) sur l'item courant.
/// 0...100, plus haut = plus favorable.
public struct Sink: Hashable, Codable, Sendable {
    public let percent: Int

    public init(percent: Int) {
        self.percent = max(0, min(100, percent))
    }

    public var fraction: Double {
        Double(percent) / 100.0
    }
}
