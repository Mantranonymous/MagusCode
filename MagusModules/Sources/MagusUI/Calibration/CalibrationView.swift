import CoreGraphics
import MagusCore
import SwiftUI

/// Vue de calibration : permet à l'utilisateur de tracer les 6 régions
/// (Stats, Historique, Sink, Inventaire runes, Niveau métier, Barre XP)
/// par-dessus un screenshot de la fenêtre Dofus.
///
/// La vue est "dumb" : elle prend l'image + un binding sur le profil,
/// et délègue le save/cancel via callbacks.
public struct CalibrationView: View {

    @Binding public var profile: ResolutionProfile
    public let image: CGImage
    public let onSave: () -> Void
    public let onCancel: () -> Void
    public let onRecapture: (() -> Void)?

    @State private var selectedKind: RegionKind = .stats

    public init(
        profile: Binding<ResolutionProfile>,
        image: CGImage,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onRecapture: (() -> Void)? = nil
    ) {
        self._profile = profile
        self.image = image
        self.onSave = onSave
        self.onCancel = onCancel
        self.onRecapture = onRecapture
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.Colors.border)
            HStack(spacing: 0) {
                sidebar
                Divider().background(Theme.Colors.border)
                canvasArea
            }
            Divider().background(Theme.Colors.border)
            actionBar
        }
        .background(Theme.Colors.bg)
    }

    // MARK: - Header

    private var requiredCount: Int { RegionKind.allCases.filter(\.isRequired).count }
    private var optionalCount: Int { RegionKind.allCases.filter { !$0.isRequired }.count }
    private var requiredDefined: Int { RegionKind.allCases.filter { $0.isRequired && profile.regions[$0] != nil }.count }
    private var optionalDefined: Int { RegionKind.allCases.filter { !$0.isRequired && profile.regions[$0] != nil }.count }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Calibration de la fenêtre Dofus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Trace les zones requises pour pouvoir sauvegarder. Les optionnelles peuvent être ajoutées plus tard.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            // Compteurs séparés requis / optionnels
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("\(requiredDefined)/\(requiredCount)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(profile.isComplete ? Theme.Colors.success : Theme.Colors.danger)
                        Text("requises")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        if profile.isComplete {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.Colors.success)
                        }
                    }
                    HStack(spacing: 4) {
                        Text("\(optionalDefined)/\(optionalCount)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text("optionnelles")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.lg)
        .background(Theme.Colors.surface)
    }

    // MARK: - Sidebar

    private var requiredKinds: [RegionKind] { RegionKind.allCases.filter(\.isRequired) }
    private var optionalKinds: [RegionKind] { RegionKind.allCases.filter { !$0.isRequired } }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                // Section requises
                Text("Zones requises")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .textCase(.uppercase)
                    .padding(.top, Theme.Spacing.lg)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.sm)

                ForEach(requiredKinds, id: \.self) { kind in
                    regionRow(for: kind)
                }

                // Section optionnelles
                HStack(spacing: 6) {
                    Text("Optionnelles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .textCase(.uppercase)
                    Text("skippables")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Colors.gold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.Colors.gold.opacity(0.15))
                        .clipShape(Capsule())
                }
                .padding(.top, Theme.Spacing.xl)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.sm)

                Text("Tu peux les ajouter plus tard via une nouvelle calibration sans perdre les requises.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.sm)

                ForEach(optionalKinds, id: \.self) { kind in
                    regionRow(for: kind)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(Theme.Colors.surface)
    }

    private func regionRow(for kind: RegionKind) -> some View {
        let isDefined = profile.regions[kind] != nil
        let isSelected = selectedKind == kind
        let dotState: StatusDot.State = isSelected ? .current : (isDefined ? .done : .pending)

        return Button {
            selectedKind = kind
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                StatusDot(state: dotState)
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.displayName)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(kind.isRequired ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                        .lineLimit(2)
                    if isDefined {
                        Text("✓ Calibré")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Colors.success)
                    } else if !kind.isRequired {
                        Text("non requis")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    } else {
                        Text("à tracer")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Colors.danger)
                    }
                }
                Spacer()
                if isDefined {
                    Button {
                        profile.removeRegion(kind: kind)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(4)
                            .background(Theme.Colors.surfaceElev)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(isSelected ? Theme.Colors.surfaceElev : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .padding(.horizontal, Theme.Spacing.xs)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        VStack(spacing: 0) {
            // Toolbar : info zone courante + bouton Passer
            HStack(spacing: Theme.Spacing.md) {
                HStack(spacing: 6) {
                    Image(systemName: selectedKind.isRequired ? "circle.fill" : "circle.dashed")
                        .font(.system(size: 10))
                        .foregroundStyle(selectedKind.isRequired ? Theme.Colors.danger : Theme.Colors.gold)
                    Text("Zone courante : ")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(selectedKind.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if !selectedKind.isRequired {
                        Text("OPTIONNEL")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.Colors.gold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.Colors.gold.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Spacer()
                // Bouton skip uniquement pour zones optionnelles non encore définies
                if !selectedKind.isRequired {
                    MagusButton("Passer", icon: "forward", style: .ghost) {
                        if let next = nextKind(after: selectedKind) {
                            selectedKind = next
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.surface.opacity(0.5))

            Divider().background(Theme.Colors.border)

            CalibrationCanvas(
                image: image,
                profile: $profile,
                currentKind: selectedKind,
                onRegionDefined: { kind in
                    // Avance vers la prochaine zone non définie
                    if let next = nextUndefinedKind(after: kind) {
                        selectedKind = next
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.bg)
        }
    }

    private func nextKind(after kind: RegionKind) -> RegionKind? {
        let all = RegionKind.allCases
        guard let idx = all.firstIndex(of: kind) else { return nil }
        return all[(idx + 1) % all.count]
    }

    private func nextUndefinedKind(after kind: RegionKind) -> RegionKind? {
        let all = RegionKind.allCases
        guard let idx = all.firstIndex(of: kind) else { return nil }
        for i in 1...all.count {
            let next = all[(idx + i) % all.count]
            if profile.regions[next] == nil {
                return next
            }
        }
        return nil
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let onRecapture = onRecapture {
                MagusButton("Recapturer", icon: "camera.fill", style: .ghost, action: onRecapture)
            }
            Spacer()
            MagusButton("Annuler", style: .secondary, action: onCancel)
            MagusButton(
                "Sauvegarder",
                icon: "checkmark",
                style: .primary,
                isDisabled: !profile.isComplete,
                action: onSave
            )
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.lg)
        .background(Theme.Colors.surface)
    }
}
