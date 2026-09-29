# MagusBot.Network

Couche réseau du bot — **scaffold seulement**.

## État

| Composant | État | Note |
|---|---|---|
| `IGameClient` | Stable | Interface haut-niveau utilisée par CLI/UI. |
| `Stub/StubGameClient` | Complet | Simule item + résultats aléatoires pour tester la logique. |
| `Messages/Packet` (abstract) | Stub | Base class prête, IDs à RE. |
| `Messages/ItemSelectedPacket` | Stub | TODO RE : packet ID + champs. |
| `Messages/FmActionPacket` | Stub | TODO RE. |
| `Messages/FmResultPacket` | Stub | TODO RE. |
| `Codec/PacketCodec` | TODO | Encoding/decoding binaire à reverse. |
| `Codec/PacketRegistry` | Squelette | Prêt à recevoir les IDs découverts. |

## Pour démarrer le RE

Voir [`docs/REVERSE_ENGINEERING.md`](../../docs/REVERSE_ENGINEERING.md) à la racine du projet.
La cible logique pour la première itération du bot fonctionnel :

1. Faire passer un login + sélection de perso (sans logique métier)
2. Capturer un packet de pose de rune réel pour identifier `FmActionPacket`
3. Capturer le résultat pour identifier `FmResultPacket`
4. Une fois ces 3 IDs connus + sérialisation propre, swap
   `StubGameClient` par `DofusGameClient` dans la CLI.

## Avertissements

- **Toujours tester sur un compte secondaire** : Ankama bannit régulièrement les bots.
- **MITM passif d'abord** : observe sans modifier les packets pendant 1-2 semaines pour
  réduire le risque de pattern de détection.
- **Pas de rejouer brut** : le serveur a probablement des nonces/timestamps qui
  détecteront le replay.
