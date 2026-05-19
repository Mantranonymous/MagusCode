import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import MagusCommon
import os

/// Gère les permissions système nécessaires à Magus :
/// - Screen Recording (capture de la fenêtre Dofus)
/// - Accessibility (tracking et input simulation)
@MainActor
@Observable
public final class PermissionManager {

    public enum Status: Hashable, Sendable {
        case unknown
        case granted
        case denied
    }

    public enum Permission: Hashable, Sendable, CaseIterable {
        case screenRecording
        case accessibility

        public var displayName: String {
            switch self {
            case .screenRecording: return "Capture d'écran"
            case .accessibility: return "Accessibilité"
            }
        }

        public var rationale: String {
            switch self {
            case .screenRecording:
                return "Magus a besoin de capturer la fenêtre de Dofus pour lire l'état de l'item en cours de forgemagie."
            case .accessibility:
                return "Magus utilise l'accessibilité pour détecter et suivre la fenêtre de Dofus, et pour simuler les clics en mode automatique."
            }
        }
    }

    public private(set) var screenRecording: Status = .unknown
    public private(set) var accessibility: Status = .unknown

    public init() {
        refresh()
    }

    public var allGranted: Bool {
        screenRecording == .granted && accessibility == .granted
    }

    public func status(of permission: Permission) -> Status {
        switch permission {
        case .screenRecording: return screenRecording
        case .accessibility: return accessibility
        }
    }

    /// Vérifie l'état des permissions sans déclencher de prompt système.
    public func refresh() {
        screenRecording = CGPreflightScreenCaptureAccess() ? .granted : .denied
        accessibility = AXIsProcessTrusted() ? .granted : .denied
        MagusLogger.perception.info(
            "Permissions: screen=\(self.screenRecording == .granted ? "granted" : "denied", privacy: .public) accessibility=\(self.accessibility == .granted ? "granted" : "denied", privacy: .public)"
        )
    }

    /// Demande Screen Recording (déclenche le prompt système la première fois).
    @discardableResult
    public func requestScreenRecording() -> Status {
        let granted = CGRequestScreenCaptureAccess()
        screenRecording = granted ? .granted : .denied
        return screenRecording
    }

    /// Demande Accessibility (déclenche le prompt système la première fois).
    @discardableResult
    public func requestAccessibility() -> Status {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        accessibility = granted ? .granted : .denied
        return accessibility
    }

    /// Ouvre le panneau System Settings correspondant.
    public func openSystemSettings(for permission: Permission) {
        let urlString: String
        switch permission {
        case .screenRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
