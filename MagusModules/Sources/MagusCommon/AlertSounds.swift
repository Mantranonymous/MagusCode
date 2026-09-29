import AppKit
import Foundation

/// 4 alertes sonores inspirées d'ExoFast :
/// - success : fin de session, jet atteint
/// - fail    : rune épuisée, échec critique
/// - danger  : MP modérateur, invitation groupe (anti-bust)
/// - alert   : safety stop, régression détectée
///
/// Utilise les sons système macOS pour éviter de packager des fichiers audio.
/// L'utilisateur peut remplacer par ses propres sons en posant des fichiers
/// .aiff dans `~/Library/Sounds/`.
@MainActor
public final class AlertSounds {

    public static let shared = AlertSounds()

    public enum Kind: String, Sendable, CaseIterable {
        case success
        case fail
        case danger
        case alert

        /// Nom du son système macOS le plus adapté.
        public var systemSoundName: String {
            switch self {
            case .success: return "Glass"   // doux et positif
            case .fail: return "Sosumi"     // notification d'erreur classique
            case .danger: return "Basso"    // grave et urgent
            case .alert: return "Tink"      // léger pour signal
            }
        }

        public var displayName: String {
            switch self {
            case .success: return "Succès (fin de jet)"
            case .fail: return "Échec (rune épuisée)"
            case .danger: return "Danger (MP / modérateur)"
            case .alert: return "Alerte (safety stop)"
            }
        }
    }

    private init() {}

    /// Joue le son correspondant. No-op si `enabled` est false.
    public func play(_ kind: Kind, enabled: Bool = true) {
        guard enabled else { return }
        NSSound(named: kind.systemSoundName)?.play()
    }
}
