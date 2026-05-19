import AppKit
import MagusCommon
import MagusUI
import SwiftUI

/// Fenêtre Diagnostics affichable via ⌥⌘D.
/// Affiche : logs récents, dernière OCR, dernière décision, snapshot, métriques.
struct DiagnosticsView: View {
    let appState: AppState
    @State private var refreshTick = 0
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Logs").tag(0)
                Text("État détecté").tag(1)
                Text("OCR brut").tag(2)
                Text("Decision").tag(3)
                Text("Système").tag(4)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)

            Divider().background(Theme.Colors.border)

            ScrollView {
                Group {
                    switch selectedTab {
                    case 0: logsPanel
                    case 1: parsedPanel
                    case 2: rawOCRPanel
                    case 3: decisionPanel
                    case 4: systemPanel
                    default: EmptyView()
                    }
                }
                .padding(Theme.Spacing.lg)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Theme.Colors.bg)
        .preferredColorScheme(.dark)
    }

    private var logsPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(LogBuffer.shared.snapshot().count) entries")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
                Spacer()
                MagusButton("Clear", style: .ghost) { LogBuffer.shared.clear(); refreshTick += 1 }
                MagusButton("Refresh", icon: "arrow.clockwise", style: .secondary) { refreshTick += 1 }
            }
            ForEach(Array(LogBuffer.shared.snapshot().reversed().prefix(200).enumerated()), id: \.offset) { _, entry in
                logRow(entry: entry)
            }
        }
        .id(refreshTick)
    }

    private func logRow(entry: LogBuffer.Entry) -> some View {
        let color: Color = {
            switch entry.level {
            case "ERROR", "FAULT": return Theme.Colors.danger
            case "WARNING": return Theme.Colors.warning
            default: return Theme.Colors.textSecondary
            }
        }()
        let timestamp = entry.timestamp.formatted(date: .omitted, time: .standard)
        return HStack(alignment: .top, spacing: 6) {
            Text(timestamp)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(entry.level)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 50, alignment: .leading)
            Text(entry.category)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 80, alignment: .leading)
            Text(entry.message)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private var parsedPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snap = appState.lastParsedSnapshot {
                kv("Timestamp", snap.timestamp.formatted())
                kv("Reliquat", snap.reliquat.map { $0.formatted } ?? "—")
                kv("Job level", snap.jobLevel.map(String.init) ?? "—")
                kv("History count", "\(snap.history.count)")
                kv("Stats count", "\(snap.item?.stats.count ?? 0)")
                Text("Stats détectées")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                ForEach(Array((snap.item?.stats ?? []).enumerated()), id: \.offset) { _, stat in
                    Text("• \(appState.displayName(for: stat.kind)) = \(stat.value)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } else {
                Text("Pas de snapshot.").foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private var rawOCRPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let raw = appState.lastOCRSnapshot {
                kv("Total OCR", String(format: "%.1f ms", raw.totalElapsedMs))
                ForEach(Array(raw.results.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { kind in
                    if let r = raw.results[kind] {
                        Text(kind.shortName + " (\(String(format: "%.1f", r.elapsedMs)) ms)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                        Text(r.joinedText.isEmpty ? "(vide)" : r.joinedText)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(Theme.Spacing.sm)
                            .background(Theme.Colors.surfaceElev)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            } else {
                Text("Pas d'OCR récent.").foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private var decisionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let d = appState.currentDecision {
                kv("Type", "\(d)")
                Text("Explication")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text(d.explanation)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                Text("Pas de décision.").foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private var systemPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            kv("Session active", appState.isSessionActive ? "OUI" : "non")
            kv("Mode auto", appState.automation.rawValue)
            kv("FPS session", String(format: "%.2f", appState.sessionFps))
            kv("Clicks auto", "\(appState.autoClickCount)")
            kv("Clicks démo", "\(appState.demoClickCount)")
            kv("Régressions", "\(appState.consecutiveRegressions)")
            kv("No-change", "\(appState.consecutiveNoChange)")
            kv("Fenêtre Dofus", appState.detectedWindow != nil ? "détectée" : "absente")
            kv("Permissions OK", appState.permissions.allGranted ? "oui" : "non")
            kv("Profils calibrés", "\(appState.savedProfiles.count)")
            kv("Item sélectionné", appState.selectedItem?.name ?? "—")
            kv("Preset courant", appState.currentStatsPreset?.name ?? "—")
            kv("Presets sauvegardés", "\(appState.savedPresets.count)")
            kv("File d'attente", "\(appState.queue.count) items")
            kv("DofusDB", appState.dofusDBVersion ?? "—")
            kv("Log file", FileLogger.shared.logFileURL?.path ?? "—")
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: 180, alignment: .leading)
            Text(v)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.Colors.textSecondary)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

@MainActor
final class DiagnosticsController {
    private var window: NSWindow?
    private var hosting: NSHostingController<DiagnosticsView>?

    func toggle(appState: AppState) {
        if let w = window, w.isVisible {
            w.orderOut(nil)
            return
        }
        if window == nil {
            let hosting = NSHostingController(rootView: DiagnosticsView(appState: appState))
            let w = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false
            )
            w.title = "Magus — Diagnostics"
            w.contentViewController = hosting
            self.window = w
            self.hosting = hosting
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
