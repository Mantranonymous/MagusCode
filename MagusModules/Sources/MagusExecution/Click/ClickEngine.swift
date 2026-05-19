import AppKit
import CoreGraphics
import Foundation
import MagusCommon
import os

public enum ClickEngineError: Error, Sendable {
    case eventCreationFailed
    case eventSourceFailed
}

/// Simule des clics souris ciblés sur la fenêtre Dofus via CGEvent.
/// Utilise le tap HID global (`.cghidEventTap`) qui est le canal standard pour
/// les événements synthétiques. Pour que Dofus reçoive le click, on active le
/// process avant le click.
@MainActor
public final class ClickEngine {

    private let logger = MagusLogger.execution

    public init() {}

    /// Clic gauche unique sur (x, y) en coordonnées d'écran (Quartz top-left).
    /// Trajectoire human-like (Bézier + jitter) si `humanMotion` true.
    public func click(at point: CGPoint, pid: pid_t, holdMs: Int = 40, humanMotion: Bool = true) async throws {
        // 1. Active Dofus pour qu'il soit le récepteur du click
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateIgnoringOtherApps])
            try await Task.sleep(nanoseconds: 80_000_000) // 80ms pour laisser le focus s'appliquer
        }

        // 2. Bouge le curseur — trajectoire humaine ou directe
        if humanMotion {
            try await moveHumanLike(to: point)
        } else {
            try moveMouse(to: point)
            try await Task.sleep(nanoseconds: 30_000_000)
        }

        // 3. Crée les événements down + up avec une CGEventSource explicite
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ClickEngineError.eventSourceFailed
        }
        guard let down = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ), let up = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            throw ClickEngineError.eventCreationFailed
        }

        // ClickState = 1 pour que macOS considère ça comme un vrai click (pas un drag)
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)

        // 4. Post via le HID tap global — le système route normalement vers la fenêtre sous le curseur
        down.post(tap: .cghidEventTap)
        try await Task.sleep(nanoseconds: UInt64(max(20, holdMs) * 1_000_000))
        up.post(tap: .cghidEventTap)

        logger.info("Click @(\(Int(point.x), privacy: .public), \(Int(point.y), privacy: .public)) pid=\(pid, privacy: .public)")
    }

    /// Déplace le curseur via le HID tap global (instantané).
    public func moveMouse(to point: CGPoint) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ClickEngineError.eventSourceFailed
        }
        guard let move = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            throw ClickEngineError.eventCreationFailed
        }
        move.post(tap: .cghidEventTap)
    }

    /// Déplace le curseur le long d'une trajectoire human-like (Bézier + jitter).
    private func moveHumanLike(to target: CGPoint) async throws {
        let currentLocation = NSEvent.mouseLocation
        // NSEvent.mouseLocation est en bottom-left, on convertit vers Quartz top-left
        let screenH = NSScreen.main?.frame.height ?? 0
        let from = CGPoint(x: currentLocation.x, y: screenH - currentLocation.y)

        let path = HumanMotion.path(from: from, to: target)
        for step in path {
            try moveMouse(to: step.point)
            try await Task.sleep(nanoseconds: step.delayNs)
        }
    }
}
