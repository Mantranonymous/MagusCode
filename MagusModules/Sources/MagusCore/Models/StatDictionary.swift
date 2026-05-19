import Foundation

/// Lookup `String → StatKind` avec aliases et tolérance aux fautes OCR.
/// Construit depuis la liste DofusDB (`name_fr`) + table d'aliases manuelle.
public struct StatDictionary: Sendable {

    public struct Entry: Sendable {
        public let kind: StatKind
        public let canonicalName: String
        public init(kind: StatKind, canonicalName: String) {
            self.kind = kind
            self.canonicalName = canonicalName
        }
    }

    private let exactMap: [String: StatKind]    // normalisé → kind
    private let entries: [Entry]                // pour fuzzy

    /// Aliases manuels (forme courte FR → nom canonique DofusDB).
    /// Couvre :
    /// - les écrits courts qu'on voit en jeu (ex: "PA", "Vita")
    /// - les libellés UI Dofus 3 vs noms DofusDB (ex: "Résistance Neutre" → "Neutre (%)")
    public static let defaultAliases: [String: String] = [
        // Stats principales (formes courtes)
        "vita": "vitalité",
        "vit": "vitalité",
        "pv": "points de vie",
        "pa": "pa",
        "pm": "pm",
        "ra": "portée",
        "po": "portée",
        "sa": "sagesse",
        "fo": "force",
        "in": "intelligence",
        "ch": "chance",
        "ag": "agilité",
        "pui": "puissance",
        "dom": "dommages",
        "crit": "critique",
        "cc": "coups critiques",

        // Résistances en % (avec "%" dans la ligne OCR)
        "résistance neutre %": "Neutre (%)",
        "résistance terre %": "Terre (%)",
        "résistance feu %": "Feu (%)",
        "résistance eau %": "Eau (%)",
        "résistance air %": "Air (%)",

        // Résistances fixes (sans "%" dans la ligne OCR)
        "résistance neutre": "Neutre (fixe)",
        "résistance terre": "Terre (fixe)",
        "résistance feu": "Feu (fixe)",
        "résistance eau": "Eau (fixe)",
        "résistance air": "Air (fixe)",

        // Avec le % devant (pas standard mais possible)
        "% résistance neutre": "Neutre (%)",
        "% résistance terre": "Terre (%)",
        "% résistance feu": "Feu (%)",
        "% résistance eau": "Eau (%)",
        "% résistance air": "Air (%)",

        // Dommages élémentaires (DofusDB stocke "Terre"/"Feu"/"Eau"/"Air"/"Neutre" pour les dommages)
        "dommage terre": "Terre",
        "dommage feu": "Feu",
        "dommage eau": "Eau",
        "dommage air": "Air",
        "dommage neutre": "Neutre",
        "dommages terre": "Terre",
        "dommages feu": "Feu",
        "dommages eau": "Eau",
        "dommages air": "Air",
        "dommages neutre": "Neutre",
    ]

    public init(referenceEntries: [(kind: StatKind, displayName: String)], aliases: [String: String] = defaultAliases) {
        var exact: [String: StatKind] = [:]
        var entries: [Entry] = []

        for (kind, name) in referenceEntries {
            let normalized = Self.normalize(name)
            exact[normalized] = kind
            entries.append(Entry(kind: kind, canonicalName: name))
        }

        // Appliquer les aliases : alias → kind via canonical name
        for (alias, canonical) in aliases {
            let canonNorm = Self.normalize(canonical)
            if let kind = exact[canonNorm] {
                exact[Self.normalize(alias)] = kind
            }
        }

        self.exactMap = exact
        self.entries = entries
    }

    /// Recherche exacte normalisée. Retourne nil si pas trouvé.
    public func lookup(_ text: String) -> StatKind? {
        let normalized = Self.normalize(text)
        return exactMap[normalized]
    }

    /// Recherche fuzzy : retourne le meilleur match si distance Levenshtein ≤ tolerance.
    public func lookupFuzzy(_ text: String, tolerance: Int = 2) -> StatKind? {
        if let exact = lookup(text) { return exact }
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else { return nil }

        var bestKind: StatKind?
        var bestDist = tolerance + 1
        for entry in entries {
            let cand = Self.normalize(entry.canonicalName)
            let dist = Self.levenshtein(normalized, cand)
            if dist < bestDist {
                bestDist = dist
                bestKind = entry.kind
            }
        }
        return bestKind
    }

    public var size: Int { exactMap.count }

    // MARK: - Helpers

    static func normalize(_ s: String) -> String {
        let lower = s.lowercased()
        let folded = lower.folding(options: .diacriticInsensitive, locale: .current)
        // ATTENTION : on conserve "%", "(", ")" pour distinguer "Force" vs "Force %"
        // (DofusDB a les deux : id 10 "Force" et id 127 "Force %").
        return folded
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let aa = Array(a), bb = Array(b)
        if aa.isEmpty { return bb.count }
        if bb.isEmpty { return aa.count }
        var prev = Array(0...bb.count)
        var curr = [Int](repeating: 0, count: bb.count + 1)
        for i in 1...aa.count {
            curr[0] = i
            for j in 1...bb.count {
                let cost = aa[i - 1] == bb[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,            // delete
                    curr[j - 1] + 1,        // insert
                    prev[j - 1] + cost      // substitute
                )
            }
            swap(&prev, &curr)
        }
        return prev[bb.count]
    }
}
