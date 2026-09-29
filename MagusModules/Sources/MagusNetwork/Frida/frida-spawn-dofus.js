#!/usr/bin/env node
/*
 * frida-spawn-dofus.js
 *
 * Spawn Dofus.app et hook libc `connect()` pour rediriger toute connexion TCP
 * sortante vers un proxy local Magus. Le proxy est forward-only (observation
 * passive), donc Dofus continue de communiquer normalement avec ses serveurs.
 *
 * Format des logs stdout (Magus parse ces lignes) :
 *   [FRIDA] PID:<pid>                  → process spawné
 *   [FRIDA] HOOK:connect installed
 *   [FRIDA] CONNECT <ip>:<port> → 127.0.0.1:<proxyPort>
 *   [FRIDA] ERROR: <message>
 *
 * Usage :
 *   node frida-spawn-dofus.js --port 7975 \
 *     [--dofus /Applications/Ankama/Dofus-dofus3/Dofus.app/Contents/MacOS/Dofus]
 *
 * Permissions macOS :
 *   - Frida attache à un process Apple → peut nécessiter `csrutil disable`
 *     en Recovery sur les Mac Apple Silicon (hardened runtime).
 *   - À défaut : Magus continue de marcher en mode OCR-seul, ce module est
 *     un bonus de précision.
 */
// **ESM** : frida v16+ et commander v11+ sont distribués en ES Modules.
// `package.json` doit avoir `"type": "module"` pour que ce fichier soit interprété
// comme ESM (ce qui permet le top-level `import`).

let frida;
let program;
try {
    const fridaModule = await import('frida');
    frida = fridaModule.default ?? fridaModule;
    const commanderModule = await import('commander');
    program = commanderModule.program ?? commanderModule.default?.program;
} catch (err) {
    console.error('[FRIDA] ERROR: package introuvable (' + (err?.message ?? err) + '). Lance `npm install` dans Sources/MagusNetwork/Frida/');
    process.exit(2);
}

if (!program) {
    console.error('[FRIDA] ERROR: impossible de charger commander.program');
    process.exit(2);
}

program
    .option(
        '--target <name>',
        'Nom du process Dofus à attacher (recherche par nom)',
        'Dofus'
    )
    .option(
        '--min-bytes <n>',
        'Ignore les chunks send/recv de moins de N octets (réduit le bruit)',
        '4'
    )
    .parse(process.argv);

const opts = program.opts();
const targetName = opts.target;
const minBytes = parseInt(opts['minBytes'] ?? opts.minBytes ?? '4', 10);

// Script Frida injecté dans Dofus (déjà en cours d'exécution).
// On hook libc `send()` et `recv()` sur les sockets AF_INET pour observer le
// trafic réseau **sans le modifier**. Chaque chunk est sérialisé en base64 et
// renvoyé au process Node via `send(...)` Frida, qui l'écrit sur stdout au
// format `[PKT <dir> fd=<n> len=<n>] <base64>`.
//
// **Forward-only, passif** : on ne réécrit rien, on ne forge rien, on n'envoie
// rien au serveur. Juste de l'observation.
//
// Signatures libc Darwin :
//   ssize_t send(int sockfd, const void *buf, size_t len, int flags);
//   ssize_t recv(int sockfd, void *buf, size_t len, int flags);
//
// Pour réduire le bruit (DNS, keepalive vides, ...) on filtre :
//   - taille minimum (`MIN_BYTES`)
//   - sockets non-AF_INET (vérifié via getsockname)
const fridaScript = `
'use strict';

const MIN_BYTES = ${minBytes};
const AF_INET = 2;

// Cache des sockets connus AF_INET pour éviter un getsockname() à chaque send/recv.
const inetSockets = new Set();
// Cache des sockets non-AF_INET (UNIX, IPv6, autres) pour les rejeter rapidement.
const skipSockets = new Set();

// Helpers
function bytesToBase64(arrBuf) {
    const bytes = new Uint8Array(arrBuf);
    let binary = '';
    for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i]);
    }
    return btoa ? btoa(binary) : Buffer.from(bytes).toString('base64');
}

// getsockname(sockfd, sockaddr, &len) → détecte AF_INET
const getsocknamePtr = Module.findExportByName(null, 'getsockname');
let getsockname = null;
if (getsocknamePtr) {
    getsockname = new NativeFunction(getsocknamePtr, 'int', ['int', 'pointer', 'pointer']);
}

function isInetSocket(sockfd) {
    if (inetSockets.has(sockfd)) { return true; }
    if (skipSockets.has(sockfd)) { return false; }
    if (!getsockname) { return true; } // pas de filtrage possible
    const addr = Memory.alloc(128);
    const len = Memory.alloc(4);
    len.writeU32(128);
    const r = getsockname(sockfd, addr, len);
    if (r !== 0) { skipSockets.add(sockfd); return false; }
    const family = addr.add(1).readU8(); // sa_family sur Darwin (octet 1 après sin_len)
    if (family === AF_INET) { inetSockets.add(sockfd); return true; }
    skipSockets.add(sockfd);
    return false;
}

function dumpBytes(direction, sockfd, bufPtr, length) {
    if (length < MIN_BYTES) { return; }
    if (!isInetSocket(sockfd)) { return; }
    const data = bufPtr.readByteArray(length);
    if (data === null) { return; }
    const b64 = bytesToBase64(data);
    send('[PKT ' + direction + ' fd=' + sockfd + ' len=' + length + '] ' + b64);
}

// Hook send()
const sendPtr = Module.findExportByName(null, 'send');
if (sendPtr === null) {
    send('[FRIDA] ERROR: send() introuvable');
} else {
    Interceptor.attach(sendPtr, {
        onEnter: function (args) {
            this.sockfd = args[0].toInt32();
            this.bufPtr = args[1];
            this.length = args[2].toInt32();
        },
        onLeave: function (retval) {
            const sent = retval.toInt32();
            if (sent <= 0) { return; }
            dumpBytes('OUT', this.sockfd, this.bufPtr, sent);
        }
    });
    send('[FRIDA] HOOK:send installed');
}

// Hook recv()
const recvPtr = Module.findExportByName(null, 'recv');
if (recvPtr === null) {
    send('[FRIDA] ERROR: recv() introuvable');
} else {
    Interceptor.attach(recvPtr, {
        onEnter: function (args) {
            this.sockfd = args[0].toInt32();
            this.bufPtr = args[1];
        },
        onLeave: function (retval) {
            const received = retval.toInt32();
            if (received <= 0) { return; }
            dumpBytes('IN', this.sockfd, this.bufPtr, received);
        }
    });
    send('[FRIDA] HOOK:recv installed');
}

// Hook close() pour cleanup du cache (sinon mémoire qui grandit)
const closePtr = Module.findExportByName(null, 'close');
if (closePtr) {
    Interceptor.attach(closePtr, {
        onEnter: function (args) {
            const fd = args[0].toInt32();
            inetSockets.delete(fd);
            skipSockets.delete(fd);
        }
    });
}

send('[FRIDA] READY');
`;

