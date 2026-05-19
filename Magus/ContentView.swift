import MagusCore
import MagusPerception
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
        Card(title: "Test OCR — \(profile.name)") {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    if let snap = appState.lastOCRSnapshot {
                        Text("Dernier run : \(String(format: "%.1f", snap.totalElapsedMs)) ms · \(snap.results.count) régions")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(snap.totalElapsedMs < 200 ? Theme.Colors.success : Theme.Colors.warning)
                    } else {
                        Text("Aucun run encore. Lance Dofus avec un item sur l'établi puis clique « Lancer OCR ».")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    MagusButton(
                        appState.isRunningOCR ? "OCR en cours..." : "Lancer OCR",
                        icon: "text.viewfinder",
                        style: .primary,
                        isDisabled: appState.isRunningOCR || appState.detectedWindow == nil
                    ) {
                        Task { await appState.runOCRTest(profile: profile) }
                    }
                }
                if let snap = appState.lastOCRSnapshot {
                    Divider().background(Theme.Colors.border)
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ForEach(RegionKind.allCases, id: \.self) { kind in
                            ocrResultRow(kind: kind, result: snap.results[kind])
                        }
                    }
                }
            }
        }
    }

    private func ocrResultRow(kind: RegionKind, result: RegionOCRResult?) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(kind.shortName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if kind.dataType == .visual {
                        Text("visual")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Theme.Colors.gold.opacity(0.25))
                            .foregroundStyle(Theme.Colors.gold)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                if let r = result {
                    Text("\(String(format: "%.1f", r.elapsedMs)) ms · conf \(String(format: "%.2f", r.averageConfidence))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .frame(width: 100, alignment: .leading)

            Group {
                if kind.dataType == .visual {
                    Text("Zone visuelle — analyse pixel à venir en P2/P3")
                        .italic()
                        .foregroundStyle(Theme.Colors.textTertiary)
                } else if let r = result {
                    Text(r.joinedText)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    Text("—")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(4)
        }
        .padding(.vertical, Theme.Spacing.xs)
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
