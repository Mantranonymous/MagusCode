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

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Calibration de la fenêtre Dofus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Trace les 6 zones d'intérêt sur la capture")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            HStack(spacing: Theme.Spacing.sm) {
                Text("\(profile.regions.count) / 6")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(profile.isComplete ? Theme.Colors.success : Theme.Colors.textSecondary)
                if profile.isComplete {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.Colors.success)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.lg)
        .background(Theme.Colors.surface)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Zones")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .textCase(.uppercase)
                    .padding(.top, Theme.Spacing.lg)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.sm)

                ForEach(RegionKind.allCases, id: \.self) { kind in
                    regionRow(for: kind)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: 240)
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
                    .frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(kind.displayName)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if kind.dataType == .visual {
                            Text("visuelle")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Theme.Colors.gold.opacity(0.25))
                                .foregroundStyle(Theme.Colors.gold)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text(kind.dataType == .visual ? "Analyse pixel (P2+)" : kind.shortName)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                Spacer()
                if isDefined {
                    Button {
                        profile.removeRegion(kind: kind)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(4)
                            .background(Theme.Colors.surfaceElev)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background(isSelected ? Theme.Colors.surfaceElev : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .padding(.horizontal, Theme.Spacing.xs)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        CalibrationCanvas(
            image: image,
            profile: $profile,
            currentKind: selectedKind,
            onRegionDefined: { kind in
                // Avance automatiquement à la prochaine région non définie
                if let next = nextUndefinedKind(after: kind) {
                    selectedKind = next
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.bg)
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
