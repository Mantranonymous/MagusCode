import SwiftUI

public struct MagusButton: View {

    public enum Style: Sendable {
        case primary, secondary, danger, ghost
    }

    private let title: String
    private let icon: String?
    private let style: Style
    private let isDisabled: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        icon: String? = nil,
        style: Style = .primary,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.isDisabled = isDisabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return Theme.Colors.accent
        case .secondary: return Theme.Colors.surfaceElev
        case .danger: return Theme.Colors.danger
        case .ghost: return Color.clear
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary, .danger: return .white
        case .secondary: return Theme.Colors.textPrimary
        case .ghost: return Theme.Colors.textSecondary
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary, .danger: return Color.clear
        case .secondary, .ghost: return Theme.Colors.border
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        MagusButton("Sauvegarder", icon: "checkmark", style: .primary) {}
        MagusButton("Annuler", style: .secondary) {}
        MagusButton("Supprimer", icon: "trash", style: .danger) {}
        MagusButton("Plus", style: .ghost) {}
    }
    .padding()
    .background(Theme.Colors.bg)
}
