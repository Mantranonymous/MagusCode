using System.Text;

namespace MagusBot.Persistence;

/// <summary>
/// Importer des fichiers <c>.efitem</c> du bot concurrent ExoFast.
///
/// Format binaire reverse-engineerd :
/// - Header : <c>01 00 00 LEN</c> (LEN = longueur du nom)
/// - Name : XOR-chain (LEN+1 bytes) — <c>enc[0] = name[0] ^ LEN</c>, <c>enc[i] = name[i-1] ^ name[i]</c>
/// - Préambule : 16 bytes fixes pour items "standard", variable pour items complexes
/// - Stat blocks : marqués <c>01 01</c>, contiennent effectId + target
///
/// <b>Stratégie MVP</b> : on extrait toujours le nom (très fiable), et on tente de
/// parser les targets (best effort). Si on n'a pas le nom dans DofusDB, on rate.
/// L'utilisateur peut compléter manuellement.
/// </summary>
public sealed class EfitemImporter
{
    public sealed class ImportException : Exception
    {
        public ImportException(string message) : base(message) { }
    }

    public sealed record Parsed(string ItemName, IReadOnlyList<EfitemTarget> Targets);

    public sealed record EfitemTarget(int CharacteristicId, int Target);

    /// <summary>
    /// Mapping effect_id ExoFast → characteristicId DofusDB Dofus 3.
    /// <b>Doit rester aligné avec <c>Presets/convert_efitem.py</c></b> et le Swift
    /// (<c>MagusModules/Sources/MagusPersistence/EfitemImporter.swift</c>). Toute
    /// divergence introduit des bugs subtils (mauvais effet appliqué).
    /// Corrigé v2 après bug "Dommage Feu 5/11" — l'ancienne table mappait 418→89 (Feu)
    /// alors que 418 = Dommages Critiques (cid 86) et 424 = Feu (cid 89).
    /// </summary>
    private static readonly IReadOnlyDictionary<int, int> EffectToCharacteristic = new Dictionary<int, int>
    {
        { 111, 1 },    // PA
        { 112, 16 },   // Dommages
        { 115, 18 },   // % Critique
        { 117, 19 },   // Portée
        { 118, 10 },   // Force
        { 119, 14 },   // Agilité
        { 123, 13 },   // Chance
        { 124, 12 },   // Sagesse
        { 125, 11 },   // Vitalité
        { 126, 15 },   // Intelligence
        { 128, 23 },   // PM
        { 138, 25 },   // Puissance
        { 158, 40 },   // Pods
        { 160, 27 },   // Esquive PA
        { 161, 28 },   // Esquive PM
        { 163, 28 },   // Esquive PM (variant)
        { 174, 44 },   // Initiative
        { 176, 48 },   // Prospection
        { 178, 49 },   // Soins
        { 182, 26 },   // Invocations
        // Résistances en % — ordre canonique DofusDB :
        // 210=Terre, 211=Eau, 212=Air, 213=Feu, 214=Neutre
        { 210, 33 }, { 211, 35 }, { 212, 36 }, { 213, 34 }, { 214, 37 },
        // Résistances fixes — ordre canonique :
        // 240=Terre, 241=Eau, 242=Air, 243=Feu, 244=Neutre
        { 240, 54 }, { 241, 56 }, { 242, 57 }, { 243, 55 }, { 244, 58 },
        // Dommages élémentaires :
        // 414=Poussée, 418=DoCri, 422=Terre, 424=Feu, 426=Eau, 428=Air
        { 414, 84 }, { 418, 86 }, { 422, 88 }, { 424, 89 }, { 426, 90 }, { 428, 91 },
        // Poussée fixe
        { 416, 85 },
        // Tacle / Fuite
        { 752, 78 }, { 753, 79 }, { 755, 79 },
    };

