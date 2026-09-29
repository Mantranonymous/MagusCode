import Foundation
import Observation

/// Préférences utilisateur persistées dans `UserDefaults`.
/// Lecture/écriture sur le MainActor uniquement (UI binding).
@MainActor
@Observable
public final class AppSettings {

    public static let shared = AppSettings()

    // MARK: - Keys

    private enum Key {
        static let vlmFallbackEnabled = "magus.vlmFallbackEnabled"
        static let vlmConfidenceThreshold = "magus.vlmConfidenceThreshold"
        static let showClickMarker = "magus.showClickMarker"
        static let logLevel = "magus.logLevel"
        static let onboardingDone = "magus.onboardingDone"
        static let soundsEnabled = "magus.soundsEnabled"
        static let ocrUpscaleFactor = "magus.ocrUpscaleFactor"
        static let ocrBinarize = "magus.ocrBinarize"
        static let turboMode = "magus.turboMode"
        static let networkObservationEnabled = "magus.networkObservationEnabled"
        static let networkProxyPort = "magus.networkProxyPort"
        static let networkDofusPath = "magus.networkDofusPath"
    }

    // MARK: - VLM Fallback

    /// Active le fallback VLM (Qwen2.5-VL via MLX) en cas de confiance Vision basse.
    /// **Note** : l'engine VLM est actuellement non implémenté ; le toggle est exposé
    /// pour préparer l'infrastructure. Activé → l'OCRPipeline tentera VLM quand
    /// la confidence d'une région passe sous `vlmConfidenceThreshold`.
    public var vlmFallbackEnabled: Bool {
        didSet { UserDefaults.standard.set(vlmFallbackEnabled, forKey: Key.vlmFallbackEnabled) }
    }

    /// Seuil de confiance Vision sous lequel le VLM prend le relais (0–1).
    public var vlmConfidenceThreshold: Double {
        didSet { UserDefaults.standard.set(vlmConfidenceThreshold, forKey: Key.vlmConfidenceThreshold) }
    }

    // MARK: - UI

    /// Affiche le marqueur visuel rond au point du prochain clic (debug visuel).
    public var showClickMarker: Bool {
        didSet { UserDefaults.standard.set(showClickMarker, forKey: Key.showClickMarker) }
    }

    // MARK: - Logging

    public enum LogLevel: String, CaseIterable, Sendable {
        case debug
        case info
        case warning
        case error

        public var displayName: String {
            switch self {
            case .debug: return "Debug"
            case .info: return "Info"
            case .warning: return "Warning"
            case .error: return "Error"
            }
        }
    }

    public var logLevel: LogLevel {
        didSet { UserDefaults.standard.set(logLevel.rawValue, forKey: Key.logLevel) }
    }

    /// Active les alertes sonores (success/fail/danger/alert).
    public var soundsEnabled: Bool {
        didSet { UserDefaults.standard.set(soundsEnabled, forKey: Key.soundsEnabled) }
    }

    // MARK: - OCR Preprocessing

    /// Facteur d'upscale Lanczos avant OCR (1.0 = pas d'upscale, 2.0 = 2x, etc.).
    /// Boost significativement la précision sur du texte fin (table FM Dofus).
    public var ocrUpscaleFactor: Double {
        didSet { UserDefaults.standard.set(ocrUpscaleFactor, forKey: Key.ocrUpscaleFactor) }
    }

    /// Active la binarisation (noir & blanc + contraste boosté) avant OCR.
    /// Plus précis sur certains items mais peut rater le texte clair sur fond gris.
    public var ocrBinarize: Bool {
        didSet { UserDefaults.standard.set(ocrBinarize, forKey: Key.ocrBinarize) }
    }

    // MARK: - Turbo

    /// Mode Turbo : 2-3x plus rapide mais risque détection accru.
    /// Désactive les pauses anti-detect, réduit les délais entre clicks et l'OCR,
    /// raccourcit le mouvement humain Bézier. À réserver aux comptes jetables.
    public var turboMode: Bool {
        didSet { UserDefaults.standard.set(turboMode, forKey: Key.turboMode) }
    }

    // MARK: - Network observation (passive)

    /// Active l'observation passive du trafic réseau Dofus via le module
    /// MagusNetwork (proxy local + hook Frida libc connect()). Aucune injection
    /// ni forge de paquet — observation pure pour augmenter la précision du
    /// `GameStateSnapshot`. Le `ClickEngine` reste source unique d'actions.
    public var networkObservationEnabled: Bool {
        didSet { UserDefaults.standard.set(networkObservationEnabled, forKey: Key.networkObservationEnabled) }
    }

    /// Port local sur lequel le proxy MagusNetwork écoute. Le hook Frida
    /// réécrit la sockaddr Dofus pour pointer vers `127.0.0.1:<port>`.
    public var networkProxyPort: UInt16 {
        didSet { UserDefaults.standard.set(Int(networkProxyPort), forKey: Key.networkProxyPort) }
    }

    /// Chemin de l'exécutable Dofus à spawn par Frida. Vide = défaut système.
    public var networkDofusPath: String {
        didSet { UserDefaults.standard.set(networkDofusPath, forKey: Key.networkDofusPath) }
    }

