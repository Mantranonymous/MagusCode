# Frida helper — `magus-frida-helper`

Script Node.js qui spawn Dofus.app et installe un hook libc `connect()` pour
rediriger toute connexion TCP IPv4 sortante vers le proxy local Magus.

C'est de l'**observation passive** : aucun paquet n'est modifié ni forgé.
Le proxy fait juste suivre les bytes du client vers le serveur (et inversement)
en les inspectant côté.

## Install (une fois)

```bash
cd /Users/simonyeche/Desktop/perso/MagusCode/MagusModules/Sources/MagusNetwork/Frida
npm install
```

Cette étape télécharge le binaire natif Frida (~50 Mo) pour ton architecture.

## Lancer manuellement (debug)

```bash
node frida-spawn-dofus.js --port 7975 \
  --dofus /Applications/Ankama/Dofus-dofus3/Dofus.app/Contents/MacOS/Dofus
```

Magus lance ce script en sous-process via `FridaHelper.swift` — pas besoin de
le lancer à la main en usage normal.

## Permissions macOS

Frida attache à un process Apple. Sur Apple Silicon avec SIP actif et hardened
runtime, l'attachement peut être refusé.

Options par ordre de préférence :

1. **Ignorer le mode réseau** (fallback OCR) — Magus continue de marcher sans.
2. **Désactiver SIP partiellement** :
   - Redémarrer en Recovery (⌘+R au boot Intel, ou hold power on Apple Silicon)
   - Terminal → `csrutil enable --without debug`
   - Redémarrer
3. `sudo node frida-spawn-dofus.js …` — déconseillé (Dofus tourne alors en root,
   risque sécurité).

## Logs

Le script écrit sur stdout des lignes commençant par `[FRIDA] …`. Magus parse :

| Pattern | Sens |
|---|---|
| `[FRIDA] PID:<n>` | Dofus spawné, PID `n` |
| `[FRIDA] HOOK:connect installed` | Hook libc OK |
| `[FRIDA] CONNECT <ip>:<port> → 127.0.0.1:<proxy>` | Connexion redirigée |
| `[FRIDA] READY` | Tout est prêt |
| `[FRIDA] ERROR: …` | Erreur — voir message |
| `[FRIDA] STOPPING (<signal>)` | Cleanup en cours |

## Important

- **Ferme toute instance Dofus existante avant** d'activer le mode observation,
  car le helper doit *spawn* Dofus, pas s'attacher à un process déjà lancé.
- Le hook ne touche que IPv4 (AF_INET). IPv6 et UDP sont ignorés.
- L'envoi du préambule `CONNECT host:port HTTP/1.0\r\n\r\n` au proxy n'est pas
  implémenté côté Frida (Interceptor n'a pas accès direct au fd dans onLeave).
  Le `DofusProxy` swift utilise donc une stratégie alternative : il accepte la
  connexion et tente de reconstituer l'host depuis l'URI TLS (SNI) si HTTPS,
  ou utilise un cache PID→original-host alimenté par les logs Frida.
