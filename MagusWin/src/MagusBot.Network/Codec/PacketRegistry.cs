using MagusBot.Network.Messages;

namespace MagusBot.Network.Codec;

/// <summary>
/// Registry des packet IDs Dofus 3 connus.
///
/// <b>TODO RE</b> : remplir au fur et à mesure du dump Il2Cpp +
/// observation des captures Wireshark. La méthode <see cref="Register{T}"/>
/// permet d'enregistrer un type Packet pour son ID wire.
///
/// Conseil : commencer par les packets FM nécessaires au MVP :
/// <list type="bullet">
/// <item>Sélection de l'item (<see cref="ItemSelectedPacket"/>)</item>
/// <item>Application de rune (<see cref="FmActionPacket"/>)</item>
/// <item>Résultat de pose (<see cref="FmResultPacket"/>)</item>
/// <item>Mise à jour reliquat (à découvrir)</item>
/// <item>Mise à jour item après pose (probable <c>ObjectModifiedMessage</c>)</item>
/// </list>
/// </summary>
public sealed class PacketRegistry
{
    private readonly Dictionary<ushort, Func<Packet>> _factories = new();

    /// <summary>Enregistre un constructeur de packet pour un ID donné.</summary>
    public void Register<T>(Func<T> factory) where T : Packet
    {
        var sample = factory();
        _factories[sample.PacketId] = factory;
    }

    /// <summary>Construit une nouvelle instance vide d'un packet pour l'ID donné.</summary>
    public Packet? CreateForId(ushort id) =>
        _factories.TryGetValue(id, out var f) ? f() : null;

    /// <summary>Liste tous les IDs enregistrés (debug).</summary>
    public IEnumerable<ushort> KnownIds => _factories.Keys;
}
