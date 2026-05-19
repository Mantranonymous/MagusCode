import Foundation

/// Snapshot brut OCR : pour chaque RegionKind calibrée, le résultat OCR.
/// Type "boundary" partagé entre MagusPerception (producteur) et
/// MagusExecution/MagusDecision (consommateurs).
public struct RawOCRSnapshot: Sendable {
    public let results: [RegionKind: RegionOCRResult]
    public let frameTimestamp: Date
    public let totalElapsedMs: Double

    public init(
        results: [RegionKind: RegionOCRResult],
        frameTimestamp: Date,
        totalElapsedMs: Double
    ) {
        self.results = results
        self.frameTimestamp = frameTimestamp
        self.totalElapsedMs = totalElapsedMs
    }
}
