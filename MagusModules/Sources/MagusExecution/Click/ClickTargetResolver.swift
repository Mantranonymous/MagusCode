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

    /// Pour les exos : la stat n'apparaît pas dans la table FM, donc on doit cliquer
    /// la rune **directement dans l'inventaire**. Retourne le centre de la cellule
    /// calibrée si dispo, nil sinon.
    public func exoInventorySlotPosition(
        for kind: StatKind,
        inventorySlotBounds: NormalizedRect?,
        dofusBounds: CGRect
    ) -> CGPoint? {
        guard let bounds = inventorySlotBounds else { return nil }
        let screen = regionToScreen(bounds: bounds, dofusBounds: dofusBounds)
        return CGPoint(x: screen.midX, y: screen.midY)
    }

    /// True si la stat ciblée est un exo (rune dans inventaire, pas dans table FM).
    /// Inclut PA (1), PM (23), Portée (19), Do Sort % (123), Do Distance % (120).
    public static func isExoTarget(_ kind: StatKind) -> Bool {
        [1, 23, 19, 123, 120].contains(kind.characteristicId)
    }

    /// True UNIQUEMENT si la stat est exo-candidate ET n'est pas native sur l'item.
    /// Si la stat existe déjà sur l'item (item.stat(matching:) != nil), elle apparaît
    /// dans la table FM avec sa colonne Pa/Ra → on doit cliquer la colonne, pas
    /// la rune en inventaire. Évite le bug "Magus va chercher Ga PA en inventaire
    /// alors que le PA natif vient juste de tomber et qu'il y a une rune dans Pa".
    public static func isExoTargetForItem(_ kind: StatKind, item: Item?) -> Bool {
        guard isExoTarget(kind) else { return false }
        // Si la stat est présente sur l'item (native, même tombée à 0), c'est un
        // re-mage classique via la colonne, pas un exo.
        if let item = item, item.stat(matching: kind) != nil {
            return false
        }
        return true
    }

    /// Pour un exo, retourne la `RegionKind` du slot inventaire correspondant.
    public static func exoSlotRegionKind(for kind: StatKind) -> RegionKind? {
        switch kind.characteristicId {
        case 1: return .runeSlotGaPa
        case 23: return .runeSlotGaPme
        case 19: return .runeSlotPo
        case 123: return .runeSlotPaDoSort
        case 120: return .runeSlotPaDoDistance
        default: return nil
        }
    }

    /// Calcule la position écran (Quartz top-left) à cliquer.
    ///
    /// Si `dictionary` est fourni, le matching OCR utilise le StatDictionary pour
    /// identifier la BONNE stat (évite les faux positifs type "1 Portée" matchée
    /// quand on cherche "Dommage Feu").
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
        dofusBounds: CGRect,
        dictionary: StatDictionary? = nil
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
               targetKind: kind,
               dictionary: dictionary,
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

    /// Cherche dans les observations OCR la ligne de la stat ciblée.
    ///
    /// **Stratégie robuste** (évite les faux positifs type "1 Portée" matchée quand on cherche "Dommage Feu") :
    ///
    /// 1. **Priorité 1** : si dictionary fourni, on parse chaque obs pour identifier son StatKind
    ///    via `lookupFuzzy`. On retient seulement les obs qui mappent vers `targetKind`.
    /// 2. **Priorité 2** : fallback string contains (legacy). Plus permissif mais peut tromper.
    private func findRowYFromOCR(
        statName: String,
        targetKind: StatKind,
        dictionary: StatDictionary?,
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
        let croppedImageHeight = result.imageSize.height

        // Stratégie 1 : matching par kind via dictionary (la bonne approche)
        if let dict = dictionary {
            var bestMatch: (y: CGFloat, score: Int)?
            for obs in result.observations {
                guard let resolved = resolveKind(in: obs.text, dictionary: dict),
                      resolved == targetKind else { continue }
                // Score = longueur du texte (préfère les obs avec plus de contexte → moins ambigu)
                let score = obs.text.count
                let rowFraction = obs.boundingBox.midY / croppedImageHeight
                let rowY = statsRegionScreen.minY + statsRegionScreen.height * rowFraction
                if bestMatch == nil || score > bestMatch!.score {
                    bestMatch = (rowY, score)
                }
            }
            if let m = bestMatch { return m.y }
        }

        // Stratégie 2 : fallback substring strict (target ⊂ normalized) — plus sûr que contains(normalized, target)
        // Évite que "1" matche "dommagefeu" via target.contains.
        for obs in result.observations {
            let normalized = normalize(obs.text)
            if normalized.contains(target) {
                let rowFraction = obs.boundingBox.midY / croppedImageHeight
                let rowY = statsRegionScreen.minY + statsRegionScreen.height * rowFraction
                return rowY
            }
        }
        return nil
    }

    /// Résout le StatKind dans un texte OCR via le dictionary. Itère sur les mots
    /// de l'observation et tente fuzzy lookup pour chaque substring.
    private func resolveKind(in text: String, dictionary: StatDictionary) -> StatKind? {
        // Tokenise en mots
        let tokens = text.split(whereSeparator: { $0.isWhitespace || "()%-+:".contains($0) })
            .map(String.init)
            .filter { $0.count >= 2 }
        // Tente d'abord les paires consécutives (ex: "Dommage Feu")
        for i in 0..<tokens.count {
            if i + 1 < tokens.count {
                let pair = "\(tokens[i]) \(tokens[i+1])"
                if let kind = dictionary.lookupFuzzy(pair) { return kind }
            }
            if let kind = dictionary.lookupFuzzy(tokens[i]) { return kind }
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
