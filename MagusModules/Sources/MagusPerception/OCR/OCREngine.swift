import CoreGraphics
import Foundation

/// Options communes aux moteurs OCR.
public struct OCROptions: Sendable {
    public var languages: [String]
    public var customWords: [String]
    public var useAccurateRecognition: Bool
    public var minimumTextHeight: Float?    // fraction de la hauteur de l'image, ex: 0.02 = 2%

    public init(
        languages: [String] = ["fr-FR", "en-US"],
        customWords: [String] = [],
        useAccurateRecognition: Bool = true,
        minimumTextHeight: Float? = nil
    ) {
        self.languages = languages
        self.customWords = customWords
        self.useAccurateRecognition = useAccurateRecognition
        self.minimumTextHeight = minimumTextHeight
    }
}

public enum OCREngineError: Error, Sendable {
    case imageInvalid
    case recognitionFailed(underlying: String)
    case notImplemented
}

/// Protocole commun aux moteurs OCR (Vision, VLM).
public protocol OCREngine: Sendable {
    var identifier: String { get }
    func recognize(image: CGImage, options: OCROptions) async throws -> [OCRResult]
}
