import AppKit
import CoreGraphics
import Foundation
import MagusCommon
import os

/// Cherche et suit une fenêtre cible par bundle ID (case-insensitive) avec fallback titre.
/// Par défaut : Dofus 3 (Unity) — bundle ID `com.Ankama.Dofus`.
public struct WindowFinder: Sendable {

    public let targetBundleIdentifier: String
    public let targetTitleFallback: String?
    public let pollInterval: TimeInterval

    public init(
        bundleIdentifier: String = "com.Ankama.Dofus",
        titleFallback: String? = "Dofus",
        pollInterval: TimeInterval = 0.5
    ) {
        self.targetBundleIdentifier = bundleIdentifier
        self.targetTitleFallback = titleFallback
        self.pollInterval = pollInterval
    }

    /// Recherche ponctuelle. Retourne `nil` si la fenêtre n'est pas trouvée.
    public func find() -> WindowInfo? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for entry in raw {
            guard
                let layer = entry[kCGWindowLayer as String] as? Int,
                layer == 0,
                let windowID = entry[kCGWindowNumber as String] as? CGWindowID,
                let pid = entry[kCGWindowOwnerPID as String] as? pid_t
            else { continue }

            let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            let title = entry[kCGWindowName as String] as? String

            let matchesBundle = bundleID.map {
                $0.caseInsensitiveCompare(targetBundleIdentifier) == .orderedSame
            } ?? false

            let matchesTitle: Bool = {
                guard let fallback = targetTitleFallback, let t = title, !t.isEmpty else { return false }
                return t.localizedCaseInsensitiveContains(fallback)
            }()

            guard matchesBundle || matchesTitle else { continue }

            guard
                let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }

            return WindowInfo(
                windowID: windowID,
                processID: pid,
                bundleIdentifier: bundleID,
                title: title,
                bounds: bounds
            )
        }
        return nil
    }

    /// Stream qui émet une nouvelle valeur dès que la fenêtre change (position, taille, apparition, disparition).
    public func track() -> AsyncStream<WindowInfo?> {
        AsyncStream { continuation in
            let finder = self
            let task = Task {
                var last: WindowInfo? = nil
                while !Task.isCancelled {
                    let current = finder.find()
                    if current != last {
                        continuation.yield(current)
                        last = current
                        if current == nil {
                            MagusLogger.perception.debug("WindowFinder: fenêtre cible introuvable")
                        } else {
                            MagusLogger.perception.debug("WindowFinder: fenêtre détectée \(String(describing: current?.bounds), privacy: .public)")
                        }
                    }
                    try? await Task.sleep(nanoseconds: UInt64(finder.pollInterval * 1_000_000_000))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
