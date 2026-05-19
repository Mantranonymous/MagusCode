import MagusCore
import CoreGraphics
import Foundation
import MagusCommon
import Vision
import os

/// Moteur OCR principal basé sur Apple Vision (VNRecognizeTextRequest).
/// Ultra rapide sur Apple Silicon (Neural Engine).
public struct VisionOCR: OCREngine {

    public let identifier = "vision"
    private let logger = MagusLogger.perception

    public init() {}

    public func recognize(image: CGImage, options: OCROptions) async throws -> [OCRResult] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCREngineError.recognitionFailed(underlying: error.localizedDescription))
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let imageHeight = CGFloat(image.height)
                let imageWidth = CGFloat(image.width)

                let results: [OCRResult] = observations.compactMap { observation in
                    guard let top = observation.topCandidates(1).first else { return nil }
                    // VNRecognizedTextObservation.boundingBox est en coords normalisées
                    // origine bottom-left, on convertit en top-left + pixels.
                    let bbox = observation.boundingBox
                    let bboxPixels = CGRect(
                        x: bbox.minX * imageWidth,
                        y: (1.0 - bbox.maxY) * imageHeight,
                        width: bbox.width * imageWidth,
                        height: bbox.height * imageHeight
                    )
                    return OCRResult(
                        text: top.string,
                        confidence: Double(top.confidence),
                        boundingBox: bboxPixels
                    )
                }
                continuation.resume(returning: results)
            }

            request.recognitionLevel = options.useAccurateRecognition ? .accurate : .fast
            request.recognitionLanguages = options.languages
            request.usesLanguageCorrection = true
            if !options.customWords.isEmpty {
                request.customWords = options.customWords
            }
            if let minHeight = options.minimumTextHeight {
                request.minimumTextHeight = minHeight
            }

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCREngineError.recognitionFailed(underlying: error.localizedDescription))
            }
        }
    }
}
