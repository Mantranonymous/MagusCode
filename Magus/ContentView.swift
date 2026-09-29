import MagusCommon
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
        @Bindable var bindable = appState
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
        .overlay(alignment: .top) {
            if let msg = appState.toastMessage {
                toastBanner(message: msg, isError: appState.toastIsError)
                    .padding(.top, Theme.Spacing.xl)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.toastMessage)
        .sheet(isPresented: $bindable.showOnboarding) {
            OnboardingSheet(appState: appState, isPresented: $bindable.showOnboarding)
        }
    }

    private func toastBanner(message: String, isError: Bool) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? Theme.Colors.danger : Theme.Colors.success)
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke((isError ? Theme.Colors.danger : Theme.Colors.success).opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 4)
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
                queueCard
                if let profile = appState.savedProfiles.first(where: { $0.isComplete }) {
                    ocrTestCard(profile: profile)
                }

                Spacer(minLength: Theme.Spacing.xxxl)
            }
            .padding(.horizontal, Theme.Spacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var queueCard: some View {
        Card(title: "File d'attente") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if appState.queue.isEmpty {
                    HStack {
                        Text("File vide. Ajoute l'item + preset courant à la file pour traiter plusieurs items en batch.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        MagusButton("Ajouter à la file", icon: "plus.circle", style: .secondary,
                                    isDisabled: appState.selectedItem == nil || appState.currentStatsPreset == nil) {
                            appState.addToQueue()
                        }
                    }
                } else {
                    ForEach(appState.queue) { item in
                        queueRow(item: item)
                    }
                    HStack {
                        MagusButton("Ajouter", icon: "plus.circle", style: .ghost,
                                    isDisabled: appState.selectedItem == nil || appState.currentStatsPreset == nil) {
                            appState.addToQueue()
                        }
                        Spacer()
                        if appState.isQueueActive {
                            MagusButton("Stopper la file", icon: "stop.circle", style: .danger) {
                                appState.stopQueue()
                            }
                        } else {
                            MagusButton("Vider la file", icon: "trash", style: .ghost) {
                                appState.clearQueue()
                            }
                            MagusButton("Démarrer la file", icon: "play.circle", style: .primary,
                                        isDisabled: appState.automation != .auto || appState.detectedWindow == nil) {
                                appState.startQueue()
                            }
                        }
                    }
                }
            }
        }
    }

    private func queueRow(item: QueueItem) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            statusBadge(for: item.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.itemName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(item.presetName)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            if item.status == .pending {
                Button {
                    appState.removeFromQueue(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    private func statusBadge(for status: QueueItem.Status) -> some View {
        let (color, icon): (Color, String) = {
            switch status {
            case .pending: return (Theme.Colors.textTertiary, "circle")
            case .current: return (Theme.Colors.accent, "arrow.right.circle.fill")
            case .done: return (Theme.Colors.success, "checkmark.circle.fill")
            case .skipped: return (Theme.Colors.warning, "xmark.circle.fill")
            }
        }()
        return Image(systemName: icon)
            .font(.system(size: 14))
            .foregroundStyle(color)
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
                        HStack {
                            Spacer()
                            MagusButton("Importer JSON", icon: "square.and.arrow.down", style: .ghost) {
                                appState.importPreset()
                            }
                            MagusButton("Importer .efitem", icon: "square.and.arrow.down.on.square", style: .ghost) {
                                appState.importEfitem()
                            }
                        }
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
                preferencesCard

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

                if !appState.permissions.allGranted {
                    HStack {
                        Text("Si tu viens de cocher dans Réglages, clique ici (macOS ne propage pas en live).")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Spacer()
                        MagusButton("Re-vérifier", icon: "arrow.clockwise", style: .ghost) {
                            appState.retryPermissions()
                        }
                    }
                    .padding(.top, Theme.Spacing.xs)
                }
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

    private var preferencesCard: some View {
        PreferencesCard(appState: appState)
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
    @State private var showPresetEditor = false
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
                            sessionLiveStats
                        }
                        Spacer()
                        sessionButtons
                    }
                    automationControls

                    if let preset = appState.currentStatsPreset, preset.isMultiStep {
                        stepProgressRow(preset: preset)
                    }

                    actionPrimaryRow(decision: decision)

                    Text(decision.explanation)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let probas = appState.currentProbabilities {
                        probabilityRow(probas: probas)
                    }
                    if !appState.currentRiskDrops.isEmpty {
                        riskDropsRow(drops: appState.currentRiskDrops)
                    }
                    if !appState.depletedRunes.isEmpty {
                        depletedRunesRow
                    }
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

    private func stepProgressRow(preset: StatsPreset) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "list.number")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.accent)
            let name = preset.stepName(at: appState.currentStepIndex) ?? "Étape \(appState.currentStepIndex + 1)"
            Text("Étape \(appState.currentStepIndex + 1)/\(preset.stepCount) · \(name)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            if appState.currentStepIndex < preset.stepCount - 1 {
                MagusButton("Passer", icon: "forward", style: .ghost) {
                    appState.skipCurrentStep()
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 6)
        .background(Theme.Colors.accent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private var sessionLiveStats: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle().fill(Theme.Colors.success).frame(width: 6, height: 6)
            Text("\(appState.sessionCombineCount) combines")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.Colors.textSecondary)
            scLabel(count: appState.sessionScCount, color: Theme.Colors.success, label: "SC")
            scLabel(count: appState.sessionSnCount, color: Theme.Colors.warning, label: "SN")
            scLabel(count: appState.sessionEcCount, color: Theme.Colors.danger, label: "EC")
            if let rem = appState.estimatedMinutesRemaining {
                Text("· ~\(rem) min restantes")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private func scLabel(count: Int, color: Color, label: String) -> some View {
        HStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private func probabilityRow(probas: SuccessProbabilityModel.Probabilities) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            probaBlock(pct: probas.sc, label: "SC", color: Theme.Colors.success)
            probaBlock(pct: probas.sn, label: "SN", color: Theme.Colors.warning)
            probaBlock(pct: probas.ec, label: "EC", color: Theme.Colors.danger)
            Spacer()
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.surfaceElev)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func probaBlock(pct: Double, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(Int((pct * 100).rounded()))%")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private func riskDropsRow(drops: [RiskSimulator.PredictedDrop]) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.Colors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Si échec, chutes probables :")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.textTertiary)
                let text = drops.map { d in
                    "\(appState.displayName(for: d.kind)) −\(d.estimatedPointsLost) (\(Int((d.probability * 100).rounded()))%)"
                }.joined(separator: ", ")
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.warning)
            }
        }
    }

    private var depletedRunesRow: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "nosign")
                .font(.system(size: 10))
                .foregroundStyle(Theme.Colors.danger)
            VStack(alignment: .leading, spacing: 4) {
                Text("Runes épuisées (\(appState.depletedRunes.count)) :")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.textTertiary)
                let names = appState.depletedRunes.map { rune in
                    let prefix = rune.power.prefix.isEmpty ? "" : "\(rune.power.prefix) "
                    return "\(prefix)\(appState.displayName(for: rune.kind))"
                }.sorted().joined(separator: ", ")
                Text(names)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.danger)
            }
            Spacer()
            MagusButton("Réinitialiser", style: .ghost) {
                appState.resetDepletedRunes()
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
                            HStack(spacing: Theme.Spacing.sm) {
                                Text(item.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                if let preset = appState.currentStatsPreset {
                                    Text("PRESET ACTIF · \(preset.name)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Theme.Colors.success)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Theme.Colors.success.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
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

                    // Sélecteur de scénario via Menu (9+ scénarios, le HStack pills overflow)
                    Divider().background(Theme.Colors.border)
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("Scénario")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .textCase(.uppercase)
                        Menu {
                            ForEach(PresetScenario.allCases, id: \.self) { scenario in
                                Button {
                                    appState.setScenario(scenario)
                                } label: {
                                    if appState.currentScenario == scenario {
                                        Label(scenario.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(scenario.displayName)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: scenarioIcon(appState.currentScenario))
                                    .font(.system(size: 11))
                                Text(appState.currentScenario.displayName)
                                    .font(.system(size: 12, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9))
                            }
                            .foregroundStyle(Theme.Colors.accent)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, 6)
                            .background(Theme.Colors.accent.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        // Toggle alternance PA/PM si scenario exo
                        if appState.currentScenario == .exoPA || appState.currentScenario == .exoPM {
                            Toggle(isOn: Binding(
                                get: { appState.currentConfigPreset.alternateExoPAPM },
                                set: { appState.currentConfigPreset.alternateExoPAPM = $0 }
                            )) {
                                Text("Alterner PA↔PM")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                        Spacer()
                        MagusButton("Remplir depuis l'item", icon: "arrow.down.doc", style: .ghost,
                                    isDisabled: appState.lastParsedSnapshot?.item == nil) {
                            appState.fillPresetFromCurrentItem()
                        }
                        MagusButton("Éditer", icon: "slider.horizontal.3", style: .ghost,
                                    isDisabled: appState.currentStatsPreset == nil) {
                            showPresetEditor = true
                        }
                        MagusButton("Sauvegarder", icon: "square.and.arrow.down", style: .secondary) {
                            appState.saveCurrentPreset()
                        }
                        MagusButton("Exporter", icon: "square.and.arrow.up", style: .ghost,
                                    isDisabled: appState.currentStatsPreset == nil) {
                            appState.exportCurrentPreset()
                        }
                    }

                    Divider().background(Theme.Colors.border)

                    // Toutes les stats sont mageables : même une stat "1-1" peut tomber
                    // pendant le maging et doit être remontée. On les affiche toutes dans
                    // une seule liste, triées : variables d'abord puis fixes/overables.
                    let sortedStats = item.stats.sorted { a, b in
                        if a.hasVariableRange != b.hasVariableRange { return a.hasVariableRange }
                        return a.order < b.order
                    }
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Stats de l'item (\(sortedStats.count))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .textCase(.uppercase)
                            ForEach(sortedStats, id: \.kind) { spec in
                                itemSpecStatRow(spec: spec, isFixed: !spec.hasVariableRange)
                            }
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                    .frame(maxHeight: 380)
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
        .sheet(isPresented: $showPresetEditor) {
            if let preset = appState.currentStatsPreset {
                PresetEditorSheet(appState: appState, isPresented: $showPresetEditor, preset: preset)
            }
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

    private func scenarioIcon(_ scenario: PresetScenario) -> String {
        switch scenario {
        case .jetParfait: return "checkmark.seal"
        case .exoPA: return "1.circle"
        case .exoPM: return "2.circle"
        case .exoDoSort1, .exoDoSort2: return "sparkles"
        case .exoDoDistance1, .exoDoDistance2: return "scope"
        case .overVita: return "heart.fill"
        case .leveling: return "arrow.up.right"
        }
    }

    private func itemSpecStatRow(spec: StatSpec, isFixed: Bool) -> some View {
        StatRowEditable(spec: spec, isFixed: isFixed, appState: appState)
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

// MARK: - Stat Row Editable

private struct StatRowEditable: View {
    let spec: StatSpec
    let isFixed: Bool
    let appState: AppState
    @State private var targetInput: String = ""
    @State private var minInput: String = ""
    @State private var isExpanded: Bool = false
    @FocusState private var focusedField: Field?

    enum Field { case target, minimum }

    var body: some View {
        let currentValue = appState.lastParsedSnapshot?.item?.stat(matching: spec.kind)?.value
        let displayName = appState.displayName(for: spec.kind)
        let currentTarget = appState.currentStatsPreset?.targets[spec.kind]
        let isEnabled = currentTarget?.enabled ?? false
        let target = currentTarget?.target ?? spec.maxValue
        let priority = currentTarget?.priority ?? 100
        let progressColor = progressColor(value: currentValue, target: target)

        VStack(alignment: .leading, spacing: 6) {
            // Ligne principale compacte
            HStack(spacing: Theme.Spacing.md) {
                // Toggle pill stylé
                Button(action: { appState.toggleEnabled(for: spec.kind) }) {
                    Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isEnabled ? Theme.Colors.accent : Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)

                // Nom + sous-ligne range
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName)
                        .font(.system(size: 12, weight: isEnabled ? .semibold : .regular))
                        .foregroundStyle(isEnabled ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                    Text("range \(spec.minValue)–\(spec.maxValue)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .frame(width: 160, alignment: .leading)

                // Valeur courante / cible avec barre de progression compacte
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if let v = currentValue {
                            Text("\(v)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(v >= target ? Theme.Colors.success : progressColor)
                        } else {
                            Text("—").font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        Text("/")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        TextField("0", text: $targetInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(isEnabled ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                            .multilineTextAlignment(.center)
                            .frame(width: 36)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.surfaceElev)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .focused($focusedField, equals: .target)
                            .onSubmit { commitTarget() }
                    }
                    // Barre de progression
                    progressBar(value: currentValue, target: target, color: progressColor)
                        .frame(width: 110, height: 3)
                }

                // Badge priorité (cliquable pour expand)
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    HStack(spacing: 3) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 9))
                        Text("\(priority)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(priorityColor(priority))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(priorityColor(priority).opacity(0.15))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                // Indicateur expand
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }
            }

            // Section dépliable : Min + Priority + actions rapides
            if isExpanded {
                HStack(spacing: Theme.Spacing.md) {
                    // Min input
                    HStack(spacing: 4) {
                        Text("Min")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        TextField("auto", text: $minInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .frame(width: 40)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.surfaceElev)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .focused($focusedField, equals: .minimum)
                            .onSubmit { commitMin() }
                    }
                    // Slider priorité
                    HStack(spacing: 4) {
                        Text("Priorité")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Slider(value: Binding(
                            get: { Double(priority) },
                            set: { appState.updateStat(for: spec.kind, priority: Int($0)) }
                        ), in: 0...150, step: 10)
                        .frame(width: 100)
                        Text("\(priority)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(priorityColor(priority))
                            .frame(width: 24, alignment: .trailing)
                    }
                    Spacer()
                    // Actions rapides
                    Button("Max") {
                        appState.updateStat(for: spec.kind, target: spec.maxValue)
                        targetInput = String(spec.maxValue)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.accent)
                    Button("Min") {
                        appState.updateStat(for: spec.kind, target: spec.minValue)
                        targetInput = String(spec.minValue)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.leading, 28)
                .padding(.vertical, 4)
                .background(Theme.Colors.surfaceElev.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, Theme.Spacing.xs)
        .background(isEnabled ? Color.clear : Theme.Colors.surfaceElev.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .opacity(isFixed && !isEnabled ? 0.5 : 1.0)
        .onAppear {
            targetInput = String(target)
            minInput = currentTarget?.minimum.map(String.init) ?? ""
        }
        // Re-sync les champs si le preset change depuis l'extérieur (import .efitem,
        // changement de scénario, etc.) — sinon les TextField gardent leur ancien texte.
        .onChange(of: target) { _, newValue in
            if !targetIsFocused { targetInput = String(newValue) }
        }
        // Commit LIVE sur chaque frappe : le bot tourne en continu, l'utilisateur
        // ne doit pas avoir à press Enter pour que sa nouvelle cible soit prise en compte.
        .onChange(of: targetInput) { _, _ in commitTarget() }
        .onChange(of: minInput) { _, _ in commitMin() }
        .onChange(of: focusedField) { _, newFocus in
            if newFocus != .target { commitTarget() }
            if newFocus != .minimum { commitMin() }
        }
    }

    private var targetIsFocused: Bool { focusedField == .target }

    private func commitTarget() {
        guard let n = Int(targetInput), n >= 0 else { return }
        // Évite la boucle d'update si la valeur est déjà à jour
        if appState.currentStatsPreset?.targets[spec.kind]?.target == n { return }
        appState.updateStat(for: spec.kind, target: n)
    }

    private func commitMin() {
        if minInput.isEmpty {
            if appState.currentStatsPreset?.targets[spec.kind]?.minimum != nil {
                appState.updateStat(for: spec.kind, minimum: .some(nil))
            }
        } else if let n = Int(minInput) {
            if appState.currentStatsPreset?.targets[spec.kind]?.minimum != n {
                appState.updateStat(for: spec.kind, minimum: .some(n))
            }
        }
    }

    private func progressColor(value: Int?, target: Int) -> Color {
        guard let v = value, target > 0 else { return Theme.Colors.textTertiary }
        let ratio = Double(v) / Double(target)
        if ratio >= 1.0 { return Theme.Colors.success }
        if ratio >= 0.7 { return Theme.Colors.accent }
        if ratio >= 0.3 { return Theme.Colors.warning }
        return Theme.Colors.danger
    }

    private func priorityColor(_ p: Int) -> Color {
        switch p {
        case 120...: return Theme.Colors.danger      // PA/PM critique
        case 100..<120: return Theme.Colors.accent   // standard
        case 60..<100: return Theme.Colors.warning   // moyen
        default: return Theme.Colors.textTertiary    // bas
        }
    }

    @ViewBuilder
    private func progressBar(value: Int?, target: Int, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Colors.surfaceElev)
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: progressWidth(value: value, target: target, total: geo.size.width))
            }
        }
    }

    private func progressWidth(value: Int?, target: Int, total: CGFloat) -> CGFloat {
        guard let v = value, target > 0 else { return 0 }
        let ratio = min(1.0, Double(v) / Double(target))
        return CGFloat(ratio) * total
    }
}

// MARK: - Preferences Card

private struct PreferencesCard: View {
    let appState: AppState

    var body: some View {
        @Bindable var settings = appState.settings
        Card(title: "Préférences") {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // VLM Fallback
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: Theme.Spacing.xs) {
                                Text("Fallback VLM")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text("expérimental")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.warning)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.Colors.warning.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            Text("Quand Apple Vision a une confiance basse sur une zone, tenter Qwen2.5-VL (MLX) en relais. Moteur VLM non packagé pour l'instant — toggle prêt pour activation future.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.vlmFallbackEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    if settings.vlmFallbackEnabled {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            HStack {
                                Text("Seuil de confiance")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                Spacer()
                                Text(String(format: "%.2f", settings.vlmConfidenceThreshold))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                            Slider(value: $settings.vlmConfidenceThreshold, in: 0.3...0.95, step: 0.05)
                            Text("Sous ce seuil de confiance Vision, le VLM prend le relais.")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .padding(Theme.Spacing.sm)
                        .background(Theme.Colors.surfaceElev)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                }

                Divider().background(Theme.Colors.border)

                // Click marker toggle
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Afficher le marqueur de clic")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Cercle visuel au point du prochain clic auto/démo.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.showClickMarker)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Divider().background(Theme.Colors.border)

                // Mode Turbo
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: Theme.Spacing.xs) {
                                Text("Mode Turbo")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text("risqué")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.danger)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.Colors.danger.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            Text("Throttle 250ms, click toutes les 800ms, pas de pauses anti-detect, click direct sans courbe humaine. ~2-3× plus rapide.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.turboMode)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    if settings.turboMode {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Colors.danger)
                            Text("Détection Ankama plus probable. À réserver aux comptes jetables.")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.Colors.danger)
                        }
                        .padding(Theme.Spacing.sm)
                        .background(Theme.Colors.danger.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                }

                Divider().background(Theme.Colors.border)

                // OCR Preprocessing
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Upscaling OCR")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("Multiplie la taille de l'image avant OCR (Lanczos). 2x = meilleur compromis perf/qualité, 3x = max qualité mais plus lent.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Text("×\(String(format: "%.1f", settings.ocrUpscaleFactor))")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(width: 40, alignment: .trailing)
                    }
                    Slider(value: $settings.ocrUpscaleFactor, in: 1.0...4.0, step: 0.5)
                }

                Divider().background(Theme.Colors.border)

                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Binarisation OCR")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Convertit en N&B + contraste boosté. Utile sur les items très sombres. Peut rater du texte clair.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.ocrBinarize)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Divider().background(Theme.Colors.border)

                // Alertes sonores
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Alertes sonores")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Joue un son sur succès / échec / régression. Utile en arrière-plan.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.soundsEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Divider().background(Theme.Colors.border)

                // Log level
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Niveau de log")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Filtre des messages affichés dans Diagnostics.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    Picker("", selection: $settings.logLevel) {
                        ForEach(AppSettings.LogLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }

                Divider().background(Theme.Colors.border)

                // Network observation (passive)
                NetworkObservationSection(appState: appState)

                Divider().background(Theme.Colors.border)

                // Actions
                HStack(spacing: Theme.Spacing.md) {
                    MagusButton("Rejouer l'onboarding", icon: "arrow.counterclockwise", style: .secondary) {
                        appState.replayOnboarding()
                    }
                    MagusButton("Restaurer défauts", icon: "arrow.uturn.backward", style: .ghost) {
                        appState.settings.resetToDefaults()
                    }
                    Spacer()
                }
            }
        }
    }
}

/// Section dédiée au mode observation réseau passive (`MagusNetwork`).
/// Affiche le toggle principal + paramètres (port, path Dofus) + bouton de
/// test + statut live (PID, connexions, paquets observés).
private struct NetworkObservationSection: View {
    let appState: AppState
    @State private var isStarting = false
    @State private var isTesting = false

    var body: some View {
        @Bindable var settings = appState.settings
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("Observation réseau passive")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("expérimental")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.Colors.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.warning.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Text("Décode les paquets Protobuf entre Dofus et Ankama pour reconstruire l'état exact de la session FM. Aucune injection ni forge de paquet — les actions restent simulées via clavier/souris.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.networkObservationEnabled },
                    set: { newValue in
                        settings.networkObservationEnabled = newValue
                        Task {
                            if newValue {
                                isStarting = true
                                await appState.startNetworkObservation()
                                isStarting = false
                            } else {
                                appState.stopNetworkObservation()
                            }
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(isStarting)
            }

            if settings.networkObservationEnabled {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Text("Port proxy local")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        TextField("7975", value: Binding(
                            get: { Int(settings.networkProxyPort) },
                            set: { newValue in
                                let clamped = max(1024, min(65535, newValue))
                                settings.networkProxyPort = UInt16(clamped)
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    }
                    HStack {
                        Text("Chemin Dofus")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        TextField("/Applications/.../Dofus", text: $settings.networkDofusPath)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 360)
                    }

                    HStack(spacing: Theme.Spacing.sm) {
                        MagusButton(
                            isTesting ? "Test…" : "Tester",
                            icon: "wand.and.rays",
                            style: .secondary
                        ) {
                            Task {
                                isTesting = true
                                await appState.runNetworkDiagnostic()
                                isTesting = false
                            }
                        }
                        .disabled(isTesting)
                        Spacer()
                        statusBadge
                    }

                    if let error = appState.networkLastError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Colors.danger)
                            Text(error)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.Colors.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text("Setup : `npm install` dans Sources/MagusNetwork/Frida/ puis `./generate.sh` dans Sources/MagusNetwork/Protos/. Voir README du module.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.surfaceElev)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.networkObserver.isObserving ? Theme.Colors.success : Theme.Colors.textTertiary)
                .frame(width: 8, height: 8)
            if appState.networkObserver.isObserving {
                VStack(alignment: .trailing, spacing: 2) {
                    if let pid = appState.networkObserver.dofusPid {
                        Text("PID \(pid)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Text("\(appState.networkObserver.packetCount) paquets / \(appState.networkObserver.redirectedConnectionCount) cnx")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } else {
                Text("inactif")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }
}

#Preview {
    ContentView()
}
