#!/usr/bin/env python3
"""Convertit un .efitem (ExoFast) en JSON .magus (Magus).

Logique alignée avec MagusModules/Sources/MagusPersistence/EfitemImporter.swift.
Format binaire ExoFast :
- [01 00 00 LEN] : header (LEN = longueur du nom)
- [name XOR-chain] : enc[0] = name[0] ^ LEN, enc[i] = name[i-1] ^ name[i]
- [préambule variable] : 16 bytes "standard" ou plus pour items lourds
- [stat blocks "01 01"] : marker + flag + eid (1 ou 2 bytes XOR-chain) + target

Mapping effect_id (Dofus) → characteristicId (DofusDB).
"""
import json
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

EFFECT_TO_CHARACTERISTIC = {
    # Source : DofusDB live (ref_effects table) — corrigé v2
    111: 1,    # PA
    112: 16,   # Dommages
    115: 18,   # % Critique
    117: 19,   # Portée
    118: 10,   # Force
    119: 14,   # Agilité
    123: 13,   # Chance
    124: 12,   # Sagesse
    125: 11,   # Vitalité
    126: 15,   # Intelligence
    128: 23,   # PM
    138: 25,   # Puissance
    158: 40,   # Pods
    160: 27,   # Esquive PA
    161: 28,   # Esquive PM
    163: 28,   # Esquive PM (variant)
    174: 44,   # Initiative
    176: 48,   # Prospection
    178: 49,   # Soins
    182: 26,   # Invocation
    # Résistances en % — ATTENTION ordre canonique DofusDB :
    # 210=Terre, 211=Eau, 212=Air, 213=Feu, 214=Neutre
    210: 33, 211: 35, 212: 36, 213: 34, 214: 37,
    # Résistances fixes — ATTENTION ordre canonique :
    # 240=Terre, 241=Eau, 242=Air, 243=Feu, 244=Neutre
    240: 54, 241: 56, 242: 57, 243: 55, 244: 58,
    # Dommages élémentaires :
    # 414=Poussée, 418=DoCri, 422=Terre, 424=Feu, 426=Eau, 428=Air
    414: 84, 418: 86, 422: 88, 424: 89, 426: 90, 428: 91,
    # Poussée fixe
    416: 85,
    # Tacle / Fuite
    752: 78, 753: 79, 755: 79,
}


def decode_xor_chain_name(enc: bytes, length: int) -> str:
    """enc[0] = name[0] ^ length, enc[i] = name[i-1] ^ name[i]"""
    if length == 0 or len(enc) < length:
        return ""
    decoded = bytearray(length)
    decoded[0] = enc[0] ^ (length & 0xFF)
    for i in range(1, length):
        decoded[i] = enc[i] ^ decoded[i - 1]
    try:
        return decoded.decode("utf-8")
    except UnicodeDecodeError:
        return decoded.decode("latin-1", errors="replace")


def parse_main_block(data: bytes, offset: int):
    """Parse bloc principal `01 01 00 [flag] ...`.
    - 1-byte eid (flag=00) : eid à [+4]==[+5]
    - 2-byte eid (flag=01) : eid = (data[+3] << 8) | data[+5]  (le flag EST le high byte !)
    - target = (data[+7] << 8) | min(data[+8], data[+9])  (XOR pair tolérant ±1)
    """
    if offset + 11 >= len(data):
        return None
    flag = data[offset + 3]
    if flag == 0x00:
        if data[offset + 4] != data[offset + 5] or data[offset + 4] == 0:
            return None
        eid = data[offset + 4]
    elif flag == 0x01:
        eid = (data[offset + 3] << 8) | data[offset + 5]
    else:
        return None
    th = data[offset + 7]
    t1, t2 = data[offset + 8], data[offset + 9]
    if t1 == t2:
        tl = t1
    elif abs(t1 - t2) == 1:
        tl = min(t1, t2)
    else:
        return None
    return (eid, (th << 8) | tl)


def parse_chain_mini(data: bytes, offset: int):
    """Parse mini-stat dans une chain (9 bytes après `13 9b 89 01`).
    Format : `00 00 EE EE 00 TH TL TL CONT` (CONT=01 → continue, 00 → fin).
    """
    if offset + 9 > len(data):
        return None
    if data[offset] != 0 or data[offset + 1] != 0:
        return None
    e1, e2 = data[offset + 2], data[offset + 3]
    if e1 == 0 or e1 != e2:
        return None
    if data[offset + 4] != 0:
        return None
    th = data[offset + 5]
    if th > 0x10:
        return None
    t1, t2 = data[offset + 6], data[offset + 7]
    if t1 == t2:
        tl = t1
    elif abs(t1 - t2) == 1:
        tl = min(t1, t2)
    else:
        return None
    return (e1, (th << 8) | tl, data[offset + 8])


