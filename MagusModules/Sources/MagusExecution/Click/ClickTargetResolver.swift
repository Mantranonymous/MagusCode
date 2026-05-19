import CoreGraphics
import Foundation
import MagusCore

/// Résout la position (en coords d'écran) où cliquer pour appliquer une rune
/// à une stat donnée.
///
/// **Stratégie v2** :
/// - Row Y : extraite depuis les bbox OCR de la stats region (matching nom stat).
///   Fallback arithmétique si pas trouvée.
/// - Col X : utilise les régions calibrées `.statsPaColumn` et `.statsRaColumn`
///   si dispo, sinon fractions empiriques.
public struct ClickTargetResolver: Sendable {

    public struct ColumnFractions: Sendable {
        public let modif: Double
        public let pa: Double
        public let ra: Double

        public init(modif: Double = 0.62, pa: Double = 0.78, ra: Double = 0.92) {
            self.modif = modif
            self.pa = pa
            self.ra = ra
        }

        public static let `default` = ColumnFractions()
    }

    private let columns: ColumnFractions

    public init(columns: ColumnFractions = .default) {
        self.columns = columns
    }

    /// Calcule la position écran (Quartz top-left) à cliquer.
    public func cellPosition(
        for kind: StatKind,
        rank: Rune.Power,
        spec: ItemSpec,
        statsRegionBounds: NormalizedRect,
        baseColumnBounds: NormalizedRect?,
        paColumnBounds: NormalizedRect?,
        raColumnBounds: NormalizedRect?,
        ocrSnapshot: RawOCRSnapshot?,
        statsDisplayName: String?,
        dofusBounds: CGRect
    ) -> CGPoint? {
        guard let index = spec.stats.firstIndex(where: { $0.kind == kind }) else { return nil }
        let rowCount = spec.stats.count
        guard rowCount > 0 else { return nil }

        // === Row Y ===
        // Préfère OCR si on trouve le nom de la stat dans les observations
        let statsRegionScreen = regionToScreen(bounds: statsRegionBounds, dofusBounds: dofusBounds)
        let rowY: CGFloat
        if let name = statsDisplayName,
           let ocrY = findRowYFromOCR(
               statName: name,
               ocrSnapshot: ocrSnapshot,
               statsRegionScreen: statsRegionScreen,
               statsRegionBounds: statsRegionBounds
           ) {
            rowY = ocrY
        } else {
            // Fallback arithmétique
            let rowFraction = (Double(index) + 0.5) / Double(rowCount)
            rowY = statsRegionScreen.minY + statsRegionScreen.height * CGFloat(rowFraction)
        }

        // === Col X ===
        let screenX: CGFloat
        switch rank {
        case .ra:
            if let raBounds = raColumnBounds {
                let raScreen = regionToScreen(bounds: raBounds, dofusBounds: dofusBounds)
                screenX = raScreen.midX
            } else {
                screenX = statsRegionScreen.minX + statsRegionScreen.width * CGFloat(columns.ra)
            }
        case .pa:
            if let paBounds = paColumnBounds {
                let paScreen = regionToScreen(bounds: paBounds, dofusBounds: dofusBounds)
                screenX = paScreen.midX
            } else {
                screenX = statsRegionScreen.minX + statsRegionScreen.width * CGFloat(columns.pa)
            }
        case .base:
            if let baseBounds = baseColumnBounds {
                let baseScreen = regionToScreen(bounds: baseBounds, dofusBounds: dofusBounds)
                screenX = baseScreen.midX
            } else {
                screenX = statsRegionScreen.minX + statsRegionScreen.width * CGFloat(columns.modif)
            }
        }

        return CGPoint(x: screenX, y: rowY)
    }

    // MARK: - Helpers

    private func regionToScreen(bounds: NormalizedRect, dofusBounds: CGRect) -> CGRect {
        let absInWindow = bounds.absolute(in: dofusBounds.size)
        return CGRect(
            x: dofusBounds.minX + absInWindow.minX,
            y: dofusBounds.minY + absInWindow.minY,
            width: absInWindow.width,
            height: absInWindow.height
        )
    }

    /// Cherche dans les observations OCR de la zone stats l'observation qui
    /// contient le nom de la stat ciblée. Retourne la Y center de cette obs
    /// en coordonnées écran.
    private func findRowYFromOCR(
        statName: String,
        ocrSnapshot: RawOCRSnapshot?,
        statsRegionScreen: CGRect,
        statsRegionBounds: NormalizedRect
    ) -> CGFloat? {
        guard let snapshot = ocrSnapshot,
              let result = snapshot.results[RegionKind.stats],
              !result.observations.isEmpty,
              result.imageSize.height > 0 else { return nil }

        let target = normalize(statName)
        guard !target.isEmpty else { return nil }

        // Utilise la VRAIE taille de l'image OCR croppée (sinon les fractions se compressent
        // et le click dérive de plus en plus vers le bas du tableau).
        let croppedImageHeight = result.imageSize.height

        for obs in result.observations {
            let normalized = normalize(obs.text)
            if normalized.contains(target) || target.contains(normalized) {
                // bbox.midY en pixels du cropped image (top-left origin)
                let rowFractionInRegion = obs.boundingBox.midY / croppedImageHeight
                let rowY = statsRegionScreen.minY + statsRegionScreen.height * rowFractionInRegion
                return rowY
            }
        }
        return nil
    }

    private func normalize(_ s: String) -> String {
        let lower = s.lowercased()
        let folded = lower.folding(options: .diacriticInsensitive, locale: .current)
        return folded
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
