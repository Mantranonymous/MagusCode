import CoreGraphics
import Foundation

/// Résultat d'une observation OCR : texte reconnu, position, confiance.
public struct OCRResult: Hashable, Sendable {
    public let text: String
    public let confidence: Double      // 0...1
    public let boundingBox: CGRect     // dans l'espace de l'image source

    public init(text: String, confidence: Double, boundingBox: CGRect) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

/// Ensemble des résultats OCR pour une région donnée.
public struct RegionOCRResult: Hashable, Sendable {
    public let observations: [OCRResult]
    public let elapsedMs: Double         // temps d'exécution OCR pour cette région
    public let engine: String            // identifiant du moteur ("vision", "vlm")
    public let imageSize: CGSize         // taille en pixels de l'image OCR'd (cropped) — pour convertir bbox → fraction → screen

    public init(observations: [OCRResult], elapsedMs: Double, engine: String, imageSize: CGSize = .zero) {
        self.observations = observations
        self.elapsedMs = elapsedMs
        self.engine = engine
        self.imageSize = imageSize
    }

    /// Concatène les textes dans l'ordre vertical (top-to-bottom).
    public var joinedText: String {
        observations
            .sorted { $0.boundingBox.minY < $1.boundingBox.minY }
            .map(\.text)
            .joined(separator: "\n")
    }

    public var averageConfidence: Double {
        guard !observations.isEmpty else { return 0 }
        return observations.map(\.confidence).reduce(0, +) / Double(observations.count)
    }
}
