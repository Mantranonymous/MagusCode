# Notes protocole Dofus 3

Document vivant : rempli au fur et à mesure du reverse engineering. Voir
[`REVERSE_ENGINEERING.md`](REVERSE_ENGINEERING.md) pour le workflow.

> Convention : pour chaque packet, note **direction**, **ID hex**, **nom Ankama**,
> et la **structure des champs** (avec leur offset / type / signification).

## Packets identifiés

### (Template — copier/coller pour chaque packet trouvé)

#### `ExempleNomPacket`
- **Direction** : Client → Server (ou Server → Client)
- **ID** : `0xABCD`
- **Nom Ankama** : `ExempleNomMessage`
- **Trigger observé** : décrire l'action qui déclenche l'envoi/réception
- **Structure** :
  | Offset | Type | Nom | Note |
  |---|---|---|---|
  | 0 | `uint16` | header | toujours `0xABCD` |
  | 2 | `varint` | itemUid | UID de l'item |
  | ? | `string` (len-prefixed) | label | optionnel |
- **Notes** : observations, edge cases, etc.

## Packets MVP à identifier en priorité

### `ItemSelectedPacket` (Client → Server)
- À TROUVER. Trigger : drag d'un item dans le slot d'établi FM.

### `FmActionPacket` (Client → Server)
- À TROUVER. Trigger : drag d'une rune sur l'item dans l'établi.

### `FmResultPacket` (Server → Client)
- À TROUVER. Trigger : après pose, contient SC/SN/EC + nouvelle valeur de stat.
- Probablement composé de 2 messages : `ExchangeCraftResultMessage` + `ObjectModifiedMessage`.

### `ReliquatUpdatePacket` (Server → Client ?)
- À TROUVER. Peut-être intégré dans `ObjectModifiedMessage`.

## Format wire général

- [ ] Header structure (length, type id, sequence id ?)
- [ ] Encryption (XOR clé fixe ? AES ? aucune ?)
- [ ] Endianness (big endian probable)
- [ ] Varint encoding pour les uints (à confirmer)
- [ ] String encoding (UTF-8 len-prefixed probable)

## IDs DofusDB observés vs envoyés sur le wire

Vérifier que les `characteristicId` envoyés/reçus correspondent exactement à ceux
de DofusDB qu'on utilise dans `StatKind` et `RuneWeights`. Sinon mapper.

| DofusDB (notre code) | Dofus client (wire) | Match ? |
|---|---|---|
| 1 — PA | ? | ? |
| 11 — Vitalité | ? | ? |
| 23 — PM | ? | ? |
| ... | ... | ... |

## Observations diverses

(Note ici tout ce qui peut servir : rate-limiting serveur, particularités de
session, fenêtres d'envoi, comportements bizarres, etc.)