def parse_efitem(path: Path):
    data = path.read_bytes()
    if len(data) < 5:
        raise ValueError("Fichier trop court")
    if not (data[0] == 0x01 and data[1] == 0x00 and data[2] == 0x00):
        raise ValueError("Header invalide")
    name_len = data[3]
    if len(data) < 4 + name_len + 1:
        raise ValueError("Fichier tronqué")
    name = decode_xor_chain_name(data[4:4 + name_len + 1], name_len)

    targets = {}
    debug_hits = []
    start = 4 + name_len + 1

    # Pass 1 — main blocks
    i = start
    while i + 11 < len(data):
        if data[i] == 0x01 and data[i + 1] == 0x01 and data[i + 2] == 0x00:
            parsed = parse_main_block(data, i)
            if parsed:
                eid, t = parsed
                char_id = EFFECT_TO_CHARACTERISTIC.get(eid)
                debug_hits.append(("MAIN", i, eid, t, char_id))
                if char_id and 0 < t < 5000:
                    targets[char_id] = t
            i += 19
        else:
            i += 1

    # Pass 2 — chains (13 9b 89 01 puis mini-stats)
    i = start
    while i + 4 < len(data):
        if data[i:i+4] == b'\x13\x9b\x89\x01':
            j = i + 4
            while j + 9 <= len(data):
                parsed = parse_chain_mini(data, j)
                if not parsed:
                    break
                eid, t, cont = parsed
                char_id = EFFECT_TO_CHARACTERISTIC.get(eid)
                debug_hits.append(("CHAIN", j, eid, t, char_id))
                if char_id and 0 < t < 5000 and char_id not in targets:
                    targets[char_id] = t
                j += 9
                if cont != 0x01:
                    break
            i = j
        else:
            i += 1

    return {"itemName": name, "targets": targets, "_debug": debug_hits}


CHARACTERISTIC_NAMES = {
    1: "PA", 10: "Force", 11: "Vitalité", 12: "Sagesse", 13: "Chance",
    14: "Agilité", 15: "Intelligence", 16: "Dommages", 18: "Critique",
    19: "Portée", 23: "PM", 25: "Puissance", 26: "Invocation",
    27: "Esquive PA", 28: "Esquive PM", 40: "Pods", 44: "Initiative",
    48: "Prospection", 49: "Soins", 54: "Résistance Terre",
    55: "Résistance Feu", 56: "Résistance Eau", 57: "Résistance Air",
    58: "Résistance Neutre", 33: "Résistance Terre %", 34: "Résistance Feu %",
    35: "Résistance Eau %", 36: "Résistance Air %", 37: "Résistance Neutre %",
    78: "Fuite", 79: "Tacle", 84: "Poussée", 85: "Poussée fixe",
    86: "Dommages Critiques", 88: "Dommages Terre", 89: "Dommages Feu",
    90: "Dommages Eau", 91: "Dommages Air",
}


def to_magus_preset(parsed: dict, source_file: str) -> dict:
    """Construit un JSON .magus.preset format v1 propre."""
    now_iso = datetime.now(timezone.utc).isoformat()
    targets = []
    for char_id, target in sorted(parsed["targets"].items()):
        targets.append({
            "characteristicId": char_id,
            "characteristicName": CHARACTERISTIC_NAMES.get(char_id, f"#{char_id}"),
            "target": target,
            "minimum": None,
            "priority": 100,
            "enabled": True,
        })
    return {
        "format": "magus.preset",
        "version": 1,
        "exportedAt": now_iso,
        "source": {
            "type": "efitem_conversion",
            "originalFile": source_file,
            "tool": "Presets/convert_efitem.py",
        },
        "item": {
            "name": parsed["itemName"],
            "dofusDbId": None,
        },
        "stats": {
            "id": str(uuid.uuid4()).upper(),
            "name": f"Importé ExoFast — {parsed['itemName']}",
            "scenario": "jetParfait",
            "itemSpecId": None,
            "targets": targets,
            "steps": [],
            "createdAt": now_iso,
            "updatedAt": now_iso,
        },
        "config": {
            "id": str(uuid.uuid4()).upper(),
            "name": "Rapide (règle ×20)",
            "defaultRule": {
                "useBase": True, "usePA": True, "useRA": True,
                "thresholdPA": 20, "thresholdRA": 60, "maxCanHit": 9999,
                "paValueThreshold": "always", "raValueThreshold": "always",
            },
            "alternateExoPAPM": False,
            "createdAt": now_iso,
            "updatedAt": now_iso,
        },
        "_efitem_notes": {
            "extractedFromBinary": len(targets),
            "missingFromBinary": "ExoFast n'exporte pas les stats négatives (Tacle, Esquive) ni les stats fixes 1-1 sans cible custom (Portée)",
        },
    }


def main():
    if len(sys.argv) < 3:
        print("Usage: convert_efitem.py <input.efitem> <output.json>")
        sys.exit(1)
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    parsed = parse_efitem(src)
    print(f"Item: {parsed['itemName']}")
    print(f"\nBlocs trouvés ({len(parsed.get('_debug', []))}) :")
    for kind, off, eid, t, char_id in parsed.get("_debug", []):
        marker = "✓" if char_id else "?"
        print(f"  [{kind:5s}] offset={off:3d} {marker} eid={eid:5d} t={t:4d} → char_id={char_id}")
    print(f"\nTargets retenus ({len(parsed['targets'])}) :")
    for char_id, t in sorted(parsed["targets"].items()):
        print(f"  characteristicId={char_id:3d} → target={t}")
    preset = to_magus_preset(parsed, source_file=src.name)
    dst.write_text(json.dumps(preset, indent=2, ensure_ascii=False, sort_keys=True))
    print(f"\n→ JSON écrit : {dst}")


if __name__ == "__main__":
    main()
