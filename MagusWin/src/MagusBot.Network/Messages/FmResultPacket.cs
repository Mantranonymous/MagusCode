using MagusBot.Core.Models;

namespace MagusBot.Network.Messages;

/// <summary>
/// STUB — Server → Client : résultat d'une pose de rune (SC/SN/EC + Δstat + Δreliquat).
///
/// <b>TODO RE</b> : trouver le packet exact qui notifie le résultat. Probablement
/// <c>ExchangeCraftResultMessage</c> + <c>ObjectModifiedMessage</c> (pour l'item)
/// combinés. Mesurer la fenêtre temporelle entre <see cref="FmActionPacket"/> envoyé
/// et résultat reçu.
/// </summary>
public sealed class FmResultPacket : Packet
{
    public override ushort PacketId => 0xDEAF; // TODO RE
    public override string Name => "FmResult";
    public override PacketDirection Direction => PacketDirection.ServerToClient;

    public required CombineResult Result { get; init; }
    public required StatKind TargetStat { get; init; }
    public int StatDelta { get; init; }
    public double ReliquatDelta { get; init; }
}
