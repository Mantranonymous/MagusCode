using MagusBot.Network.Messages;

namespace MagusBot.Network.Codec;

/// <summary>
/// Encode et décode les packets Dofus 3 vers/depuis le format binaire wire.
///
/// <b>TODO RE — sans implémentation pour le moment.</b>
///
/// Pistes à confirmer :
/// <list type="bullet">
/// <item>Encryption : Dofus 2 utilisait un XOR avec clé fixe / partial AES. À vérifier en Dofus 3.</item>
/// <item>Header : magic byte + length-prefix big endian (probable, hérité de D2)</item>
/// <item>Payload : custom binary format avec types primitifs (varint, string len-prefixed)</item>
/// <item>Compression : packets > 1024 bytes potentiellement gzip-compressés</item>
/// </list>
///
/// Voir <c>docs/REVERSE_ENGINEERING.md</c> pour le workflow MITM + dump Il2Cpp.
/// </summary>
public sealed class PacketCodec
{
    /// <summary>Encode un packet vers le format wire. À implémenter après RE.</summary>
    public byte[] Encode(Packet packet)
    {
        throw new NotImplementedException(
            "PacketCodec.Encode non implémenté — voir docs/REVERSE_ENGINEERING.md. " +
            $"Packet: {packet.Name} (id 0x{packet.PacketId:X4}).");
    }

    /// <summary>Décode un buffer wire vers un packet typé. À implémenter après RE.</summary>
    public Packet Decode(ReadOnlySpan<byte> buffer)
    {
        throw new NotImplementedException(
            "PacketCodec.Decode non implémenté — voir docs/REVERSE_ENGINEERING.md. " +
            $"Buffer size: {buffer.Length} bytes.");
    }
}
