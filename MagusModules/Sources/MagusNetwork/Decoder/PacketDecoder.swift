import Foundation
import os

private let logger = Logger(subsystem: "com.magus.network", category: "decoder")

/// Décode une frame protobuf (déjà délimitée par le `PacketFramer`) en une
/// valeur `DecodedMessage` riche.
///
/// Statut actuel : **scaffolding**. Tant que les `.pb.swift` n'ont pas été
/// générés via `Protos/generate.sh`, ce decoder ne peut pas vraiment parser
/// l'envelope `Message` ni le wrapper `google.protobuf.Any`. Il tente une
/// heuristique simple sur la frame brute : extraction du `type_url` si présent
/// (cherche la séquence `type.googleapis.com/…`), classification en fonction
/// du suffixe, et retour d'un `DecodedMessage.unknown` sinon.
///
/// Une fois les types générés, remplacer le corps de `decode(_:direction:)`
/// par un vrai `try Message(serializedData:)` puis un switch sur le `oneof`.
public final class PacketDecoder: Sendable {

    public init() {}

    /// Décode une frame complète issue du framer.
    ///
    /// - Parameter frame: bytes du message protobuf (sans le length-prefix).
    /// - Parameter direction: sens d'observation.
    /// - Returns: un `DecodedMessage`. Ne throw jamais : tout échec est
    ///   converti en `.decodeError` pour ne pas casser le proxy forward.
    public func decode(_ frame: Data, direction: DecodedMessage.Direction) -> DecodedMessage {
        // PLACEHOLDER until protoc runs.
        //
        // TODO: importer `Com_Ankama_Dofus_Server_Game_Protocol_Message` et
        // décoder via `try Com_Ankama_Dofus_Server_Game_Protocol_Message(
        //     serializedData: frame
        // )`.
        // Le champ `event.content` est un `google.protobuf.Any` dont le
        // `type_url` se termine par `…ExchangeCraftResultEvent` etc.
        // On peut alors faire :
        //     if any.isA(Com_…_ExchangeCraftResultEvent.self) {
        //         let craft = try Com_…_ExchangeCraftResultEvent(unpackingAny: any)
        //         return .exchangeCraftResult(craft)
        //     }
        //
        // En attendant on fait du best-effort sur les bytes bruts.

        guard !frame.isEmpty else {
            return .decodeError(reason: "empty frame", rawBytes: frame, direction: direction)
        }

        if let typeUrl = Self.extractTypeUrl(from: frame) {
            return classify(typeUrl: typeUrl, payload: frame, direction: direction)
        }

        return .unknown(typeUrl: "(no type_url found)", payloadBytes: frame, direction: direction)
    }

    // MARK: - Helpers

    /// Cherche dans la frame brute la séquence ASCII `type.googleapis.com/...`
    /// utilisée par `google.protobuf.Any`. Best-effort, retourne nil si non
    /// trouvée.
    private static func extractTypeUrl(from data: Data) -> String? {
        // Marker : "type.googleapis.com/"
        let marker: [UInt8] = Array("type.googleapis.com/".utf8)
        guard let range = data.range(of: Data(marker)) else { return nil }
        // Lit jusqu'au prochain byte non-ASCII / non-printable
        var url = "type.googleapis.com/"
        var idx = range.upperBound
        while idx < data.endIndex {
            let b = data[idx]
            if b >= 0x20 && b < 0x7F {
                let c = Character(UnicodeScalar(b))
                if c.isLetter || c.isNumber || c == "." || c == "_" || c == "/" {
                    url.append(c)
                    idx = data.index(after: idx)
                    continue
                }
            }
            break
        }
        return url
    }

    private func classify(
        typeUrl: String,
        payload: Data,
        direction: DecodedMessage.Direction
    ) -> DecodedMessage {
        // Suffixe court pour reconnaître l'événement FM.
        let lower = typeUrl.lowercased()

        if lower.hasSuffix("exchangecraftresultevent") {
            return .exchangeCraftResult(typeUrl: typeUrl, payloadBytes: payload, direction: direction)
        }
        if lower.hasSuffix("exchangeobjectsmodifiedevent") {
            return .exchangeObjectsModified(typeUrl: typeUrl, payloadBytes: payload, direction: direction)
        }
        if lower.hasSuffix("exchangeobjectsaddedevent") {
            return .exchangeObjectsAdded(typeUrl: typeUrl, payloadBytes: payload, direction: direction)
        }
        if lower.hasSuffix("exchangerunestradestartedevent") {
            return .exchangeRunesTradeStarted(typeUrl: typeUrl, payloadBytes: payload, direction: direction)
        }
        if lower.contains("exchangestarted") {
            return .exchangeStarted(typeUrl: typeUrl, payloadBytes: payload, direction: direction)
        }
        if lower.hasSuffix("exchangeleaveevent") {
            return .exchangeLeave(typeUrl: typeUrl, payloadBytes: payload, direction: direction)
        }
        return .unknown(typeUrl: typeUrl, payloadBytes: payload, direction: direction)
    }
}
