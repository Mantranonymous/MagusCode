import MagusCore
import MagusUI
import SwiftUI

struct PresetEditorSheet: View {
    let appState: AppState
    @Binding var isPresented: Bool
    @State private var workingPreset: StatsPreset

    init(appState: AppState, isPresented: Binding<Bool>, preset: StatsPreset) {
        self.appState = appState
        self._isPresented = isPresented
        self._workingPreset = State(initialValue: preset)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.Colors.border)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    nameAndScenarioCard
                    targetsCard
                    Spacer(minLength: 16)
                }
                .padding(Theme.Spacing.lg)
            }
            Divider().background(Theme.Colors.border)
            footer
        }
        .frame(width: 640, height: 720)
        .background(Theme.Colors.bg)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Éditeur de preset")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Ajuste cibles, priorités et activation par stat")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            MagusButton("Fermer", style: .ghost) { isPresented = false }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface)
    }

    private var nameAndScenarioCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Identité")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
            TextField("Nom du preset", text: $workingPreset.name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
            HStack {
                Text("Scénario :")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(workingPreset.scenario.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var targetsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Cibles par stat")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
            ForEach(Array(workingPreset.targets.keys.sorted(by: { $0.characteristicId < $1.characteristicId })), id: \.characteristicId) { kind in
                targetRow(kind: kind)
                Divider().background(Theme.Colors.border)
            }
            if workingPreset.targets.isEmpty {
                Text("Aucune cible. Choisis d'abord un item dans Activité pour auto-générer les cibles.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func targetRow(kind: StatKind) -> some View {
        let bindingTarget = Binding<Int>(
            get: { workingPreset.targets[kind]?.target ?? 0 },
            set: { newVal in
                if var t = workingPreset.targets[kind] {
                    t = StatTarget(target: newVal, minimum: t.minimum, priority: t.priority, enabled: t.enabled)
                    workingPreset.targets[kind] = t
                }
            }
        )
        let bindingPriority = Binding<Double>(
            get: { Double(workingPreset.targets[kind]?.priority ?? 100) },
            set: { newVal in
                if var t = workingPreset.targets[kind] {
                    t = StatTarget(target: t.target, minimum: t.minimum, priority: Int(newVal), enabled: t.enabled)
                    workingPreset.targets[kind] = t
                }
            }
        )
        let bindingEnabled = Binding<Bool>(
            get: { workingPreset.targets[kind]?.enabled ?? true },
            set: { newVal in
                if var t = workingPreset.targets[kind] {
                    t = StatTarget(target: t.target, minimum: t.minimum, priority: t.priority, enabled: newVal)
                    workingPreset.targets[kind] = t
                }
            }
        )
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("", isOn: bindingEnabled)
                    .toggleStyle(.switch)
                    .scaleEffect(0.75)
                Text(appState.displayName(for: kind))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(bindingEnabled.wrappedValue ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                Spacer()
                HStack(spacing: 4) {
                    Text("Cible")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    TextField("", value: bindingTarget, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .font(.system(size: 12, design: .monospaced))
                        .disabled(!bindingEnabled.wrappedValue)
                }
            }
            HStack {
                Text("Priorité \(Int(bindingPriority.wrappedValue))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: 80, alignment: .leading)
                Slider(value: bindingPriority, in: 0...100, step: 1)
                    .disabled(!bindingEnabled.wrappedValue)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack {
            MagusButton("Annuler", style: .ghost) { isPresented = false }
            Spacer()
            MagusButton("Sauvegarder", icon: "square.and.arrow.down", style: .primary) {
                appState.currentStatsPreset = workingPreset
                appState.saveCurrentPreset()
                isPresented = false
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface)
    }
}
