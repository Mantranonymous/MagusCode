namespace MagusBot.Network.Messages;

/// <summary>
/// STUB — Client → Server : sélection d'un item à mager dans l'établi FM.
///
/// <b>TODO RE</b> :
/// <list type="bullet">
/// <item>Trouver l'ID exact (probablement quelque chose comme <c>ExchangeObjectMoveMessage</c>
///     ou un message dédié à la FM)</item>
/// <item>Identifier les champs : UID de l'item, slot d'établi, signature</item>
/// </list>
/// </summary>
public sealed class ItemSelectedPacket : Packet
{
    public override ushort PacketId => 0xDEAD; // TODO RE
    public override string Name => "ItemSelected"; // TODO RE: vrai nom Ankama
    public override PacketDirection Direction => PacketDirection.ClientToServer;

    /// <summary>UID de l'item dans l'inventaire du joueur.</summary>
    public required long ItemUid { get; init; }
}
