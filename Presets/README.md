# Presets

Centralise les configurations d'items de forgemagie pour Magus.

## Structure

```
Presets/
├── efitem/              # Configs ExoFast (format binaire propriétaire .efitem)
│   ├── Anneau de Padgref.efitem
│   ├── Anneau Chevelu.efitem
│   ├── Gant du Valet Veinard.efitem
│   └── Lavanneau.efitem
├── json/                # Configs Magus (format .magus.json, lisible et éditable)
│   └── Anneau de Padgref.json
└── convert_efitem.py    # Script de conversion .efitem → .magus.json
```

## Conversion .efitem → .magus.json

```bash
cd Presets
python3 convert_efitem.py "efitem/<nom_item>.efitem" "json/<nom_item>.json"
```

Le script :
1. Parse le binaire `.efitem` (header XOR-chain + blocs stat `01 01`)
2. Mappe les `effect_id` ExoFast vers les `characteristicId` DofusDB
3. Génère un JSON au format `magus.preset` v1

⚠ **Best-effort** : le parser des blocs 2-byte n'est pas 100% fiable. Stats fréquemment ratées : Dommages élémentaires, Résistances Air/Terre. Les valeurs parsées sont à valider manuellement après import.

## Import dans Magus

Depuis l'app :
- **Sidebar Bibliothèque** → bouton **"Importer JSON"** pour un `.magus.json`
- **Sidebar Bibliothèque** → bouton **"Importer .efitem"** pour un binaire ExoFast direct

## Format .magus.json

```json
{
  "format": "magus.preset",
  "version": 1,
  "exportedAt": "ISO8601",
  "stats": {
    "id": "UUID",
    "name": "Importé ExoFast — Anneau de Padgref",
    "scenario": "jetParfait",
    "targets": [
      { "characteristicId": 11, "target": 96, "priority": 100, "enabled": true }
    ]
  },
  "config": {
    "name": "Rapide (règle ×20)",
    "alternateExoPAPM": false
  }
}
```
