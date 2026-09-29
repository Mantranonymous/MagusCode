# Guide reverse engineering Dofus 3

Ce document décrit le workflow pour reverser le protocole réseau Dofus 3 Unity (`Dofus.exe`) et brancher `MagusBot.Network/Real/DofusGameClient` à la place du `StubGameClient`.

> **Avertissement** : ce qui suit est destiné à un usage personnel sur compte secondaire uniquement. Ankama bannit les bots et le RE de leur protocole est officiellement interdit par leurs CGU. Tu prends tous les risques.

## 1. Outillage à installer (Windows)

| Outil | Rôle | Lien |
|---|---|---|
| **Il2CppDumper** | Extrait les noms de classes/méthodes C# du binaire Unity | https://github.com/Perfare/Il2CppDumper |
| **Ghidra** (gratuit) ou **IDA Pro** (payant) | Décompilation native des fonctions critiques | https://ghidra-sre.org/ |
| **dnSpy** | Naviguer dans les DLL .NET (utilitaires Ankama / launcher) | https://github.com/dnSpyEx/dnSpy |
| **Wireshark** | Capture réseau brut | https://www.wireshark.org/ |
| **mitmproxy** | MITM TLS avec injection de certificat | https://mitmproxy.org/ |
| **Frida** | Hook dynamique de fonctions à l'exécution (alt à patch binaire) | https://frida.re/ |
| **Cheat Engine** | Inspect mémoire processus (utile pour trouver les buffers de packets) | https://www.cheatengine.org/ |

## 2. Dump du binaire Unity