    // MARK: - Init

    private init() {
        let d = UserDefaults.standard
        // Defaults : VLM off (pas encore implémenté), threshold 0.6, marker on, log info
        if d.object(forKey: Key.vlmFallbackEnabled) == nil {
            d.set(false, forKey: Key.vlmFallbackEnabled)
        }
        if d.object(forKey: Key.vlmConfidenceThreshold) == nil {
            d.set(0.6, forKey: Key.vlmConfidenceThreshold)
        }
        if d.object(forKey: Key.showClickMarker) == nil {
            d.set(true, forKey: Key.showClickMarker)
        }
        if d.object(forKey: Key.logLevel) == nil {
            d.set(LogLevel.info.rawValue, forKey: Key.logLevel)
        }
        if d.object(forKey: Key.soundsEnabled) == nil {
            d.set(true, forKey: Key.soundsEnabled)
        }
        if d.object(forKey: Key.ocrUpscaleFactor) == nil {
            d.set(2.0, forKey: Key.ocrUpscaleFactor)
        }
        if d.object(forKey: Key.ocrBinarize) == nil {
            d.set(false, forKey: Key.ocrBinarize)
        }
        if d.object(forKey: Key.turboMode) == nil {
            d.set(false, forKey: Key.turboMode)
        }
        if d.object(forKey: Key.networkObservationEnabled) == nil {
            d.set(false, forKey: Key.networkObservationEnabled)
        }
        if d.object(forKey: Key.networkProxyPort) == nil {
            d.set(7975, forKey: Key.networkProxyPort)
        }
        if d.object(forKey: Key.networkDofusPath) == nil {
            d.set("/Applications/Ankama/Dofus-dofus3/Dofus.app/Contents/MacOS/Dofus", forKey: Key.networkDofusPath)
        }
        self.vlmFallbackEnabled = d.bool(forKey: Key.vlmFallbackEnabled)
        self.vlmConfidenceThreshold = d.double(forKey: Key.vlmConfidenceThreshold)
        self.showClickMarker = d.bool(forKey: Key.showClickMarker)
        let levelRaw = d.string(forKey: Key.logLevel) ?? LogLevel.info.rawValue
        self.logLevel = LogLevel(rawValue: levelRaw) ?? .info
        self.soundsEnabled = d.bool(forKey: Key.soundsEnabled)
        self.ocrUpscaleFactor = d.double(forKey: Key.ocrUpscaleFactor)
        self.ocrBinarize = d.bool(forKey: Key.ocrBinarize)
        self.turboMode = d.bool(forKey: Key.turboMode)
        self.networkObservationEnabled = d.bool(forKey: Key.networkObservationEnabled)
        let storedPort = d.integer(forKey: Key.networkProxyPort)
        self.networkProxyPort = (storedPort > 0 && storedPort <= 65535) ? UInt16(storedPort) : 7975
        self.networkDofusPath = d.string(forKey: Key.networkDofusPath) ?? ""
    }

    // MARK: - Actions

    /// Remet le drapeau d'onboarding à zéro pour rejouer le wizard.
    public func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: Key.onboardingDone)
    }

    /// Restore les valeurs par défaut (n'affecte pas onboarding/calibration/DB).
    public func resetToDefaults() {
        vlmFallbackEnabled = false
        vlmConfidenceThreshold = 0.6
        showClickMarker = true
        logLevel = .info
        soundsEnabled = true
        ocrUpscaleFactor = 2.0
        ocrBinarize = false
        turboMode = false
        networkObservationEnabled = false
        networkProxyPort = 7975
        networkDofusPath = "/Applications/Ankama/Dofus-dofus3/Dofus.app/Contents/MacOS/Dofus"
    }
}

/// Snapshot immuable de `AppSettings`, safe à passer à des contextes non-MainActor
/// (ex : OCRPipeline tournant dans une Task background).
public struct AppSettingsSnapshot: Sendable {
    public let vlmFallbackEnabled: Bool
    public let vlmConfidenceThreshold: Double
    public let showClickMarker: Bool
    public let ocrUpscaleFactor: Double   // 1.0 = no scale, 2.0 = 2x Lanczos, etc.
    public let ocrBinarize: Bool

    public init(
        vlmFallbackEnabled: Bool,
        vlmConfidenceThreshold: Double,
        showClickMarker: Bool,
        ocrUpscaleFactor: Double = 2.0,
        ocrBinarize: Bool = false
    ) {
        self.vlmFallbackEnabled = vlmFallbackEnabled
        self.vlmConfidenceThreshold = vlmConfidenceThreshold
        self.showClickMarker = showClickMarker
        self.ocrUpscaleFactor = ocrUpscaleFactor
        self.ocrBinarize = ocrBinarize
    }
}

extension AppSettings {
    public var snapshot: AppSettingsSnapshot {
        AppSettingsSnapshot(
            vlmFallbackEnabled: vlmFallbackEnabled,
            vlmConfidenceThreshold: vlmConfidenceThreshold,
            showClickMarker: showClickMarker,
            ocrUpscaleFactor: ocrUpscaleFactor,
            ocrBinarize: ocrBinarize
        )
    }
}
