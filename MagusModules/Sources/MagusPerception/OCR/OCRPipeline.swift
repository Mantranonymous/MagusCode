import CoreGraphics
import Foundation
import MagusCommon
import MagusCore
import os

/// Pipeline OCR spéculatif : OCR de N régions en parallèle via TaskGroup.
/// Cible : < 200ms pour 6 régions sur M4.
public struct OCRPipeline: Sendable {

    private let engine: any OCREngine
    private let logger = MagusLogger.perception

    public init(engine: any OCREngine = VisionOCR()) {
        self.engine = engine
    }

    /// Lance l'OCR sur toutes les régions du profil en parallèle.
    /// Retourne un snapshot agrégé avec timings.
    public func recognize(
        frame: CaptureFrame,
        profile: ResolutionProfile,
        options: OCROptions = OCROptions()
    ) async -> RawOCRSnapshot {
        let start = Date()

        let results = await withTaskGroup(of: (RegionKind, RegionOCRResult?).self) { group in
            // Ne traite que les régions de type texte. Les régions visuelles
            // (ex: barre XP) sont gérées par un analyseur pixel séparé en P2/P3.
            for (kind, region) in profile.regions where kind.dataType == .text {
                group.addTask { [self] in
                    let result = await self.runOne(image: frame.image, region: region, options: options)
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
            let observations = try await engine.recognize(image: cropped, options: options)
            let elapsed = Date().timeIntervalSince(regionStart) * 1000
            let size = CGSize(width: cropped.width, height: cropped.height)
            return RegionOCRResult(
                observations: observations,
                elapsedMs: elapsed,
                engine: engine.identifier,
                imageSize: size
            )
        } catch {
            logger.error("OCR failed for region \(region.kind.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
