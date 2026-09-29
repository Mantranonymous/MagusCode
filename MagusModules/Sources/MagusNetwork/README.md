# MagusNetwork — observation passive du trafic Dofus

Module **expérimental** ajouté à Magus en Phase 25. Sa raison d'être tient en
une phrase :

> **Décoder les paquets Protobuf entre Dofus et les serveurs Ankama pour
> reconstruire l'état exact de la session de forgemagie — sans jamais
> modifier ni forger un seul paquet.**

Le `ClickEngine` continue de cliquer comme avant. Seule la source d'information
de Magus change : on remplace progressivement les snapshots OCR (qui peuvent
foirer sur des polices fines, des couleurs identiques, etc.) par des snapshots
issus des events serveur (qui sont parfaits par construction).

## À quoi ça sert

- **OCR seul** : Magus voit ce qui est *affiché* à l'écran. Si l'image est
  blurry ou si une rune est mal collée à un nombre, la valeur lue est fausse.
  Conséquences : décisions erronées, click sur la mauvaise stat, sessions qui
  tournent en rond.
- **Observation réseau** : Magus voit directement les events serveur
  (`ExchangeCraftResultEvent`, `ExchangeObjectsModifiedEvent`, etc.) qui
  contiennent les valeurs exactes au bit près.
- **Hybride** : par défaut on garde l'OCR pour les champs hors couverture
  réseau (niveau métier, runes en inventaire visuel, etc.). Le réseau prend
  la priorité sur ce qu'il fournit.

## Ce que ce module NE FAIT PAS

Cadre strict, à respecter scrupuleusement :

- **N'envoie jamais de paquet au serveur.** Il n'existe pas de `PacketSender`,
  pas d'API qui forge des paquets. Si tu vois quelqu'un en ajouter, c'est un
  bug à refuser en review.
- **Ne modifie jamais un paquet en transit.** Le proxy est strictement
  forward-only : chaque byte client → byte serveur, et vice-versa, à
  l'identique.
- **Ne contourne pas l'authentification.** On observe le flux qui passe ;
  on ne réimplemente pas le login.
- **Ne remplace pas le `ClickEngine`.** Les actions restent simulées via
  input clavier/souris exactement comme avant.

Magus reste un "assistant" qui clique pour toi — pas un bot qui parle au
serveur à ta place.

## Architecture

```
Dofus.app (process spawné par Frida)
    │
    │ libc connect() hook
    │ (sockaddr réécrite : serveur réel → 127.0.0.1:7975)
    ▼
DofusProxy (NWListener TCP, port 7975)
    │
    │ forward bidirectionnel transparent
    ▼
Vrai serveur Ankama
```

Et côté observation (side-channel) :

```
Bytes observés (par sens)
    │
    ▼
PacketFramer (varint ou uint32BE, auto-switch)
    │
    │ frames Protobuf délimitées
    ▼
PacketDecoder (Message envelope → DecodedMessage)
    │
    ▼
NetworkStateBuilder (events → GameStateSnapshot)
    │
    ▼
AppState.lastParsedSnapshot (merge avec OCR)
```

## Setup utilisateur

Une seule fois après avoir cloné le repo :

```bash
# 1. Outils Protobuf
brew install protobuf swift-protobuf

# 2. Générer les .pb.swift à partir des .proto Ankama
cd /Users/simonyeche/Desktop/perso/MagusCode/MagusModules/Sources/MagusNetwork/Protos
./generate.sh

# 3. Installer le helper Frida (Node.js)
cd ../Frida
npm install

# 4. Re-build Magus dans Xcode (les .pb.swift sont maintenant compilés)

# 5. Lancer Magus → Préférences → "Observation réseau passive" → toggle ON
#    → bouton "Tester" pour vérifier que Frida arrive bien à spawn Dofus.
```

## Troubleshooting

| Symptôme | Diagnostic | Fix |
|---|---|---|
| `node not found` | Node.js absent | `brew install node` |
| `Package frida non installé` | `node_modules/frida` absent | `cd Sources/MagusNetwork/Frida && npm install` |
| `Frida a refusé l'attachement à Dofus` | SIP actif + hardened runtime | Soit `csrutil enable --without debug` en Recovery, soit accepter de tourner sans le mode réseau (l'OCR continue de marcher) |
| `Dofus introuvable à <path>` | Mauvais chemin dans Préférences | Corriger dans Préférences → champ "Chemin Dofus" |
| Aucun paquet observé | Dofus pas lancé via Frida | Le helper DOIT *spawn* Dofus, pas s'attacher à une instance déjà ouverte. Ferme Dofus, retoggle Observation OFF/ON. |
| Decode error sur tous les paquets | Mauvais framing | Le framer auto-switch varint ↔ uint32BE après 3 échecs. Si ça ne marche toujours pas, il y a probablement du TLS opaque (rare en Dofus 3 Unity) → ouvre une issue. |
| Magus crash quand on toggle ON | Voir Console.app, filtre `com.magus.network` | … |

## Limites connues du scaffolding actuel

État au **2026-05-22** (Phase 25) :

- Les fichiers `.pb.swift` ne sont **pas commit**. Tu dois lancer
  `generate.sh` une fois. Tant que ce n'est pas fait, `PacketDecoder` fait
  du best-effort sur les bytes bruts (extraction du `type_url` ASCII) et
  `NetworkStateBuilder` ne hydrate aucun champ.
- Le préambule `CONNECT host:port\r\n\r\n` envoyé par le hook Frida n'est
  pas encore généré côté Frida (l'`Interceptor` n'a pas accès direct au fd
  dans `onLeave`). Solution actuelle : on capture l'host original via les
  logs `[FRIDA] CONNECT …` que Magus lit, et on associe par ordre d'arrivée
  des connexions au proxy. Suffisant pour 1 personnage, 1 session.
- Pas de support TLS. Si Dofus 3 chiffre les paquets game, le framer va
  voir du bruit et auto-switch en boucle. À confirmer en testant en réel.
- Pas de support IPv6 (le hook ne touche que `AF_INET`).

## Files créés en Phase 25

- `Sources/MagusNetwork/Protos/clear/connection/message.proto` (téléchargé)
- `Sources/MagusNetwork/Protos/clear/game/{message,exchange,common,inventory,basic,context,character}.proto` (téléchargés)
- `Sources/MagusNetwork/Protos/generate.sh` (script)
- `Sources/MagusNetwork/Protos/Generated/_README.md` (instructions)
- `Sources/MagusNetwork/Proxy/{DofusProxy,ProxyConnection,PacketFramer}.swift`
- `Sources/MagusNetwork/Decoder/{PacketDecoder,DecodedMessage,MessageStream}.swift`
- `Sources/MagusNetwork/State/{NetworkStateBuilder,PacketLog}.swift`
- `Sources/MagusNetwork/Integration/{FridaHelper,NetworkObserver}.swift`
- `Sources/MagusNetwork/Frida/{frida-spawn-dofus.js,package.json,README.md}`
- `Sources/MagusNetwork/README.md` (ce fichier)