async function findTargetPid(name) {
    // Frida v16 expose les processus via le Device (local en l'occurrence)
    const device = await frida.getLocalDevice();
    const processes = await device.enumerateProcesses();

    // Préfère le match EXACT (ex: "Dofus") sur le match partiel
    // (ex: "AutoFill (Dofus)" est un helper macOS, pas Dofus lui-même).
    const exactMatches = processes.filter(p => p.name === name);
    if (exactMatches.length > 0) {
        if (exactMatches.length > 1) {
            console.error('[FRIDA] WARN: ' + exactMatches.length + ' process "' + name + '" exacts — utilise le premier');
            exactMatches.forEach(p => console.error('  - PID ' + p.pid + ' / ' + p.name));
        }
        return exactMatches[0];
    }

    // Fallback : match partiel, en excluant les helpers macOS connus.
    const partial = processes.filter(p => {
        if (p.name === name) return true;
        if (!p.name.includes(name)) return false;
        // Exclut les helpers/parenthèses (`AutoFill (Dofus)`, `Dofus Helper (Renderer)`...).
        const lower = p.name.toLowerCase();
        if (lower.includes('autofill') || lower.includes('helper') || lower.startsWith('com.apple')) {
            return false;
        }
        return true;
    });
    if (partial.length === 0) {
        return null;
    }
    if (partial.length > 1) {
        console.error('[FRIDA] WARN: ' + partial.length + ' process matchent "' + name + '" (partiels) — utilise le premier');
        partial.forEach(p => console.error('  - PID ' + p.pid + ' / ' + p.name));
    }
    return partial[0];
}

async function main() {
    let session;
    let pid;
    try {
        const target = await findTargetPid(targetName);
        if (!target) {
            console.error('[FRIDA] ERROR: aucun process "' + targetName + '" trouvé. Lance Dofus d\'abord puis relance ce script.');
            process.exit(5);
        }
        pid = target.pid;
        console.log('[FRIDA] PID:' + pid + ' (' + target.name + ')');
        session = await frida.attach(pid);
        const script = await session.createScript(fridaScript);
        script.message.connect((message) => {
            if (message.type === 'send') {
                console.log(message.payload);
            } else if (message.type === 'error') {
                console.error('[FRIDA] ERROR: ' + (message.description || JSON.stringify(message)));
            }
        });
        await script.load();
    } catch (err) {
        console.error('[FRIDA] ERROR: ' + (err && err.message ? err.message : String(err)));
        if (err && /code-?sign|not allowed|permission/i.test(String(err))) {
            console.error('[FRIDA] ERROR: Attach refusé. Possible cause : SIP / hardened runtime / TCC.');
            console.error('[FRIDA] HINT: essaye `sudo node frida-spawn-dofus.js --target ' + targetName + '`');
        }
        process.exit(4);
    }

    const cleanup = async (signal) => {
        console.log('[FRIDA] STOPPING (' + signal + ')');
        try {
            if (session) { await session.detach(); }
        } catch (_) { /* ignore */ }
        process.exit(0);
    };
    process.on('SIGINT', () => cleanup('SIGINT'));
    process.on('SIGTERM', () => cleanup('SIGTERM'));
}

main();
