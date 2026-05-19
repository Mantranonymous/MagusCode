import MagusCore
import MagusDecision
import MagusPersistence
import MagusPerception
import MagusReferenceData
import MagusUI
import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()

    var body: some View {
        Group {
            switch appState.mode {
            case .home:
                HomeView(appState: appState)
            case .calibration:
                CalibrationContainer(appState: appState)
            }
        }
        .frame(minWidth: 1100, minHeight: 700)
        .background(Theme.Colors.bg)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Home

private struct HomeView: View {
    let appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().background(Theme.Colors.border)
            workspace
            if appState.currentRoute == .activite {
                Divider().background(Theme.Colors.border)
                inspector
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Magus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Forgemagie assistée")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xxl)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(AppState.Route.allCases, id: \.self) { route in
                    sidebarItem(route: route)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)

            Spacer()

            // Session status mini indicator
            if appState.isSessionActive {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Theme.Colors.success)
                            .frame(width: 6, height: 6)
                        Text("Session active")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.Colors.success)
                    }
                    Text(automationModeLabel)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surfaceElev)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.md)
            }
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(Theme.Colors.surface)
    }

    private var automationModeLabel: String {
        switch appState.automation {
        case .guided: return "guided"
        case .demo: return "demo \(appState.demoClickCount)"
        case .auto: return "auto \(appState.autoClickCount)"
        }
    }

    private func sidebarItem(route: AppState.Route) -> some View {
        let isActive = appState.currentRoute == route
        return Button {
            appState.currentRoute = route
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: route.iconName)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(route.displayName)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(isActive ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(isActive ? Theme.Colors.surfaceElev : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var workspace: some View {
        switch appState.currentRoute {
        case .activite: activiteWorkspace
        case .bibliotheque: bibliothequeWorkspace
        case .reglages: reglagesWorkspace
        }
    }

    private var activiteWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                Text("Activité")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.top, Theme.Spacing.xxxl)

                actionRecommendationCard
                dofusCard
                itemPickerCard
                if let profile = appState.savedProfiles.first(where: { $0.isComplete }) {
                    ocrTestCard(profile: profile)
                }

                Spacer(minLength: Theme.Spacing.xxxl)
            }
            .padding(.horizontal, Theme.Spacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bibliothequeWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                Text("Bibliothèque")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.top, Theme.Spacing.xxxl)

                profilesCard

                Card(title: "Items DofusDB") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("\(appState.refStats.items) items synchronisés depuis DofusDB.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        if let item = appState.selectedItem {
                            HStack {
                                Text("Sélection courante :")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                                Text(item.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Spacer()
                            }
                        }
                    }
                }

                Card(title: "Presets sauvegardés") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        if appState.savedPresets.isEmpty {
                            Text("Aucun preset sauvegardé. Va sur Activité, choisis un item + un scénario, puis clique « Sauvegarder » pour le mettre ici.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        } else {
                            ForEach(appState.savedPresets) { preset in
                                presetRow(preset: preset)
                                if preset.id != appState.savedPresets.last?.id {
                                    Divider().background(Theme.Colors.border)
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: Theme.Spacing.xxxl)
            }
            .padding(.horizontal, Theme.Spacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reglagesWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                Text("Réglages")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.top, Theme.Spacing.xxxl)

                permissionsCard
                referenceCard

                Card(title: "Diagnostics") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        diagnosticRow(label: "Étape", value: flowStepLabel)
                        diagnosticRow(label: "Permissions", value: appState.permissions.allGranted ? "OK" : "manquantes")
                        diagnosticRow(label: "Dofus", value: appState.detectedWindow != nil ? "détecté" : "introuvable")
                        diagnosticRow(label: "Profils calibrés", value: "\(appState.savedProfiles.count)")
                        diagnosticRow(label: "DofusDB version", value: appState.dofusDBVersion ?? "—")
                        diagnosticRow(label: "Caractéristiques", value: "\(appState.refStats.chars)")
                        diagnosticRow(label: "Items synchros", value: "\(appState.refStats.items)")
                        if appState.isSessionActive {
                            diagnosticRow(label: "Session FPS", value: String(format: "%.1f", appState.sessionFps))
                        }
                    }
                }

                Spacer(minLength: Theme.Spacing.xxxl)
            }
            .padding(.horizontal, Theme.Spacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionsCard: some View {
        Card(title: "Permissions système") {
            VStack(spacing: Theme.Spacing.md) {
                permissionRow(
                    permission: .screenRecording,
                    status: appState.permissions.screenRecording
                )
                Divider().background(Theme.Colors.border)
                permissionRow(
                    permission: .accessibility,
                    status: appState.permissions.accessibility
                )
            }
        }
    }

    private func permissionRow(permission: PermissionManager.Permission, status: PermissionManager.Status) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            StatusDot(state: status == .granted ? .done : .error, size: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(permission.rationale)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            if status != .granted {
                MagusButton("Activer", style: .secondary) {
                    switch permission {
                    case .screenRecording:
                        appState.requestScreenRecording()
                    case .accessibility:
                        appState.requestAccessibility()
                    }
                    appState.openSettings(for: permission)
                }
            }
        }
    }

    private var referenceCard: some View {
        Card(title: "Données de référence (DofusDB)") {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    StatusDot(state: refDotState, size: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(refHeadline)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(refSubheadline)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    MagusButton(
                        appState.isSyncingReference ? "Sync en cours..." : "Resync",
                        icon: "arrow.triangle.2.circlepath",
                        style: .secondary,
                        isDisabled: appState.isSyncingReference
                    ) {
                        Task { await appState.syncReference() }
                    }
                }

                if appState.isSyncingReference {
                    syncProgressBar
                }

                if let err = appState.lastSyncError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.danger)
                        .lineLimit(3)
                }
            }
        }
    }

    private var refDotState: StatusDot.State {
        if appState.isSyncingReference { return .current }
        if appState.lastSyncError != nil { return .error }
        if appState.refStats.chars == 0 { return .pending }
        return .done
    }

    private var refHeadline: String {
        if appState.isSyncingReference {
            return "Synchronisation : \(stageLabel(appState.syncProgress.stage))"
        }
        if appState.refStats.chars == 0 {
            return "Pas encore synchronisé"
        }
        return "Synchronisé — DofusDB \(appState.dofusDBVersion ?? "?")"
    }

    private var refSubheadline: String {
        if appState.isSyncingReference {
            let p = appState.syncProgress
            if p.total > 0 {
                return "\(p.fetched) / \(p.total)"
            }
            return "..."
        }
        let s = appState.refStats
        if s.chars == 0 {
            return "—"
        }
        let last = appState.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "—"
        return "\(s.chars) stats · \(s.effects) effets · \(s.items) items · maj \(last)"
    }

    private func stageLabel(_ stage: SyncProgress.Stage) -> String {
        switch stage {
        case .idle: return "—"
        case .version: return "version"
        case .characteristics: return "stats"
        case .itemTypes: return "types d'items"
        case .effects: return "effets"
        case .items: return "items"
        case .persisting: return "écriture SQLite"
        case .done: return "OK"
        case .failed: return "erreur"
        }
    }

    private var syncProgressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.Colors.surfaceElev)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.Colors.accent)
                    .frame(width: geo.size.width * appState.syncProgress.fraction)
            }
        }
        .frame(height: 4)
    }

    private var dofusCard: some View {
        Card(title: "Fenêtre Dofus") {
            HStack(spacing: Theme.Spacing.md) {
                StatusDot(state: appState.detectedWindow != nil ? .done : .pending, size: 10)
                VStack(alignment: .leading, spacing: 2) {
                    if let win = appState.detectedWindow {
                        Text("Détectée")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("\(Int(win.bounds.width)) × \(Int(win.bounds.height)) px · \(win.bundleIdentifier ?? "?")")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    } else {
                        Text("En attente")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Lance Dofus pour que Magus le détecte automatiquement.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                Spacer()
                if appState.detectedWindow != nil {
                    MagusButton("Calibrer", icon: "scope", style: .primary) {
                        Task { await appState.startCalibration() }
                    }
                }
            }
        }
    }

    private var profilesCard: some View {
        Card(title: "Profils de calibration") {
            if appState.savedProfiles.isEmpty {
                Text("Aucun profil enregistré pour l'instant.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.vertical, Theme.Spacing.sm)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(appState.savedProfiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text("\(profile.regions.count) / 6 zones · \(profile.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            StatusDot(state: profile.isComplete ? .done : .pending, size: 8)
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                }
            }
        }
    }

    @State private var showItemPicker = false

    @State private var showAutoWarning = false

    @ViewBuilder
    private var sessionButtons: some View {
        let hasProfile = appState.savedProfiles.first(where: { $0.isComplete }) != nil
        HStack(spacing: Theme.Spacing.sm) {
            if appState.isSessionActive {
                if appState.automation == .auto {
                    MagusButton("ARRÊT D'URGENCE", icon: "stop.fill", style: .danger) {
                        appState.emergencyStop()
                    }
                } else {
                    MagusButton("Arrêter session", icon: "stop.circle", style: .secondary) {
                        appState.stopSession()
                    }
                }
            } else {
                MagusButton(
                    "Démarrer session",
                    icon: "play.circle.fill",
                    style: .primary,
                    isDisabled: !hasProfile || appState.detectedWindow == nil || appState.selectedItem == nil
                ) {
                    if appState.automation == .auto {
                        showAutoWarning = true
                    } else {
                        appState.startSession()
                    }
                }
                if hasProfile {
                    MagusButton(
                        appState.isRunningOCR ? "OCR..." : "Test ponctuel",
                        icon: "arrow.clockwise",
                        style: .ghost,
                        isDisabled: appState.isRunningOCR || appState.detectedWindow == nil
                    ) {
                        guard let p = appState.savedProfiles.first(where: { $0.isComplete }) else { return }
                        Task { await appState.runOCRTest(profile: p) }
                    }
                }
            }
        }
        .alert("Mode AUTO — Confirmation", isPresented: $showAutoWarning) {
            Button("Annuler", role: .cancel) {}
            Button("Démarrer", role: .destructive) { appState.startSession() }
        } message: {
            Text("""
            En mode AUTO, Magus clique automatiquement dans Dofus. \
            La FM comporte un risque réel de DESTRUCTION DE L'ITEM.

            Recommandations :
            • Teste d'abord en mode Démo
            • Calibre les 3 colonnes Pa/Ra/Modif pour précision
            • Garde un œil sur l'écran
            • Sois prêt à cliquer ARRÊT D'URGENCE
            """)
        }
    }

    @ViewBuilder
    private var automationControls: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Segmented mode selector
            HStack(spacing: 0) {
                automationPill(label: "Guidé", icon: "hand.point.up.left.fill", mode: .guided)
                automationPill(label: "Démo", icon: "eye.fill", mode: .demo)
                automationPill(label: "Auto", icon: "bolt.fill", mode: .auto)
            }
            .background(Theme.Colors.surfaceElev)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

            if appState.isSessionActive {
                if appState.automation == .auto {
                    HStack(spacing: 4) {
                        Image(systemName: "cursorarrow.click.2")
                            .font(.system(size: 11))
                        Text("\(appState.autoClickCount) clic\(appState.autoClickCount > 1 ? "s" : "")")
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .foregroundStyle(Theme.Colors.warning)

                    if appState.consecutiveRegressions > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.right")
                            Text("\(appState.consecutiveRegressions) régression\(appState.consecutiveRegressions > 1 ? "s" : "")")
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.Colors.danger)
                    }
                } else if appState.automation == .demo {
                    HStack(spacing: 4) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 11))
                        Text("\(appState.demoClickCount) click\(appState.demoClickCount > 1 ? "s" : "") simulé\(appState.demoClickCount > 1 ? "s" : "")")
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
            }

            if let err = appState.autoClickError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.danger)
                    .lineLimit(1)
            }
        }
    }

    private func automationPill(label: String, icon: String, mode: AppState.SessionAutomation) -> some View {
        let isSelected = appState.automation == mode
        let isAuto = mode == .auto
        let canAuto = appState.canStartAuto || !isAuto
        return Button {
            guard !appState.isSessionActive else { return }
            // Auto requiert calibration colonnes : sinon on bascule en démo
            if isAuto && !appState.canStartAuto {
                appState.automation = .demo
            } else {
                appState.automation = mode
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                if isAuto && !canAuto {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? (isAuto ? Theme.Colors.danger : Theme.Colors.accent) : Color.clear)
            .foregroundStyle(isSelected ? .white : Theme.Colors.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(appState.isSessionActive)
        .help(isAuto && !canAuto ? "Calibre les colonnes Pa/Ra/Modif d'abord pour activer l'auto" : "")
    }

    @ViewBuilder
    private var actionRecommendationCard: some View {
        if let decision = appState.currentDecision {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .fill(actionCardBackground(for: decision))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.lg)
                            .stroke(actionCardBorder(for: decision), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    HStack {
                        Text("Action recommandée")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .textCase(.uppercase)
                        if appState.isSessionActive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Theme.Colors.success)
                                    .frame(width: 6, height: 6)
                                Text("Session active · \(String(format: "%.1f", appState.sessionFps)) fps")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Theme.Colors.success)
                            }
                        }
                        Spacer()
                        sessionButtons
                    }
                    automationControls

                    actionPrimaryRow(decision: decision)

                    Text(decision.explanation)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Spacing.xl)
            }
        } else if appState.selectedItem != nil {
            Card(title: "Action recommandée") {
                Text("Lance « Lancer OCR » pour calculer la recommandation.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func actionPrimaryRow(decision: Decision) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            switch decision {
            case .applyRune(let rune, let kind, _):
                runeBadgeBig(rune: rune)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Appliquer")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .textCase(.uppercase)
                    Text(runeName(rune: rune, kind: kind))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                Spacer()

            case .applyExo(let slot, _):
                Image(systemName: "sparkle")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.Colors.gold)
                Text("Tenter exo \(slot.displayName)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.Colors.gold)
                Spacer()

            case .applyAntiRune(let rune, let kind, _):
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.Colors.danger)
                Text("Anti-rune \(runeName(rune: rune, kind: kind))")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.Colors.danger)
                Spacer()

            case .finished:
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.Colors.success)
                Text("Jet parfait atteint")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.Colors.success)
                Spacer()

            case .waitingForUser(let reason):
                Image(systemName: "hourglass")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.Colors.warning)
                Text(reason)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()

            case .blocked(let reason):
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.Colors.warning)
                Text(reason.description)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
            }
        }
    }

    private func runeName(rune: Rune, kind: StatKind) -> String {
        let statName = appState.displayName(for: kind)
        let prefix = rune.power.prefix
        if prefix.isEmpty {
            return "Rune \(statName)"
        }
        return "Rune \(prefix) \(statName)"
    }

    private func runeBadgeBig(rune: Rune) -> some View {
        let color: Color
        switch rune.power {
        case .base: color = Theme.Colors.accent.opacity(0.7)
        case .pa: color = Theme.Colors.accent
        case .ra: color = Theme.Colors.gold
        }
        return ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.2))
                .frame(width: 56, height: 56)
            VStack(spacing: 0) {
                Text(rune.power == .base ? "•" : rune.power.prefix)
                    .font(.system(size: rune.power == .base ? 24 : 14, weight: .bold))
                    .foregroundStyle(color)
                Text("d\(rune.power.density)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private func actionCardBackground(for decision: Decision) -> Color {
        switch decision {
        case .applyRune, .applyExo, .applyAntiRune:
            return Theme.Colors.surface
        case .finished:
            return Theme.Colors.success.opacity(0.08)
        case .waitingForUser, .blocked:
            return Theme.Colors.surface
        }
    }

    private func actionCardBorder(for decision: Decision) -> Color {
        switch decision {
        case .applyRune: return Theme.Colors.accent.opacity(0.4)
        case .applyExo: return Theme.Colors.gold.opacity(0.4)
        case .applyAntiRune: return Theme.Colors.danger.opacity(0.4)
        case .finished: return Theme.Colors.success.opacity(0.4)
        case .waitingForUser, .blocked: return Theme.Colors.warning.opacity(0.4)
        }
    }

    private var itemPickerCard: some View {
        Card(title: "Item à mager") {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if let item = appState.selectedItem {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("Niveau \(item.level)" + (item.typeName.map { " · \($0)" } ?? "") + (item.metier.map { " · \($0.displayName)" } ?? ""))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        MagusButton("Changer", icon: "arrow.triangle.2.circlepath", style: .secondary) {
                            showItemPicker = true
                        }
                        MagusButton("", icon: "xmark", style: .ghost) {
                            appState.clearSelectedItem()
                        }
                    }

                    // Sélecteur de scénario
                    Divider().background(Theme.Colors.border)
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("Scénario")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .textCase(.uppercase)
                        HStack(spacing: 0) {
                            ForEach(PresetScenario.allCases, id: \.self) { scenario in
                                scenarioPill(scenario)
                            }
                        }
                        .background(Theme.Colors.surfaceElev)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                        Spacer()
                        MagusButton("Sauvegarder", icon: "square.and.arrow.down", style: .secondary) {
                            appState.saveCurrentPreset()
                        }
                    }

                    Divider().background(Theme.Colors.border)

                    let mageable = item.stats.filter(\.isMageable)
                    let fixed = item.stats.filter { !$0.isMageable }

                    if !mageable.isEmpty {
                        Text("Stats mageables")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .textCase(.uppercase)
                        ForEach(mageable, id: \.kind) { spec in
                            itemSpecStatRow(spec: spec, isFixed: false)
                        }
                    }

                    if !fixed.isEmpty {
                        Divider().background(Theme.Colors.border)
                        Text("Stats fixes (non mageables)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .textCase(.uppercase)
                        ForEach(fixed, id: \.kind) { spec in
                            itemSpecStatRow(spec: spec, isFixed: true)
                        }
                    }
                } else {
                    HStack {
                        Text("Aucun item sélectionné. Choisis l'item posé sur l'établi pour activer la stratégie DofusDB.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        MagusButton("Choisir un item", icon: "magnifyingglass", style: .primary) {
                            showItemPicker = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showItemPicker) {
            ItemPickerSheet(appState: appState, isPresented: $showItemPicker)
        }
    }

    private func presetRow(preset: StatsPreset) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("\(preset.scenario.displayName) · \(preset.targets.count) stats ciblées · maj \(preset.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            MagusButton("Utiliser", icon: "play.circle", style: .secondary) {
                appState.loadPreset(preset)
                appState.currentRoute = .activite
            }
            MagusButton("", icon: "trash", style: .ghost) {
                appState.deletePreset(preset)
            }
        }
    }

    private func scenarioPill(_ scenario: PresetScenario) -> some View {
        let isSelected = appState.currentScenario == scenario
        return Button {
            appState.setScenario(scenario)
        } label: {
            Text(scenario.shortName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Theme.Colors.accent : Color.clear)
                .foregroundStyle(isSelected ? .white : Theme.Colors.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func itemSpecStatRow(spec: StatSpec, isFixed: Bool) -> some View {
        let currentValue: Int? = appState.lastParsedSnapshot?.item?.stat(matching: spec.kind)?.value
        let displayName = appState.displayName(for: spec.kind)
        let primaryColor = isFixed ? Theme.Colors.textSecondary : Theme.Colors.textPrimary

        return HStack(spacing: Theme.Spacing.md) {
            Text(displayName)
                .font(.system(size: 12, weight: isFixed ? .regular : .medium))
                .foregroundStyle(primaryColor)
                .frame(width: 200, alignment: .leading)

            if let v = currentValue {
                let atMax = v >= spec.maxValue
                Text("\(v)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(atMax ? Theme.Colors.gold : (isFixed ? Theme.Colors.textSecondary : Theme.Colors.accent))
                    .frame(width: 50, alignment: .trailing)
            } else {
                Text("—")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: 50, alignment: .trailing)
            }

            Text(isFixed ? "(fixe \(spec.minValue))" : "(\(spec.minValue) - \(spec.maxValue))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: 90, alignment: .leading)

            Spacer()
        }
        .padding(.vertical, 2)
        .opacity(isFixed ? 0.75 : 1.0)
    }

    private func ocrTestCard(profile: ResolutionProfile) -> some View {
        Card(title: "État détecté — \(profile.name)") {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    if let snap = appState.lastOCRSnapshot {
                        Text("Dernier run : \(String(format: "%.1f", snap.totalElapsedMs)) ms · OCR + parsing")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(snap.totalElapsedMs < 200 ? Theme.Colors.success : Theme.Colors.warning)
                    } else {
                        Text("Pose un item sur l'établi puis clique « Lancer OCR ».")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    MagusButton(
                        "Capturer fixture",
                        icon: "camera.metering.matrix",
                        style: .ghost,
                        isDisabled: appState.isRunningOCR || appState.detectedWindow == nil
                    ) {
                        Task { await appState.captureFixture(profile: profile) }
                    }
                    MagusButton(
                        appState.isRunningOCR ? "OCR en cours..." : "Lancer OCR",
                        icon: "text.viewfinder",
                        style: .primary,
                        isDisabled: appState.isRunningOCR || appState.detectedWindow == nil
                    ) {
                        Task { await appState.runOCRTest(profile: profile) }
                    }
                }

                if let fixture = appState.lastFixturePath {
                    Text("Fixture sauvée : \(fixture.lastPathComponent)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.Colors.success)
                }

                if let snapshot = appState.lastParsedSnapshot {
                    Divider().background(Theme.Colors.border)
                    parsedSnapshotView(snapshot)
                }

                if let diff = appState.lastStateDiff, diff.hasChanges {
                    Divider().background(Theme.Colors.border)
                    stateDiffView(diff)
                }

                if let raw = appState.lastOCRSnapshot {
                    Divider().background(Theme.Colors.border)
                    rawOCRDebugView(raw)
                }
            }
        }
    }

    private func parsedSnapshotView(_ snapshot: GameStateSnapshot) -> some View {
        let hasItemSelected = appState.selectedItem != nil
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Top row : reliquat + métier + history + stats
            HStack(spacing: Theme.Spacing.lg) {
                metricChip(label: "Reliquat", value: snapshot.reliquat.map { $0.formatted } ?? "—")
                metricChip(label: "Métier", value: snapshot.jobLevel.map { "\($0)" } ?? "—")
                metricChip(label: "Historique", value: "\(snapshot.history.count)")
                metricChip(label: "Stats OCR", value: "\(snapshot.item?.stats.count ?? 0)")
            }

            // Stats parsées — UNIQUEMENT si pas d'item sélectionné (sinon c'est affiché dans Item à mager)
            if !hasItemSelected, let stats = snapshot.item?.stats, !stats.isEmpty {
                Text("Stats brutes parsées")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .textCase(.uppercase)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                        statRow(stat: stat)
                    }
                }
            }

            if hasItemSelected {
                Text("Stats de l'item visibles dans la carte « Item à mager »")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .italic()
            }

            // History
            if !snapshot.history.isEmpty {
                Divider().background(Theme.Colors.border)
                Text("Derniers combines")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .textCase(.uppercase)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(snapshot.history.suffix(5).enumerated()), id: \.offset) { _, h in
                        historyRow(h)
                    }
                }
            }
        }
    }

    private func metricChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surfaceElev)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func statRow(stat: Stat) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(appState.displayName(for: stat.kind))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: 160, alignment: .leading)

            Text("\(stat.value)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(stat.isAtMax ? Theme.Colors.gold : Theme.Colors.accent)
                .frame(width: 50, alignment: .trailing)

            if let min = stat.minValue, let max = stat.maxValue {
                Text("(\(min) - \(max))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: 90, alignment: .leading)
                if let progress = stat.rangeProgress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.Colors.surfaceElev)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(stat.isAtMax ? Theme.Colors.gold : Theme.Colors.accent)
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 4)
                }
            } else {
                Spacer()
            }

            // Rune availability (Pa / Ra counts)
            if let av = stat.availability {
                HStack(spacing: 4) {
                    if av.paCount > 0 {
                        runeBadge(label: "Pa", count: av.paCount)
                    }
                    if av.raCount > 0 {
                        runeBadge(label: "Ra", count: av.raCount)
                    }
                }
                .frame(width: 120, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }

    private func runeBadge(label: String, count: Int) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Theme.Colors.surfaceElev)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func historyRow(_ h: MageHistoryEntry) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(historyColor(h.result))
                .frame(width: 6, height: 6)
            Text(h.delta > 0 ? "+\(h.delta)" : "\(h.delta)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(historyColor(h.result))
                .frame(width: 32, alignment: .trailing)
            if let stat = h.targetStat {
                Text(appState.displayName(for: stat))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                Text(h.raw)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            Spacer()
        }
    }

    private func historyColor(_ result: MageHistoryEntry.Result) -> Color {
        switch result {
        case .criticalSuccess: return Theme.Colors.success
        case .criticalFail: return Theme.Colors.danger
        case .neutralSuccess: return Theme.Colors.warning
        case .unknown: return Theme.Colors.textTertiary
        }
    }

    private func stateDiffView(_ diff: StateDiff) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Changements détectés")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
            ForEach(Array(diff.changes.enumerated()), id: \.offset) { _, change in
                Text(describeChange(change))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
    }

    @State private var debugExpanded = false

    private func rawOCRDebugView(_ raw: RawOCRSnapshot) -> some View {
        DisclosureGroup(isExpanded: $debugExpanded) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(Array(raw.results.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { kind in
                    if let r = raw.results[kind] {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(kind.shortName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Spacer()
                                Text("\(String(format: "%.0f", r.elapsedMs)) ms · conf \(String(format: "%.2f", r.averageConfidence))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            Text(r.joinedText.isEmpty ? "(vide)" : r.joinedText)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .textSelection(.enabled)
                                .padding(Theme.Spacing.sm)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.Colors.surfaceElev)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        }
                    }
                }
            }
            .padding(.top, Theme.Spacing.sm)
        } label: {
            HStack {
                Text("OCR brut (debug)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .textCase(.uppercase)
                Spacer()
            }
        }
        .tint(Theme.Colors.textSecondary)
    }

    private func describeChange(_ change: StateDiff.Change) -> String {
        switch change {
        case .itemSwapped: return "→ item changé"
        case .combineLanded(let entries): return "→ combine landed (\(entries.count) entrées)"
        case .statChanged(let kind, let old, let new):
            return "→ \(appState.displayName(for: kind)) : \(old) → \(new)"
        case .reliquatChanged(let old, let new):
            return "→ reliquat : \(String(format: "%.1f", old)) → \(String(format: "%.1f", new))"
        case .jobLeveledUp(let old, let new):
            return "→ métier : niveau \(old) → \(new)"
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Diagnostics")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .padding(.top, Theme.Spacing.xxl)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                diagnosticRow(label: "Étape", value: flowStepLabel)
                diagnosticRow(label: "Permissions", value: appState.permissions.allGranted ? "OK" : "manquantes")
                diagnosticRow(label: "Dofus", value: appState.detectedWindow != nil ? "détecté" : "introuvable")
                diagnosticRow(label: "Profils", value: "\(appState.savedProfiles.count)")
            }

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .background(Theme.Colors.surface)
    }

    private func diagnosticRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var flowStepLabel: String {
        switch appState.flowStep {
        case .checkingPermissions: return "permissions…"
        case .missingPermissions: return "permissions manquantes"
        case .searchingDofus: return "recherche Dofus"
        case .capturingFirstFrame: return "capture"
        case .calibrating: return "calibration"
        case .ready: return "prêt"
        case .error(let msg): return "erreur: \(msg)"
        }
    }
}

// MARK: - Calibration container

private struct CalibrationContainer: View {
    let appState: AppState

    var body: some View {
        Group {
            if let frame = appState.calibrationFrame, appState.currentProfile != nil {
                CalibrationView(
                    profile: profileBinding,
                    image: frame,
                    onSave: { appState.saveCalibration() },
                    onCancel: { appState.cancelCalibration() },
                    onRecapture: { Task { await appState.recapture() } }
                )
            } else {
                ProgressView("Capture en cours…")
                    .controlSize(.large)
                    .tint(Theme.Colors.accent)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.bg)
            }
        }
    }

    private var profileBinding: Binding<ResolutionProfile> {
        Binding(
            get: { appState.currentProfile ?? ResolutionProfile(name: "", referenceSize: .zero) },
            set: { appState.currentProfile = $0 }
        )
    }
}

// MARK: - Card

private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
            content
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Colors.border, lineWidth: 1)
        )
    }
}

#Preview {
    ContentView()
}