Le client Dofus 3 est une app Unity IL2CPP. Les bytecodes C# sont compilés AOT en natif, mais Il2CppDumper restaure des headers C# lisibles à partir de :
- `GameAssembly.dll` (le binaire natif compilé depuis le C#)
- `global-metadata.dat` (la table de symboles)

Chemins typiques (à confirmer sur ta machine) :
```
C:\Users\<user>\AppData\Local\Ankama\Dofus-dofus3\Dofus_Data\il2cpp_data\Metadata\global-metadata.dat
C:\Users\<user>\AppData\Local\Ankama\Dofus-dofus3\GameAssembly.dll
```

Procédure :

```pwsh
# 1. Lance Il2CppDumper en pointant les 2 fichiers
.\Il2CppDumper.exe path\to\GameAssembly.dll path\to\global-metadata.dat .\out

# 2. Tu obtiens dans .\out :
#    - DummyDll/  : fausses DLL .NET avec les signatures (chargeables dans dnSpy)
#    - dump.cs    : un gros C# avec toutes les classes
#    - script.json + script.py : pour Ghidra/IDA, mappe les adresses → noms
```

Charge `dump.cs` dans VSCode et grep des mots-clés utiles :
- `ProtocolMessageType` → enum des IDs de packets
- `FmAction` / `Forgemagie` / `Crafting` → classes liées à la FM
- `NetworkMessage` → base class des packets
- `BinaryReader` / `BinaryWriter` → sérialiseur

## 3. Capture réseau

Lance Dofus dans une fenêtre, puis Wireshark sur `Adapter` qui voit le trafic :

- Filter : `ip.dst == <ip-server-ankama>` (résolu via `nslookup` du domaine login Ankama)
- Port serveur historique D2 : `443` (HTTPS) + `5555` (binary tcp). En D3 c'est probablement **tout TLS sur 443**.

Tu verras du TLS chiffré uniquement à ce stade. Pour décrypter, 3 options :

### Option A — TLS bypass via patch binaire (le plus stable, le plus invasif)

Trouve dans Ghidra la fonction de validation de certificat (typiquement `Mono.Security.Protocol.Tls` ou une équivalente Unity), `nop`-out le check. Recompile et lance avec un proxy MITM en clair.

### Option B — mitmproxy + certificat injecté

```pwsh
# 1. Lance mitmproxy
mitmweb --listen-port 8080

# 2. Installe son cert dans le store de Windows (mitmproxy/cert/mitmproxy-ca-cert.pem)
# 3. Setup proxy système Windows ou variables d'env PROXY_HTTPS=http://127.0.0.1:8080
# 4. Lance Dofus. Si pin certif → Option A.
```

### Option C — Hook SSL_read / SSL_write avec Frida

```js
// dofus-hook.js — interceptor sur la function Mono SSL
Interceptor.attach(Module.findExportByName(null, "SSL_read"), {
  onLeave(retval) {
    if (retval.toInt32() > 0) {
      const buf = this.context.r1; // selon l'archi
      const data = Memory.readByteArray(buf, retval.toInt32());
      send({ direction: "in", len: retval.toInt32() }, data);
    }
  }
});
```

```pwsh
frida -l dofus-hook.js -f path\to\Dofus.exe
```

Cette option capture en clair les bytes avant chiffrement — c'est ce qui marche le mieux sur Unity AOT.

## 4. Identifier les packets MVP

Une fois le trafic en clair, scénarios à observer dans cet ordre :

1. **Login** (login + sélection serveur + sélection perso)
   - Quelques packets d'auth, plusieurs `ServerOptInformationMessage`, etc.
   - Pas critiques pour le MVP FM, mais nécessaires pour connecter le bot.

2. **Ouverture établi de FM**
   - Tu cliques sur un PNJ FM ou ton tabouret personnel.
   - Capture le `ExchangeStartedMessage` (ou équivalent D3).

3. **Sélection d'un item dans l'établi** → `ItemSelectedPacket`
   - Capture l'ID exact du packet + champs.
   - Note dans `docs/PROTOCOL_NOTES.md`.

4. **Pose d'une rune** → `FmActionPacket`
   - Drag-drop de la rune sur l'item.
   - Le client envoie un packet, le serveur en renvoie un.

5. **Résultat de la pose** → `FmResultPacket`
   - Probablement `ExchangeCraftResultMessage` + `ObjectModifiedMessage`.
   - C'est la combinaison de ces 2 qui dit "SC / SN / EC" + nouvelle valeur de stat.

6. **Mise à jour du reliquat**
   - Probablement embarqué dans `ObjectModifiedMessage` ou un message dédié.

## 5. Mapper les IDs dans MagusBot.Network

Une fois les packets identifiés, remplis :

```csharp
// MagusBot.Network/Messages/FmActionPacket.cs
public override ushort PacketId => 0xABCD; // l'ID trouvé via dump

// MagusBot.Network/Codec/PacketRegistry.cs (Cli ou Init)
var registry = new PacketRegistry();
registry.Register(() => new FmResultPacket { ... });
```

## 6. Implémenter PacketCodec

Le format binaire Dofus historique :

```
+--------+--------+--------+--------+
| len_hi | len_lo | type_hi| type_lo|
+--------+--------+--------+--------+
|          payload (len bytes)      |
+-----------------------------------+
```

À vérifier en D3 : il y a sûrement une couche supplémentaire (versioning, sequence id, peut-être encryption symétrique). Cherche dans le dump le nom de la classe qui appelle `NetworkSocket.Send` — c'est là qu'est le serializer.

Construis `PacketCodec.Encode` et `.Decode` pour matcher exactement ce que fait le client Dofus, sinon le serveur va te kicker.

## 7. Tester en MITM avant de bot

Avant de connecter `DofusGameClient` direct au serveur (high-risk), valide le decoder :

1. Capture une trace de session FM réelle (en MITM passif uniquement)
2. Décode-la avec ton `PacketCodec` → vérifie que tu sors les bons SC/SN/EC
3. Compare avec ce que tu as observé à l'écran

Si tu décodes correctement 100% des packets observés sur 1h de session, tu peux ensuite tenter le mode "actif" (envoyer un packet via le bot).

## 8. Risques de ban et atténuation

- **N'utilise jamais ton compte principal.**
- Bot uniquement sur un compte secondaire à valeur quasi nulle.
- Limite le nombre d'actions à des cadences humaines (1 action / 1-3s avec jitter).
- Ne fais jamais 24h non-stop — sessions de 30-60 min avec pauses.
- Ankama détecte aussi le patterning des actions (toujours la même milliseconde,
  toujours la même séquence) → ajoute jitter + variation.
- Si tu te fais ban, recommence à zéro et reviens en mode MITM passif uniquement
  pour comprendre ce qui t'a trahi.

## 9. Ressources

- **Repos GitHub historiques (Dofus 2)** — pour comprendre la structure générale,
  même si les IDs sont différents en D3 :
  - `darckoune/fm_assistant` (parsing puits/reliquat, déjà utilisé par le projet Swift)
  - `Aegisub/zaap` (client Dofus 2 open source)
  - `Dofus2.0-rust-emulator` (réimpl serveur, utile pour comprendre la sémantique)
- **Discord** : il existe des communautés de RE Dofus, demande sur les serveurs
  d'aide bot/scripting. Ne partage jamais tes credentials.
- **Documentation Il2CppDumper** : https://github.com/Perfare/Il2CppDumper/wiki
- **mitmproxy docs** : https://docs.mitmproxy.org/stable/

## 10. Checklist "bot fonctionnel"

- [ ] Il2CppDumper a généré `dump.cs` exploitable
- [ ] Tu as un MITM passif qui décrypte le trafic
- [ ] Tu as identifié les 3 packets MVP (`ItemSelected`, `FmAction`, `FmResult`)
- [ ] `PacketCodec.Encode` produit le même output que le client réel pour ces 3 packets
- [ ] `PacketCodec.Decode` parse correctement 100% des packets capturés
- [ ] `DofusGameClient` se connecte avec succès au serveur en lecture seule
- [ ] `DofusGameClient` peut envoyer un `FmActionPacket` et recevoir le résultat
- [ ] La boucle CLI tourne 30 min sans crash sur un compte test
- [ ] Le bot a fait au moins un jet parfait sans intervention humaine

Une fois ces points cochés, c'est l'heure d'ajouter l'UI WPF/Avalonia et les
features avancées (queue de presets, alertes sonores, exports JSON, etc.).
