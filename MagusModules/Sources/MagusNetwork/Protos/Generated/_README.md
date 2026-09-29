# Generated/ — output de protoc

Ce dossier accueille les fichiers `*.pb.swift` produits par `protoc-gen-swift`
à partir des `.proto` dans `../clear/`.

## Comment générer

Depuis le dossier `Protos/` :

```bash
brew install protobuf swift-protobuf
./generate.sh
```

Tu devrais voir apparaître ici plusieurs fichiers de la forme :

- `connection/message.pb.swift`
- `game/message.pb.swift`
- `game/exchange.pb.swift`
- `game/common.pb.swift`
- `game/basic.pb.swift`
- `game/context.pb.swift`
- `game/character.pb.swift`
- `game/inventory.pb.swift`

## Pourquoi rien n'est commit ici

Le code généré est volumineux (~30k lignes) et redondant avec les `.proto` sources.
Chaque dev qui clone le repo lance `./generate.sh` une fois.

Le SPM target `MagusNetwork` exclut `clear/`, `generate.sh` et ce `_README.md` du
compile path : seuls les `.pb.swift` ici présents seront compilés.

## TODO une fois `protoc` lancé

Dans `MagusNetwork/Decoder/PacketDecoder.swift`, remplacer les placeholders
`Data`-brut par les vrais types Swift générés :

- `Com_Ankama_Dofus_Server_Game_Protocol_Message`
- `Com_Ankama_Dofus_Server_Connection_Protocol_Message`
- `Com_Ankama_Dofus_Server_Game_Protocol_Exchange_ExchangeCraftResultEvent`
- `Com_Ankama_Dofus_Server_Game_Protocol_Exchange_ExchangeObjectsModifiedEvent`
- `Com_Ankama_Dofus_Server_Game_Protocol_Exchange_ExchangeObjectsAddedEvent`
- `Com_Ankama_Dofus_Server_Game_Protocol_Exchange_ExchangeRunesTradeStartedEvent`
- `Com_Ankama_Dofus_Server_Game_Protocol_Exchange_ExchangeLeaveEvent`
- `Com_Ankama_Dofus_Server_Game_Protocol_Common_ObjectItemInventory`
- `Com_Ankama_Dofus_Server_Game_Protocol_Common_ObjectItem`
- `Com_Ankama_Dofus_Server_Game_Protocol_Common_ObjectEffect`

Les noms exacts dépendent de la casse appliquée par `protoc-gen-swift` —
ouvre un `.pb.swift` généré pour confirmer.
