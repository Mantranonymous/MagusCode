import Foundation
import MagusCore

/// Importer des fichiers `.efitem` du bot concurrent ExoFast.
///
/// Format binaire reverse-engineerd :
/// - Header : `01 00 00 LEN` (LEN = longueur du nom)
/// - Name : XOR-chain (LEN+1 bytes) — `enc[0] = name[0] ^ LEN`, `enc[i] = name[i-1] ^ name[i]`
/// - Préambule : 16 bytes fixes pour items "standard", variable pour items complexes
/// - Stat blocks : marqués `01 01`, contiennent effectId + target
///
/// **Stratégie MVP** : on extrait toujours le nom (très fiable), et on tente de
/// parser les targets (best effort). Si on n'a pas le nom dans DofusDB, on rate.
/// L'utilisateur peut compléter manuellement dans le PresetEditor.
public struct EfitemImporter: Sendable {

    public enum ImportError: Swift.Error, LocalizedError {
        case invalidHeader
        case truncated
        case nameDecodingFailed
        public var errorDescription: String? {
            switch self {
            case .invalidHeader: return "Header .efitem invalide (attendu 01 00 00 LEN)"
            case .truncated: return "Fichier .efitem tronqué"
            case .nameDecodingFailed: return "Décodage du nom de l'item échoué"
            }
        }
    }

    public struct Parsed: Sendable {
        public let itemName: String
        /// Targets best-effort extraits du binaire. `(characteristicId DofusDB, target)`.
        /// Peut être vide si le parsing des blocs rate.
        public let targets: [(characteristicId: Int, target: Int)]
    }

    /// Mapping effect_id ExoFast → characteristicId DofusDB Dofus 3.
    /// **Doit rester aligné avec `Presets/convert_efitem.py`** (source de vérité).
    /// Corrigé v2 après bug "Dommage Feu 5/11" — l'ancienne table mappait 418→89 (Feu)
    /// alors que 418 = Dommages Critiques (cid 86) et 424 = Feu (cid 89).
    private static let effectToCharacteristic: [Int: Int] = [
        111: 1,    // PA
        112: 16,   // Dommages
        115: 18,   // % Critique
        117: 19,   // Portée
        118: 10,   // Force
        119: 14,   // Agilité
        123: 13,   // Chance
        124: 12,   // Sagesse
        125: 11,   // Vitalité
        126: 15,   // Intelligence
        128: 23,   // PM
        138: 25,   // Puissance
        158: 40,   // Pods
        160: 27,   // Esquive PA
        161: 28,   // Esquive PM
        163: 28,   // Esquive PM (variant)
        174: 44,   // Initiative
        176: 48,   // Prospection
        178: 49,   // Soins
        182: 26,   // Invocations
        // Résistances en % — ordre canonique DofusDB :
        // 210=Terre, 211=Eau, 212=Air, 213=Feu, 214=Neutre
        210: 33, 211: 35, 212: 36, 213: 34, 214: 37,
        // Résistances fixes — ordre canonique :
        // 240=Terre, 241=Eau, 242=Air, 243=Feu, 244=Neutre
        240: 54, 241: 56, 242: 57, 243: 55, 244: 58,
        // Dommages élémentaires :
        // 414=Poussée, 418=DoCri, 422=Terre, 424=Feu, 426=Eau, 428=Air
        414: 84, 418: 86, 422: 88, 424: 89, 426: 90, 428: 91,
        // Poussée fixe
        416: 85,
        // Tacle / Fuite
        752: 78, 753: 79, 755: 79,
    ]

    public init() {}

