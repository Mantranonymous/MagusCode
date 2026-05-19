import MagusCore
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
            Divider().background(Theme.Colors.border)
            inspector
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
                sidebarItem(icon: "wand.and.stars", label: "Activité", isActive: true)
                sidebarItem(icon: "books.vertical", label: "Bibliothèque", isActive: false)
                sidebarItem(icon: "gearshape", label: "Réglages", isActive: false)
            }
            .padding(.horizontal, Theme.Spacing.sm)

            Spacer()
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(Theme.Colors.surface)
    }

    private func sidebarItem(icon: String, label: String, isActive: Bool) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 18)
            Text(label)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
            Spacer()
        }
        .foregroundStyle(isActive ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(isActive ? Theme.Colors.surfaceElev : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private var workspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                Text("État du système")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.top, Theme.Spacing.xxxl)

                permissionsCard
                referenceCard
                dofusCard
                profilesCard
                if let profile = appState.savedProfiles.first(where: { $0.isComplete }) {
                    ocrTestCard(profile: profile)
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
            }
        }
    }

    private func parsedSnapshotView(_ snapshot: GameStateSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Top row : sink + job + history count
            HStack(spacing: Theme.Spacing.lg) {
                metricChip(label: "Sink", value: snapshot.sink.map { "\($0.percent)%" } ?? "—")
                metricChip(label: "Métier", value: snapshot.jobLevel.map { "\($0)" } ?? "—")
                metricChip(label: "Historique", value: "\(snapshot.history.count)")
                metricChip(label: "Stats", value: "\(snapshot.item?.stats.count ?? 0)")
            }

            // Stats parsées
            if let stats = snapshot.item?.stats, !stats.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                        statRow(stat: stat)
                    }
                }
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
        }
        .padding(.vertical, 2)
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
        case .success: return Theme.Colors.success
        case .failure: return Theme.Colors.danger
        case .neutral: return Theme.Colors.textSecondary
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

    private func describeChange(_ change: StateDiff.Change) -> String {
        switch change {
        case .itemSwapped: return "→ item changé"
        case .combineLanded(let entries): return "→ combine landed (\(entries.count) entrées)"
        case .statChanged(let kind, let old, let new):
            return "→ \(appState.displayName(for: kind)) : \(old) → \(new)"
        case .sinkChanged(let old, let new):
            return "→ sink : \(old)% → \(new)%"
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
