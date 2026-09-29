namespace MagusBot.Network.Messages;

/// <summary>
/// STUB — Client → Server : appliquer une rune sur l'item courant.
///
/// <b>TODO RE</b> : ce sera probablement un drag-drop de la rune sur l'item,
/// modélisé par un <c>ExchangeObjectMoveMessage</c> ou <c>ExchangeCraftingRuneAction</c>.
/// </summary>
public sealed class FmActionPacket : Packet
{
    public override ushort PacketId => 0xDEAE; // TODO RE
    public override string Name => "FmAction";
    public override PacketDirection Direction => PacketDirection.ClientToServer;

    /// <summary>UID de la rune dans l'inventaire du joueur.</summary>
    public required long RuneUid { get; init; }

    /// <summary>UID de l'item cible.</summary>
    public required long ItemUid { get; init; }
}
