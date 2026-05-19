import CoreGraphics
import Foundation

/// Rectangle exprimé en coordonnées relatives (0...1) à un parent.
/// L'origine (0,0) est en haut-gauche, conforme aux conventions de capture d'écran.
public struct NormalizedRect: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Construit un NormalizedRect depuis un CGRect absolu et une taille de parent.
    public init(absolute rect: CGRect, in parent: CGSize) {
        guard parent.width > 0, parent.height > 0 else {
            self.init(x: 0, y: 0, width: 0, height: 0)
            return
        }
        self.init(
            x: Double(rect.origin.x) / Double(parent.width),
            y: Double(rect.origin.y) / Double(parent.height),
            width: Double(rect.width) / Double(parent.width),
            height: Double(rect.height) / Double(parent.height)
        )
    }

    /// Convertit en CGRect absolu étant donné une taille de parent.
    public func absolute(in parent: CGSize) -> CGRect {
        CGRect(
            x: x * Double(parent.width),
            y: y * Double(parent.height),
            width: width * Double(parent.width),
            height: height * Double(parent.height)
        )
    }

    public var isValid: Bool {
        x >= 0 && y >= 0 && width > 0 && height > 0
            && x + width <= 1.0 && y + height <= 1.0
    }
}