    public Parsed Parse(byte[] data)
    {
        if (data.Length < 5) throw new ImportException("Fichier .efitem tronqué");
        if (data[0] != 0x01 || data[1] != 0x00 || data[2] != 0x00)
            throw new ImportException("Header .efitem invalide (attendu 01 00 00 LEN)");

        var nameLen = data[3];
        if (data.Length < 4 + nameLen + 1) throw new ImportException("Fichier .efitem tronqué");

        var nameSlice = new byte[nameLen + 1];
        Array.Copy(data, 4, nameSlice, 0, nameLen + 1);
        var name = DecodeXorChainName(nameSlice, nameLen);
        if (string.IsNullOrEmpty(name))
            throw new ImportException("Décodage du nom de l'item échoué");

        var targets = new Dictionary<int, int>();
        var payloadStart = 4 + nameLen + 1;

        // Pass 1 : main blocks "01 01 00 [flag] ..."
        var i = payloadStart;
        while (i + 11 < data.Length)
        {
            if (data[i] == 0x01 && data[i + 1] == 0x01 && data[i + 2] == 0x00)
            {
                var parsed = ParseMainBlock(data, i);
                if (parsed is not null &&
                    EffectToCharacteristic.TryGetValue(parsed.Value.Eid, out var charId) &&
                    parsed.Value.Target > 0 && parsed.Value.Target < 5000)
                {
                    targets[charId] = parsed.Value.Target;
                }
                i += 19;
            }
            else
            {
                i += 1;
            }
        }

        // Pass 2 : chains "13 9b 89 01 [mini_stat * N]" — c'est ici que les stats
        // type Force/Agi/Int sont stockées (et qu'on ratait avant !)
        i = payloadStart;
        while (i + 4 < data.Length)
        {
            if (data[i] == 0x13 && data[i + 1] == 0x9b && data[i + 2] == 0x89 && data[i + 3] == 0x01)
            {
                var j = i + 4;
                while (j + 9 <= data.Length)
                {
                    var mini = ParseChainMini(data, j);
                    if (mini is null) break;
                    if (EffectToCharacteristic.TryGetValue(mini.Value.Eid, out var charId) &&
                        mini.Value.Target > 0 && mini.Value.Target < 5000 &&
                        !targets.ContainsKey(charId))
                    {
                        targets[charId] = mini.Value.Target;
                    }
                    j += 9;
                    if (mini.Value.Cont != 0x01) break;
                }
                i = j;
            }
            else
            {
                i += 1;
            }
        }

        var list = targets
            .Select(kv => new EfitemTarget(kv.Key, kv.Value))
            .OrderBy(t => t.CharacteristicId)
            .ToList();
        return new Parsed(name, list);
    }

    /// <summary>
    /// Décode le nom XOR-chain.
    /// <c>enc[0] = name[0] XOR length</c>, <c>enc[i] = name[i-1] XOR name[i]</c>.
    /// </summary>
    private static string? DecodeXorChainName(byte[] enc, int length)
    {
        if (length <= 0 || enc.Length < length) return null;
        var decoded = new byte[length];
        decoded[0] = (byte)(enc[0] ^ (byte)(length & 0xFF));
        for (var i = 1; i < length; i++)
            decoded[i] = (byte)(enc[i] ^ decoded[i - 1]);
        try
        {
            return Encoding.UTF8.GetString(decoded);
        }
        catch
        {
            return Encoding.Latin1.GetString(decoded);
        }
    }

    /// <summary>
    /// Parse un bloc principal commençant par <c>01 01 00 [flag]</c>.
    /// - 1-byte eid (flag=0x00) : eid à <c>[off+4]==[off+5]</c>
    /// - 2-byte eid (flag=0x01) : eid = <c>(byte[off+3] &lt;&lt; 8) | byte[off+5]</c> (le flag est le high byte !)
    /// - target_high à <c>[off+7]</c>, target_low à <c>[off+8..9]</c> (XOR-pair tolérant ±1)
    /// </summary>
    private static (int Eid, int Target)? ParseMainBlock(byte[] bytes, int offset)
    {
        if (offset + 11 >= bytes.Length) return null;
        var flag = bytes[offset + 3];
        int eid;
        switch (flag)
        {
            case 0x00:
                if (bytes[offset + 4] != bytes[offset + 5] || bytes[offset + 4] == 0) return null;
                eid = bytes[offset + 4];
                break;
            case 0x01:
                // CLÉ : le high byte de l'eid 2-byte EST le flag lui-même
                eid = (bytes[offset + 3] << 8) | bytes[offset + 5];
                break;
            default:
                return null;
        }
        var th = bytes[offset + 7];
        int t1 = bytes[offset + 8];
        int t2 = bytes[offset + 9];
        int tl;
        if (t1 == t2) tl = t1;
        else if (Math.Abs(t1 - t2) == 1) tl = Math.Min(t1, t2);
        else return null;
        return (eid, (th << 8) | tl);
    }

    /// <summary>
    /// Parse une mini-stat dans une chain (9 bytes après <c>13 9b 89 01</c>).
    /// Format : <c>00 00 EE EE 00 TH TL TL CONT</c>.
    /// CONT = 0x01 → la chain continue (mini-stat suivante), 0x00 → fin.
    /// </summary>
    private static (int Eid, int Target, byte Cont)? ParseChainMini(byte[] bytes, int offset)
    {
        if (offset + 9 > bytes.Length) return null;
        if (bytes[offset] != 0x00 || bytes[offset + 1] != 0x00) return null;
        var e1 = bytes[offset + 2];
        var e2 = bytes[offset + 3];
        if (e1 == 0 || e1 != e2) return null;
        if (bytes[offset + 4] != 0x00) return null;
        var th = bytes[offset + 5];
        if (th > 0x10) return null;
        int t1 = bytes[offset + 6];
        int t2 = bytes[offset + 7];
        int tl;
        if (t1 == t2) tl = t1;
        else if (Math.Abs(t1 - t2) == 1) tl = Math.Min(t1, t2);
        else return null;
        return (e1, (th << 8) | tl, bytes[offset + 8]);
    }
}
