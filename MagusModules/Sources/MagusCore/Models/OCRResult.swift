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

    /// Regroupe les observations par "ligne visuelle" (Y proches), trie chaque
    /// groupe par X croissant, joint avec espaces. Indispensable pour parser une
    /// table dont Vision a séparé les colonnes en observations distinctes.
    ///
    /// Sans ça, "21 30 30 Agilité +3 115 ..." devient 7 lignes d'1 token chacune
    /// → StatLineParser échoue → SpecGuidedExtractor prend un mauvais nombre.
    public var rowGroupedText: String {
        guard !observations.isEmpty else { return "" }
        // Tolérance Y : 40% de la hauteur moyenne des bbox. Vision retourne souvent
        // des bbox de même hauteur pour une même ligne, mais avec un léger jitter.
        let avgHeight = observations.map(\.boundingBox.height).reduce(0, +) / Double(observations.count)
        let yTolerance = max(0.005, avgHeight * 0.4)

        // Trie par Y croissant pour grouper
        let sorted = observations.sorted { $0.boundingBox.minY < $1.boundingBox.minY }

        var rows: [[OCRResult]] = []
        for obs in sorted {
            let y = obs.boundingBox.midY
            if var last = rows.last, let ref = last.first?.boundingBox.midY, abs(y - ref) <= yTolerance {
                last.append(obs)
                rows[rows.count - 1] = last
            } else {
                rows.append([obs])
            }
        }

        return rows.map { row in
            row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
               .map(\.text)
               .joined(separator: " ")
        }.joined(separator: "\n")
    }

    public var averageConfidence: Double {
        guard !observations.isEmpty else { return 0 }
        return observations.map(\.confidence).reduce(0, +) / Double(observations.count)
    }
}
