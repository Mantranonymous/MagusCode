import CoreGraphics
import Foundation
import MagusCommon
import MagusCore
import os

/// Pipeline OCR spéculatif : OCR de N régions en parallèle via TaskGroup.
/// Cible : < 200ms pour 6 régions sur M4.
public struct OCRPipeline: Sendable {

    private let engine: any OCREngine
    private let fallback: (any OCREngine)?
    private let settings: AppSettingsSnapshot
    private let preprocessor: ImagePreprocessor
    private let customWords: [String]
    private let logger = MagusLogger.perception

    public init(
        engine: any OCREngine = VisionOCR(),
        fallback: (any OCREngine)? = VLMFallback.shared,
        settings: AppSettingsSnapshot = AppSettingsSnapshot(
            vlmFallbackEnabled: false,
            vlmConfidenceThreshold: 0.6,
            showClickMarker: true,
            ocrUpscaleFactor: 2.0,
            ocrBinarize: false
        ),
        preprocessor: ImagePreprocessor? = nil,
        customWords: [String] = []
    ) {
        self.engine = engine
        self.fallback = fallback
        self.settings = settings
        self.customWords = customWords
        if let p = preprocessor {
            self.preprocessor = p
        } else {
            self.preprocessor = ImagePreprocessor(settings: ImagePreprocessor.Settings(
                upscaleFactor: settings.ocrUpscaleFactor,
                binarize: settings.ocrBinarize,
                contrastBoost: settings.ocrBinarize  // si on binarise, on boost aussi
            ))
        }
    }

    /// Lance l'OCR sur toutes les régions du profil en parallèle.
    /// Retourne un snapshot agrégé avec timings.
    public func recognize(
        frame: CaptureFrame,
        profile: ResolutionProfile,
        options: OCROptions = OCROptions()
    ) async -> RawOCRSnapshot {
        let start = Date()
        // Injecte les customWords du pipeline si l'option n'en avait pas
        var effectiveOptions = options
        if effectiveOptions.customWords.isEmpty && !customWords.isEmpty {
            effectiveOptions.customWords = customWords
        }

        let results = await withTaskGroup(of: (RegionKind, RegionOCRResult?).self) { group in
            // Ne traite que les régions de type texte. Les régions visuelles
            // (ex: barre XP) sont gérées par un analyseur pixel séparé en P2/P3.
            for (kind, region) in profile.regions where kind.dataType == .text {
                group.addTask { [self] in
                    let result = await self.runOne(image: frame.image, region: region, options: effectiveOptions)
                    return (kind, result)
                }
            }

            var collected: [RegionKind: RegionOCRResult] = [:]
            for await (kind, result) in group {
                if let result = result {
                    collected[kind] = result
                }
            }
            return collected
        }

        let totalMs = Date().timeIntervalSince(start) * 1000
        logger.debug("OCR pipeline: \(results.count) regions in \(String(format: "%.1f", totalMs))ms")
        return RawOCRSnapshot(
            results: results,
            frameTimestamp: frame.timestamp,
            totalElapsedMs: totalMs
        )
    }

    private func runOne(image: CGImage, region: Region, options: OCROptions) async -> RegionOCRResult? {
        let regionStart = Date()
        do {
            let cropped = try RegionCropper.crop(image: image, region: region)
            // Preprocessing : upscale Lanczos + binarize/contrast si activé
            let processed = preprocessor.process(cropped)
            let observations = try await engine.recognize(image: processed, options: options)
            var finalObservations = observations
            var engineUsed = engine.identifier

            // VLM fallback : tente le VLM si activé ET confidence trop basse
            if settings.vlmFallbackEnabled,
               let fallback = fallback,
               averageConfidence(observations) < settings.vlmConfidenceThreshold {
                logger.debug("Low confidence on \(region.kind.rawValue, privacy: .public) → trying VLM fallback")
                do {
                    let vlmObs = try await fallback.recognize(image: processed, options: options)
                    if averageConfidence(vlmObs) > averageConfidence(observations) {
                        finalObservations = vlmObs
                        engineUsed = fallback.identifier
                    }
                } catch {
                    // VLM pas implémenté → silencieusement on garde Vision
                    logger.debug("VLM unavailable for \(region.kind.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }

            let elapsed = Date().timeIntervalSince(regionStart) * 1000
            // Important : on retourne la taille de l'image OCR-isée (processed, donc upscalée)
            // car les boundingBoxes des observations sont en pixels de cette image.
            let size = CGSize(width: processed.width, height: processed.height)
            return RegionOCRResult(
                observations: finalObservations,
                elapsedMs: elapsed,
                engine: engineUsed,
                imageSize: size
            )
        } catch {
            logger.error("OCR failed for region \(region.kind.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func averageConfidence(_ observations: [OCRResult]) -> Double {
        guard !observations.isEmpty else { return 0 }
        return observations.map(\.confidence).reduce(0, +) / Double(observations.count)
    }
}
