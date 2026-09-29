import Foundation
import os

private let logger = Logger(subsystem: "com.magus.network", category: "frida-helper")

/// Erreurs spécifiques au lancement du helper Frida.
public enum FridaError: Error, Sendable, CustomStringConvertible {
    case nodeNotFound
    case fridaPackageMissing(scriptDir: URL)
    case dofusNotFound(path: URL)
    case attachRefused(detail: String)
    case scriptNotFound(URL)
    case spawnFailed(reason: String)
    case helperExitedEarly(code: Int32, stderr: String)

    public var description: String {
        switch self {
        case .nodeNotFound:
            return "node introuvable. Installe-le via `brew install node`."
        case .fridaPackageMissing(let scriptDir):
            return "Package frida non installé. Lance `npm install` dans \(scriptDir.path)."
        case .dofusNotFound(let path):
            return "Dofus introuvable à \(path.path). Vérifie le chemin dans les Préférences."
        case .attachRefused(let detail):
            return "Frida a refusé l'attachement à Dofus. Détail : \(detail). Possible cause : SIP / hardened runtime."
        case .scriptNotFound(let url):
            return "Script Frida introuvable : \(url.path)"
        case .spawnFailed(let reason):
            return "Lancement de node a échoué : \(reason)"
        case .helperExitedEarly(let code, let stderr):
            return "Helper Frida terminé prématurément (code \(code)). stderr : \(stderr)"
        }
    }
}

/// Spawn le sous-process Node.js qui hook libc `connect()` dans Dofus pour
/// rediriger le trafic vers le proxy local.
///
/// `FridaHelper` est volontairement minimal : il ne fait que lancer le script,
/// parser les lignes `[FRIDA] …` sur stdout et exposer un callback pour
/// notifier le caller des événements importants (PID, READY, ERROR).
@MainActor
public final class FridaHelper {

    /// Événements émis par le script Node sur stdout.
    public enum Event: Sendable {
        case pid(Int32)
        case hookInstalled
        case connectRedirected(originalHost: String, originalPort: UInt16)
        case ready
        case error(String)
        case stopping(signal: String)
        case rawLine(String)
    }

    public private(set) var process: Process?
    public private(set) var helperPid: Int32?
    public var onEvent: ((Event) -> Void)?

    private let scriptDirectory: URL

    /// - Parameter scriptDirectory: dossier qui contient `frida-spawn-dofus.js`
    ///   et `package.json`. Par défaut, on cherche dans le bundle de l'app
    ///   sous `MagusNetwork/Frida/`.
    public init(scriptDirectory: URL) {
        self.scriptDirectory = scriptDirectory
    }

    /// Démarre le helper. Lance node + le script + injecte les paramètres.
    /// Throw une `FridaError` typée si quelque chose manque.
    public func start(proxyPort: UInt16, dofusPath: URL?) async throws {
        if process != nil {
            logger.warning("FridaHelper already running, stopping previous instance")
            stop()
        }

        let nodePath = try Self.locateNode()
        let scriptURL = scriptDirectory.appendingPathComponent("frida-spawn-dofus.js")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw FridaError.scriptNotFound(scriptURL)
        }
        let nodeModules = scriptDirectory.appendingPathComponent("node_modules/frida")
        guard FileManager.default.fileExists(atPath: nodeModules.path) else {
            throw FridaError.fridaPackageMissing(scriptDir: scriptDirectory)
        }
        let resolvedDofus = dofusPath ?? URL(fileURLWithPath: "/Applications/Ankama/Dofus-dofus3/Dofus.app/Contents/MacOS/Dofus")
        guard FileManager.default.fileExists(atPath: resolvedDofus.path) else {
            throw FridaError.dofusNotFound(path: resolvedDofus)
        }

