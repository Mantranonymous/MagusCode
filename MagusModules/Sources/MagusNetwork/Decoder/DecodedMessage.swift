import Foundation

/// Un message protobuf observé sur le réseau Dofus 3, après framing + decode.
///
/// Tant que les fichiers `.pb.swift` ne sont pas générés (cf
/// `Protos/Generated/_README.md`), les payloads sont représentés par les bytes
/// bruts du message (sous forme de `Data`) et un `typeUrl` extrait de
/// `google.protobuf.Any` quand disponible.
///
/// Une fois les types générés, `payloadBytes` sera remplacé par les vrais types
/// Swift, par exemple :
///
///   case exchangeCraftResult(Com_Ankama_Dofus_Server_Game_Protocol_Exchange_ExchangeCraftResultEvent)
public enum DecodedMessage: Sendable {

    /// Sens dans lequel le paquet circulait au moment de l'observation.
    public enum Direction: String, Sendable {
        /// Du client (Dofus) vers le serveur (Ankama).
        case clientToServer
        /// Du serveur vers le client.
        case serverToClient
    }

    /// Événement reconnu côté forgemagie (cf `Protos/clear/game/exchange.proto`).
    case exchangeStarted(typeUrl: String, payloadBytes: Data, direction: Direction)
    case exchangeRunesTradeStarted(typeUrl: String, payloadBytes: Data, direction: Direction)
    case exchangeObjectsAdded(typeUrl: String, payloadBytes: Data, direction: Direction)
    case exchangeObjectsModified(typeUrl: String, payloadBytes: Data, direction: Direction)
    case exchangeCraftResult(typeUrl: String, payloadBytes: Data, direction: Direction)
    case exchangeLeave(typeUrl: String, payloadBytes: Data, direction: Direction)

    /// Message décodé mais pas (encore) classifié dans la liste FM-pertinente.
    /// On garde le `typeUrl` pour pouvoir débugger dans la PacketLog.
    case unknown(typeUrl: String, payloadBytes: Data, direction: Direction)

    /// Le decode a échoué (frame mal alignée, type-url inconnue, etc.).
    /// On le pousse dans le stream uniquement pour debug, le proxy continue
    /// son forward sans interruption.
    case decodeError(reason: String, rawBytes: Data, direction: Direction)
}

extension DecodedMessage {
    /// Helper debug : nom court pour la PacketLog UI.
    public var shortLabel: String {
        switch self {
        case .exchangeStarted: return "ExchangeStarted"
        case .exchangeRunesTradeStarted: return "ExchangeRunesTradeStarted"
        case .exchangeObjectsAdded: return "ExchangeObjectsAdded"
        case .exchangeObjectsModified: return "ExchangeObjectsModified"
        case .exchangeCraftResult: return "ExchangeCraftResult"
        case .exchangeLeave: return "ExchangeLeave"
        case .unknown(let typeUrl, _, _): return "Unknown[\(typeUrl.suffix(40))]"
        case .decodeError(let reason, _, _): return "DecodeError[\(reason)]"
        }
    }

    public var direction: Direction {
        switch self {
        case .exchangeStarted(_, _, let d),
             .exchangeRunesTradeStarted(_, _, let d),
             .exchangeObjectsAdded(_, _, let d),
             .exchangeObjectsModified(_, _, let d),
             .exchangeCraftResult(_, _, let d),
             .exchangeLeave(_, _, let d),
             .unknown(_, _, let d),
             .decodeError(_, _, let d):
            return d
        }
    }
}
