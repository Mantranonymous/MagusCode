import CoreGraphics
import MagusCore
import SwiftUI

/// Canvas qui affiche le screenshot Dofus et permet de tracer la région courante
/// par drag-to-draw. Convertit les coordonnées view → normalized rect.
struct CalibrationCanvas: View {

    let image: CGImage
    @Binding var profile: ResolutionProfile
    let currentKind: RegionKind
    let onRegionDefined: (RegionKind) -> Void

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let displayedRect = aspectFitRect(imageSize: imageSize, in: geo.size)

            ZStack(alignment: .topLeading) {
                // Background grid (subtle)
                Theme.Colors.bg

                // Screenshot
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: displayedRect.width, height: displayedRect.height)
                    .position(x: displayedRect.midX, y: displayedRect.midY)
                    .overlay(
                        // Existing regions
                        existingRegionsOverlay(displayedRect: displayedRect)
                    )
                    .overlay(
                        // Currently being drawn rectangle
                        currentDragOverlay(displayedRect: displayedRect)
                    )
                    .overlay(
                        Rectangle()
                            .stroke(Theme.Colors.border, lineWidth: 1)
                            .frame(width: displayedRect.width, height: displayedRect.height)
                            .position(x: displayedRect.midX, y: displayedRect.midY)
                    )

                // Hint label
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        hintLabel
                        Spacer()
                    }
                    .padding(.bottom, Theme.Spacing.lg)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        let clamped = clamp(value.location, to: displayedRect)
                        if dragStart == nil {
                            dragStart = clamp(value.startLocation, to: displayedRect)
                        }
                        dragCurrent = clamped
                    }
                    .onEnded { _ in
                        defer {
                            dragStart = nil
                            dragCurrent = nil
                        }
                        guard let start = dragStart, let end = dragCurrent else { return }
                        let viewRect = CGRect(
                            x: min(start.x, end.x),
                            y: min(start.y, end.y),
                            width: abs(end.x - start.x),
                            height: abs(end.y - start.y)
                        )
                        guard viewRect.width > 6, viewRect.height > 6 else { return }
                        let normalized = normalize(viewRect: viewRect, displayedRect: displayedRect)
                        let region = Region(kind: currentKind, bounds: normalized)
                        profile.setRegion(region)
                        onRegionDefined(currentKind)
                    }
            )
        }
    }

    private var imageSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }

    private var hintLabel: some View {
        Group {
            if profile.regions[currentKind] != nil {
                Text("Trace une nouvelle zone pour redéfinir « \(currentKind.displayName) »")
            } else {
                Text("Trace la zone « \(currentKind.displayName) » sur la capture")
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surface.opacity(0.85))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.Colors.border, lineWidth: 1))
    }

    // MARK: - Overlays

    private func existingRegionsOverlay(displayedRect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(Array(profile.regions.values), id: \.id) { region in
                let r = denormalize(rect: region.bounds, displayedRect: displayedRect, relativeTo: .topLeading)
                let isCurrent = region.kind == currentKind
                let color = isCurrent ? Theme.Colors.accent : Theme.Colors.success

                Rectangle()
                    .strokeBorder(color, lineWidth: 2)
                    .background(color.opacity(0.12))
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX, y: r.midY)

                Text(region.kind.shortName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .fixedSize()
                    .position(x: r.minX + 20, y: max(8, r.minY - 8))
            }
        }
        .allowsHitTesting(false)
    }

    private func currentDragOverlay(displayedRect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let start = dragStart, let end = dragCurrent {
                // Conversion en coords image-local
                let x = min(start.x, end.x) - displayedRect.minX
                let y = min(start.y, end.y) - displayedRect.minY
                let w = abs(end.x - start.x)
                let h = abs(end.y - start.y)

                Rectangle()
                    .strokeBorder(Theme.Colors.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(Theme.Colors.accent.opacity(0.15))
                    .frame(width: w, height: h)
                    .position(x: x + w / 2, y: y + h / 2)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Coordinate conversion

    private func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        let imgAspect = imageSize.width / imageSize.height
        let cntAspect = container.width / container.height
        let size: CGSize
        if imgAspect > cntAspect {
            size = CGSize(width: container.width, height: container.width / imgAspect)
        } else {
            size = CGSize(width: container.height * imgAspect, height: container.height)
        }
        let origin = CGPoint(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2
        )
        return CGRect(origin: origin, size: size)
    }

    private func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func normalize(viewRect: CGRect, displayedRect: CGRect) -> NormalizedRect {
        NormalizedRect(
            x: (viewRect.minX - displayedRect.minX) / displayedRect.width,
            y: (viewRect.minY - displayedRect.minY) / displayedRect.height,
            width: viewRect.width / displayedRect.width,
            height: viewRect.height / displayedRect.height
        )
    }

    private func denormalize(rect: NormalizedRect, displayedRect: CGRect, relativeTo: UnitPoint) -> CGRect {
        CGRect(
            x: rect.x * displayedRect.width,
            y: rect.y * displayedRect.height,
            width: rect.width * displayedRect.width,
            height: rect.height * displayedRect.height
        )
    }
}