        let process = Process()
        process.currentDirectoryURL = scriptDirectory
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [
            scriptURL.path,
            "--port", String(proxyPort),
            "--dofus", resolvedDofus.path,
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let onEvent = self.onEvent
        Self.readLines(from: stdoutPipe.fileHandleForReading) { line in
            Task { @MainActor in
                let event = FridaHelper.parseEvent(line: line)
                onEvent?(event)
                if case let .pid(pid) = event {
                    // Capture le PID pour debug
                    Task { @MainActor in
                        FridaHelper.lastReportedPid = pid
                    }
                }
            }
        }
        Self.readLines(from: stderrPipe.fileHandleForReading) { line in
            Task { @MainActor in
                let event = FridaHelper.parseEvent(line: line)
                onEvent?(event)
            }
        }

        do {
            try process.run()
        } catch {
            throw FridaError.spawnFailed(reason: String(describing: error))
        }
        self.process = process
        logger.info("FridaHelper spawned: \(nodePath, privacy: .public) \(scriptURL.path, privacy: .public)")
    }

    public func stop() {
        process?.terminate()
        process = nil
        helperPid = nil
    }

    public var isRunning: Bool {
        process?.isRunning ?? false
    }

    // MARK: - Static helpers

    /// Dernier PID rapporté par un helper actif (best-effort, pour debug UI).
    @MainActor private static var lastReportedPid: Int32?

    /// Cherche `node` dans `/opt/homebrew/bin`, `/usr/local/bin`, `~/.nvm/…`,
    /// puis dans `$PATH`. Retourne le path absolu.
    public static func locateNode() throws -> String {
        let candidates: [String] = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            ("\(NSHomeDirectory())/.nvm/current/bin/node"),
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Fallback : tente `which node` via /bin/sh
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-l", "-c", "command -v node"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { throw FridaError.nodeNotFound }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        throw FridaError.nodeNotFound
    }

    private static func parseEvent(line: String) -> Event {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[FRIDA]") else {
            return .rawLine(trimmed)
        }
        let body = trimmed.replacingOccurrences(of: "[FRIDA]", with: "").trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("PID:"), let pid = Int32(body.dropFirst(4)) {
            return .pid(pid)
        }
        if body.hasPrefix("HOOK:connect installed") {
            return .hookInstalled
        }
        if body.hasPrefix("CONNECT ") {
            // ex: "CONNECT 1.2.3.4:443 → 127.0.0.1:7975"
            let payload = body.dropFirst("CONNECT ".count)
            if let arrowRange = payload.range(of: " → ") {
                let originPart = String(payload[..<arrowRange.lowerBound])
                let comps = originPart.split(separator: ":")
                if comps.count == 2, let port = UInt16(comps[1]) {
                    return .connectRedirected(originalHost: String(comps[0]), originalPort: port)
                }
            }
            return .rawLine(trimmed)
        }
        if body.hasPrefix("READY") {
            return .ready
        }
        if body.hasPrefix("STOPPING") {
            let signal = body.replacingOccurrences(of: "STOPPING (", with: "")
                .replacingOccurrences(of: ")", with: "")
            return .stopping(signal: signal)
        }
        if body.hasPrefix("ERROR:") {
            let msg = body.dropFirst("ERROR:".count).trimmingCharacters(in: .whitespaces)
            return .error(msg)
        }
        return .rawLine(trimmed)
    }

    /// Lit le pipe ligne par ligne et appelle `handler` pour chaque ligne.
    private static func readLines(from handle: FileHandle, handler: @Sendable @escaping (String) -> Void) {
        let buffer = LineBuffer()
        handle.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty {
                fh.readabilityHandler = nil
                // Flush partial
                if let last = buffer.flush() { handler(last) }
                return
            }
            buffer.append(data) { line in
                handler(line)
            }
        }
    }
}

/// Accumule des `Data` venant du pipe et émet des lignes complètes.
private final class LineBuffer: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    func append(_ chunk: Data, onLine: (String) -> Void) {
        lock.lock()
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            if let line = String(data: lineData, encoding: .utf8) {
                lock.unlock()
                onLine(line)
                lock.lock()
            }
        }
        lock.unlock()
    }

    func flush() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !buffer.isEmpty else { return nil }
        let line = String(data: buffer, encoding: .utf8)
        buffer.removeAll()
        return line
    }
}
