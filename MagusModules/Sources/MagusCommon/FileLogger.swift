import Foundation
import os

/// Buffer en mémoire des dernières lignes de log, utilisé pour la vue Diagnostics.
/// Singleton thread-safe.
public final class LogBuffer: @unchecked Sendable {

    public static let shared = LogBuffer()

    public struct Entry: Sendable {
        public let timestamp: Date
        public let level: String
        public let category: String
        public let message: String
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let maxEntries = 500

    private init() {}

    public func append(level: String, category: String, message: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(Entry(timestamp: Date(), level: level, category: category, message: message))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    public func snapshot() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}

/// FileLogger : écrit les logs dans Application Support/Magus/logs/magus.log.
/// Append-only, taille bornée (rotation manuelle à implémenter plus tard).
public final class FileLogger: @unchecked Sendable {

    public static let shared = FileLogger()

    private let fileURL: URL?
    private let queue = DispatchQueue(label: "magus.filelog", qos: .utility)
    private let formatter: DateFormatter

    private init() {
        let fm = FileManager.default
        let baseURL = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Magus/logs")
        if let base = baseURL {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
            self.fileURL = base.appendingPathComponent("magus.log")
            if !fm.fileExists(atPath: self.fileURL!.path) {
                fm.createFile(atPath: self.fileURL!.path, contents: nil)
            }
        } else {
            self.fileURL = nil
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        self.formatter = f
    }

    public func log(level: String, category: String, message: String) {
        let ts = formatter.string(from: Date())
        let line = "\(ts) [\(level)] \(category) \(message)\n"
        queue.async { [weak self] in
            guard let self = self, let url = self.fileURL else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    try? handle.write(contentsOf: data)
                }
                try? handle.close()
            }
        }
    }

    public var logFileURL: URL? { fileURL }
}
