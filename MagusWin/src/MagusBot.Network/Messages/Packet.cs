namespace MagusBot.Network.Messages;

/// <summary>
/// Base abstraite pour tous les packets envoyés/reçus sur le wire Dofus 3.
///
/// <b>TODO RE</b> : remplir <see cref="PacketId"/> avec l'ID réel découvert via Il2CppDumper
/// + observation Wireshark. Ajouter le sérialiseur binaire propre au protocole (souvent un
/// custom binary writer côté Ankama).
///
/// La taxonomie habituelle Dofus :
/// <list type="bullet">
/// <item>Client → Server : packets "send"</item>
/// <item>Server → Client : packets "receive"</item>
/// </list>
/// Voir <c>docs/PROTOCOL_NOTES.md</c> pour la liste des IDs au fur et à mesure du RE.
/// </summary>
public abstract class Packet
{
    /// <summary>
    /// ID du packet sur le wire. À remplir par chaque classe dérivée à partir
    /// du dump Il2Cpp (<c>ProtocolMessageType.Id</c>).
    /// </summary>
    public abstract ushort PacketId { get; }

    /// <summary>Nom du packet côté Ankama (utile pour le logging et le RE).</summary>
    public abstract string Name { get; }

    /// <summary>Direction : depuis le client vers le serveur, ou inverse.</summary>
    public abstract PacketDirection Direction { get; }
}

public enum PacketDirection
{
    ClientToServer,
    ServerToClient
}
