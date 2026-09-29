#!/usr/bin/env bash
#
# generate.sh — Compile les .proto Dofus (sous-dossier `clear/`) en Swift via `protoc`.
#
# Usage :
#   1. Installe les binaires :
#        brew install protobuf swift-protobuf
#   2. Lance ce script depuis le dossier `Protos/` :
#        cd MagusModules/Sources/MagusNetwork/Protos
#        ./generate.sh
#   3. Les fichiers `*.pb.swift` apparaissent dans `Generated/`.
#   4. Re-build Magus dans Xcode pour les inclure.
#
# Si tu ajoutes ou modifies des .proto, ré-exécute ce script.
#
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v protoc >/dev/null 2>&1; then
    echo "ERREUR : protoc introuvable."
    echo "Installe-le via : brew install protobuf"
    exit 1
fi

if ! command -v protoc-gen-swift >/dev/null 2>&1; then
    echo "ERREUR : protoc-gen-swift introuvable."
    echo "Installe-le via : brew install swift-protobuf"
    exit 1
fi

mkdir -p Generated

# Les imports dans les .proto Dofus sont relatifs au dossier (ex: `import "common.proto"`
# depuis basic.proto, où common.proto est dans le même dossier). On passe donc
# `--proto_path=clear/game` pour que les imports inter-game résolvent correctement.
#
# **Note** : on n'inclut PAS `clear/connection/message.proto` ici car (1) protoc
# refuse avec "Input is shadowed in the --proto_path" si on combine les deux dossiers,
# (2) le code Swift n'utilise actuellement aucun type de connection — uniquement les
# events FM (game/exchange/...). Si on a besoin un jour des types connection, on
# fera un second invocation protoc séparée avec son propre proto_path.
protoc \
    --swift_out=Generated \
    --swift_opt=Visibility=Public \
    --proto_path=clear/game \
    clear/game/basic.proto \
    clear/game/character.proto \
    clear/game/common.proto \
    clear/game/context.proto \
    clear/game/exchange.proto \
    clear/game/inventory.proto \
    clear/game/message.proto

echo "OK — fichiers .pb.swift générés dans Generated/"
ls -1 Generated/
