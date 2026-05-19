import SwiftUI

/// Contenu SwiftUI affiché dans l'overlay flottant sur Dofus.
/// Volontairement minimal et lisible à distance (gros texte, fond semi-opaque).
public struct OverlayContent: View {

    public enum Severity: Sendable {
        case action       // recommandation à exécuter (bleu accent)
        case exo          // exo / spécial (doré)
        case danger       // anti-rune / risque (rouge)
        case success      // jet parfait atteint (vert)
        case info         // information neutre (warning ambre)
    }

    public let title: String
    public let subtitle: String
    public let severity: Severity

    public init(title: String, subtitle: String, severity: Severity) {
        self.title = title
        self.subtitle = subtitle
        self.severity = severity
    }

    public var body: some View {
        HStack(spacing: 12) {
            iconView
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: 2)
                )
        )
        .shadow(color: .black.opacity(0.6), radius: 10, x: 0, y: 4)
    }

    private var iconView: some View {
        Image(systemName: iconName)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(borderColor)
            .frame(width: 30)
    }

    private var iconName: String {
        switch severity {
        case .action: return "scope"
        case .exo: return "sparkle"
        case .danger: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.seal.fill"
        case .info: return "info.circle"
        }
    }

    private var borderColor: Color {
        switch severity {
        case .action: return Color(red: 0.486, green: 0.557, blue: 1.0)        // accent
        case .exo: return Color(red: 0.831, green: 0.647, blue: 0.455)         // gold
        case .danger: return Color(red: 0.937, green: 0.267, blue: 0.267)      // danger
        case .success: return Color(red: 0.290, green: 0.871, blue: 0.502)     // success
        case .info: return Color(red: 0.984, green: 0.749, blue: 0.141)        // warning
        }
    }
}