    public func parse(_ data: Data) throws -> Parsed {
        guard data.count >= 5 else { throw ImportError.truncated }
        let bytes = Array(data)
        guard bytes[0] == 0x01, bytes[1] == 0x00, bytes[2] == 0x00 else {
            throw ImportError.invalidHeader
        }
        let nameLen = Int(bytes[3])
        guard bytes.count >= 4 + nameLen + 1 else { throw ImportError.truncated }
        let nameSlice = Array(bytes[4..<(4 + nameLen + 1)])
        guard let name = decodeXorChainName(nameSlice, length: nameLen), !name.isEmpty else {
            throw ImportError.nameDecodingFailed
        }

        var targets: [Int: Int] = [:]
        let payloadStart = 4 + nameLen + 1

        // Pass 1 : main blocks "01 01 00 [flag] ..."
        var i = payloadStart
        while i + 11 < bytes.count {
            if bytes[i] == 0x01, bytes[i + 1] == 0x01, bytes[i + 2] == 0x00 {
                if let (eid, t) = parseMainBlock(bytes: bytes, at: i),
                   let charId = Self.effectToCharacteristic[eid],
                   t > 0, t < 5000 {
                    targets[charId] = t
                }
                i += 19
            } else {
                i += 1
            }
        }

        // Pass 2 : chains "13 9b 89 01 [mini_stat * N]" — c'est ici que les stats
        // type Force/Agi/Int sont stockées (et qu'on ratait avant !)
        i = payloadStart
        while i + 4 < bytes.count {
            if bytes[i] == 0x13, bytes[i + 1] == 0x9b, bytes[i + 2] == 0x89, bytes[i + 3] == 0x01 {
                var j = i + 4
                while j + 9 <= bytes.count {
                    guard let (eid, t, cont) = parseChainMini(bytes: bytes, at: j) else { break }
                    if let charId = Self.effectToCharacteristic[eid], t > 0, t < 5000,
                       targets[charId] == nil {
                        targets[charId] = t
                    }
                    j += 9
                    if cont != 0x01 { break }
                }
                i = j
            } else {
                i += 1
            }
        }

        let list = targets.map { (characteristicId: $0.key, target: $0.value) }
            .sorted { $0.characteristicId < $1.characteristicId }
        return Parsed(itemName: name, targets: list)
    }

    /// Décode le nom XOR-chain.
    /// `enc[0] = name[0] XOR length`, `enc[i] = name[i-1] XOR name[i]`.
    private func decodeXorChainName(_ enc: [UInt8], length: Int) -> String? {
        guard length > 0, enc.count >= length else { return nil }
        var decoded = [UInt8](repeating: 0, count: length)
        decoded[0] = enc[0] ^ UInt8(length & 0xFF)
        for i in 1..<length {
            decoded[i] = enc[i] ^ decoded[i - 1]
        }
        return String(bytes: decoded, encoding: .utf8)
            ?? String(bytes: decoded, encoding: .isoLatin1)
    }

    /// Parse un bloc principal commençant par `01 01 00 [flag]`.
    /// - 1-byte eid (flag=0x00) : eid à `[off+4]==[off+5]`
    /// - 2-byte eid (flag=0x01) : eid = `(byte[off+3] << 8) | byte[off+5]` (le flag est le high byte !)
    /// - target_high à `[off+7]`, target_low à `[off+8..9]` (XOR-pair tolérant ±1)
    /// - Donc target = (th << 8) | tl pour les targets > 255 (Vita = 291 sur Veinard)
    private func parseMainBlock(bytes: [UInt8], at offset: Int) -> (eid: Int, target: Int)? {
        guard offset + 11 < bytes.count else { return nil }
        let flag = bytes[offset + 3]
        let eid: Int
        switch flag {
        case 0x00:
            guard bytes[offset + 4] == bytes[offset + 5], bytes[offset + 4] != 0 else { return nil }
            eid = Int(bytes[offset + 4])
        case 0x01:
            // CLÉ : le high byte de l'eid 2-byte EST le flag lui-même
            eid = (Int(bytes[offset + 3]) << 8) | Int(bytes[offset + 5])
        default:
            return nil
        }
        let th = Int(bytes[offset + 7])
        let t1 = Int(bytes[offset + 8])
        let t2 = Int(bytes[offset + 9])
        let tl: Int
        if t1 == t2 { tl = t1 }
        else if abs(t1 - t2) == 1 { tl = min(t1, t2) }
        else { return nil }
        return (eid, (th << 8) | tl)
    }

    /// Parse une mini-stat dans une chain (9 bytes après `13 9b 89 01`).
    /// Format : `00 00 EE EE 00 TH TL TL CONT`.
    /// CONT = 0x01 → la chain continue (mini-stat suivante), 0x00 → fin.
    /// Découverte : c'est ici que les stats type Force/Agi/Int sont stockées.
    private func parseChainMini(bytes: [UInt8], at offset: Int) -> (eid: Int, target: Int, cont: UInt8)? {
        guard offset + 9 <= bytes.count else { return nil }
        guard bytes[offset] == 0x00, bytes[offset + 1] == 0x00 else { return nil }
        let e1 = bytes[offset + 2]
        let e2 = bytes[offset + 3]
        guard e1 != 0, e1 == e2 else { return nil }
        guard bytes[offset + 4] == 0x00 else { return nil }
        let th = bytes[offset + 5]
        guard th <= 0x10 else { return nil }
        let t1 = Int(bytes[offset + 6])
        let t2 = Int(bytes[offset + 7])
        let tl: Int
        if t1 == t2 { tl = t1 }
        else if abs(t1 - t2) == 1 { tl = min(t1, t2) }
        else { return nil }
        return (Int(e1), (Int(th) << 8) | tl, bytes[offset + 8])
    }
}
