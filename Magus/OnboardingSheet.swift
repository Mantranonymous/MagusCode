import MagusPerception
import MagusUI
import SwiftUI

/// Wizard d'onboarding affiché au 1er lancement.
struct OnboardingSheet: View {
    let appState: AppState
    @Binding var isPresented: Bool
    @State private var step: Int = 0

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.Colors.border)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Theme.Spacing.xxl)
            Divider().background(Theme.Colors.border)
            footer
        }
        .frame(width: 600, height: 500)
        .background(Theme.Colors.bg)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bienvenue dans Magus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Étape \(step + 1) / \(totalSteps)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Circle()
                        .fill(i <= step ? Theme.Colors.accent : Theme.Colors.surfaceElev)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcomeStep
        case 1: permissionsStep
        case 2: dofusDBStep
        case 3: calibrationStep
        default: EmptyView()
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Image(systemName: "wand.and.stars.inverse")
                .font(.system(size: 50))
                .foregroundStyle(Theme.Colors.accent)
            Text("Forgemagie assistée")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("""
            Magus observe ton interface Dofus, comprend l'état de ton item de FM et te \
            guide rune par rune. 3 modes :

            • **Guidé** — overlay flottant te dit quelle rune appliquer, tu cliques
            • **Démo** — Magus visualise le clic sans l'exécuter
            • **Auto** — Magus clique tout seul (avec sécurités)
            """)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.leading)
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.warning)
            Text("Permissions macOS requises")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)

            permissionRow(
                title: "Capture d'écran",
                description: "Pour lire la fenêtre Dofus en temps réel",
                granted: appState.permissions.screenRecording == .granted,
                action: { appState.requestScreenRecording() }
            )

            permissionRow(
                title: "Accessibilité",
                description: "Pour cliquer sur la fenêtre Dofus en arrière-plan (mode Auto)",
                granted: appState.permissions.accessibility == .granted,
                action: { appState.requestAccessibility() }
            )

            Text("Si refusées, va dans Réglages système > Confidentialité > Capture/Accessibilité et coche Magus.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private func permissionRow(title: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(granted ? Theme.Colors.success : Theme.Colors.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            if !granted {
                MagusButton("Accorder", style: .secondary, action: action)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var dofusDBStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.accent)
            Text("Base de données DofusDB")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("""
            Magus utilise DofusDB pour connaître les items, les stats, les ranges de craft, \
            les recettes. Première sync ~30 secondes, puis cache local hors-ligne.
            """)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.textSecondary)

            HStack {
                if appState.refStats.chars > 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.success)
                    Text("Synchronisé : \(appState.refStats.chars) stats · \(appState.refStats.items) items")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.Colors.success)
                } else if appState.isSyncingReference {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Sync en cours...")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    MagusButton("Synchroniser maintenant", icon: "arrow.triangle.2.circlepath", style: .primary) {
                        Task { await appState.syncReference() }
                    }
                }
            }
        }
    }

    private var calibrationStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Image(systemName: "scope")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.gold)
            Text("Calibration")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("""
            Une fois Dofus ouvert sur l'établi de forgemagie, va sur Activité et clique \
            « Calibrer ». Trace les zones :

            • **Stats** : la table avec les valeurs courantes
            • **Historique** : la liste des combines à gauche
            • **Reliquat** : la zone "reliquat : X" en haut
            • **Niveau métier** : ton level en haut-gauche
            • **Colonnes Pa / Ra / Modif** (optionnel) : pour précision du clic auto

            Le profil est sauvegardé automatiquement. Tu peux le retracer à tout moment.
            """)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                MagusButton("Précédent", style: .ghost) { step -= 1 }
            }
            Spacer()
            if step < totalSteps - 1 {
                MagusButton("Suivant", icon: "arrow.right", style: .primary) { step += 1 }
            } else {
                MagusButton("Terminer", icon: "checkmark", style: .primary) {
                    UserDefaults.standard.set(true, forKey: "magus.onboardingDone")
                    isPresented = false
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface)
    }
}
