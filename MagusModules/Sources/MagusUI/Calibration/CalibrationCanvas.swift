import CoreGraphics
import MagusCore
import SwiftUI

/// Canvas qui affiche le screenshot Dofus et permet de :
/// - **Tracer** une nouvelle région par drag (si la région courante n'existe pas encore)
/// - **Déplacer** une région existante par drag sur son corps
/// - **Redimensionner** une région existante en draggant un des 4 handles de coin
struct CalibrationCanvas: View {

    let image: CGImage
    @Binding var profile: ResolutionProfile
    let currentKind: RegionKind
    let onRegionDefined: (RegionKind) -> Void

    @State private var interaction: Interaction = .idle

    // L'utilisateur clique sur "Retracer" sur la sidebar pour forcer un re-trace
    @State private var forceRedraw: Bool = false

    enum Corner: Sendable, Hashable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    enum Interaction: Sendable {
        case idle
        case drawing(startCanvas: CGPoint, currentCanvas: CGPoint)
        case moving(regionId: UUID, originalBounds: NormalizedRect, startCanvas: CGPoint)
        case resizing(regionId: UUID, originalBounds: NormalizedRect, corner: Corner, startCanvas: CGPoint)
    }

    var body: some View {
        GeometryReader { geo in
            let displayedRect = aspectFitRect(imageSize: imageSize, in: geo.size)

            ZStack(alignment: .topLeading) {
                // Background — assure que le ZStack remplit toute la geometry
                Color.clear

                // Screenshot Dofus
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: displayedRect.width, height: displayedRect.height)
                    .offset(x: displayedRect.minX, y: displayedRect.minY)

                // Bordure autour de l'image
                Rectangle()
                    .stroke(Theme.Colors.border, lineWidth: 1)
                    .frame(width: displayedRect.width, height: displayedRect.height)
                    .offset(x: displayedRect.minX, y: displayedRect.minY)

                // Régions déjà tracées
                ForEach(Array(profile.regions.values), id: \.id) { region in
                    regionOverlay(region: region, displayedRect: displayedRect)
                }

                // Rectangle en cours de drawing
                if case let .drawing(start, current) = interaction {
                    let x = min(start.x, current.x)
                    let y = min(start.y, current.y)
                    let w = abs(current.x - start.x)
                    let h = abs(current.y - start.y)
                    Rectangle()
                        .strokeBorder(Theme.Colors.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .background(Theme.Colors.accent.opacity(0.15))
                        .frame(width: w, height: h)
                        .offset(x: x, y: y)
                        .allowsHitTesting(false)
                }

                // Hint label flottant en bas
                VStack {
                    Spacer()
                    hintLabel
                        .padding(.bottom, Theme.Spacing.lg)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .coordinateSpace(name: "canvas")
            .gesture(canvasGesture(displayedRect: displayedRect))
        }
    }

    // MARK: - Hint label

    private var hintLabel: some View {
        let hasRegion = profile.regions[currentKind] != nil
        let text: String
        switch interaction {
        case .drawing:
            text = "Relâche pour valider"
        case .moving:
            text = "Déplacement…"
        case .resizing:
            text = "Redimensionnement…"
        case .idle:
            if hasRegion {
                text = "« \(currentKind.displayName) » — drag pour déplacer, coins pour redimensionner. Re-trace ailleurs pour redéfinir."
            } else {
                text = "Trace la zone « \(currentKind.displayName) » sur la capture"
            }
        }
        return Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.surface.opacity(0.92))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.Colors.border, lineWidth: 1))
    }

    // MARK: - Region overlay (rect + label + corner handles si current)

    private func regionOverlay(region: Region, displayedRect: CGRect) -> some View {
        let r = denormalize(rect: region.bounds, displayedRect: displayedRect)
        let isCurrent = region.kind == currentKind
        let color = isCurrent ? Theme.Colors.accent : Theme.Colors.success

        return ZStack(alignment: .topLeading) {
            // Rectangle de la région
            Rectangle()
                .strokeBorder(color, lineWidth: 2)
                .background(color.opacity(0.12))
                .frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY)
                .allowsHitTesting(false)

            // Label flottant au-dessus
            Text(region.kind.shortName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .fixedSize()
                .offset(x: r.minX + 2, y: max(displayedRect.minY, r.minY - 18))
                .allowsHitTesting(false)

            // Handles de coin uniquement pour la région courante (active)
            if isCurrent {
                cornerHandle(rect: r, corner: .topLeft)
                cornerHandle(rect: r, corner: .topRight)
                cornerHandle(rect: r, corner: .bottomLeft)
                cornerHandle(rect: r, corner: .bottomRight)
            }
        }
    }

    private func cornerHandle(rect: CGRect, corner: Corner) -> some View {
        let size: CGFloat = 12
        let half = size / 2
        let point: CGPoint
        switch corner {
        case .topLeft:     point = CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:    point = CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:  point = CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: point = CGPoint(x: rect.maxX, y: rect.maxY)
        }
        return RoundedRectangle(cornerRadius: 2)
            .fill(Theme.Colors.accent)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(.white, lineWidth: 1.5))
            .frame(width: size, height: size)
            .offset(x: point.x - half, y: point.y - half)
    }

    // MARK: - Gesture handling

    private func canvasGesture(displayedRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas"))
            .onChanged { value in
                let start = clamp(value.startLocation, to: displayedRect)
                let current = clamp(value.location, to: displayedRect)

                switch interaction {
                case .idle:
                    interaction = decideInitialInteraction(startCanvas: start, currentCanvas: current, displayedRect: displayedRect)
                case .drawing(let s, _):
                    interaction = .drawing(startCanvas: s, currentCanvas: current)
                case .moving(let id, let original, let s):
                    interaction = .moving(regionId: id, originalBounds: original, startCanvas: s)
                    applyMove(regionId: id, original: original, startCanvas: s, currentCanvas: current, displayedRect: displayedRect)
                case .resizing(let id, let original, let corner, let s):
                    interaction = .resizing(regionId: id, originalBounds: original, corner: corner, startCanvas: s)
                    applyResize(regionId: id, original: original, corner: corner, currentCanvas: current, displayedRect: displayedRect)
                }
            }
            .onEnded { _ in
                defer { interaction = .idle }
                if case let .drawing(start, current) = interaction {
                    let x = min(start.x, current.x) - displayedRect.minX
                    let y = min(start.y, current.y) - displayedRect.minY
                    let w = abs(current.x - start.x)
                    let h = abs(current.y - start.y)
                    guard w > 6, h > 6 else { return }
                    let normalized = NormalizedRect(
                        x: x / displayedRect.width,
                        y: y / displayedRect.height,
                        width: w / displayedRect.width,
                        height: h / displayedRect.height
                    )
                    let region = Region(kind: currentKind, bounds: normalized)
                    profile.setRegion(region)
                    onRegionDefined(currentKind)
                }
            }
    }

    private func decideInitialInteraction(
        startCanvas: CGPoint,
        currentCanvas: CGPoint,
        displayedRect: CGRect
    ) -> Interaction {
        // Si la région courante existe, on regarde si le start est sur un handle ou dans le corps
        if let existing = profile.regions[currentKind] {
            let r = denormalize(rect: existing.bounds, displayedRect: displayedRect)
            let handleHit: CGFloat = 14
            // Test corners
            for corner in [Corner.topLeft, .topRight, .bottomLeft, .bottomRight] {
                let p: CGPoint
                switch corner {
                case .topLeft:     p = CGPoint(x: r.minX, y: r.minY)
                case .topRight:    p = CGPoint(x: r.maxX, y: r.minY)
                case .bottomLeft:  p = CGPoint(x: r.minX, y: r.maxY)
                case .bottomRight: p = CGPoint(x: r.maxX, y: r.maxY)
                }
                if abs(startCanvas.x - p.x) <= handleHit && abs(startCanvas.y - p.y) <= handleHit {
                    return .resizing(regionId: existing.id, originalBounds: existing.bounds, corner: corner, startCanvas: startCanvas)
                }
            }
            // Test inside rect (move)
            if r.contains(startCanvas) {
                return .moving(regionId: existing.id, originalBounds: existing.bounds, startCanvas: startCanvas)
            }
        }
        // Sinon, drawing
        return .drawing(startCanvas: startCanvas, currentCanvas: currentCanvas)
    }

    private func applyMove(
        regionId: UUID,
        original: NormalizedRect,
        startCanvas: CGPoint,
        currentCanvas: CGPoint,
        displayedRect: CGRect
    ) {
        let dx = (currentCanvas.x - startCanvas.x) / displayedRect.width
        let dy = (currentCanvas.y - startCanvas.y) / displayedRect.height
        var newX = original.x + dx
        var newY = original.y + dy
        newX = max(0, min(1 - original.width, newX))
        newY = max(0, min(1 - original.height, newY))
        let newBounds = NormalizedRect(x: newX, y: newY, width: original.width, height: original.height)
        profile.setRegion(Region(id: regionId, kind: currentKind, bounds: newBounds))
    }

    private func applyResize(
        regionId: UUID,
        original: NormalizedRect,
        corner: Corner,
        currentCanvas: CGPoint,
        displayedRect: CGRect
    ) {
        let absRect = original.absolute(in: displayedRect.size)
        let originLocal = CGPoint(
            x: absRect.minX + displayedRect.minX,
            y: absRect.minY + displayedRect.minY
        )
        let cornerLocal: CGPoint
        switch corner {
        case .topLeft:     cornerLocal = originLocal
        case .topRight:    cornerLocal = CGPoint(x: originLocal.x + absRect.width, y: originLocal.y)
        case .bottomLeft:  cornerLocal = CGPoint(x: originLocal.x, y: originLocal.y + absRect.height)
        case .bottomRight: cornerLocal = CGPoint(x: originLocal.x + absRect.width, y: originLocal.y + absRect.height)
        }
        _ = cornerLocal  // référence pour clarté, on calcule à partir du current

        // Le coin opposé reste fixe
        let opposite: CGPoint
        switch corner {
        case .topLeft:     opposite = CGPoint(x: originLocal.x + absRect.width, y: originLocal.y + absRect.height)
        case .topRight:    opposite = CGPoint(x: originLocal.x, y: originLocal.y + absRect.height)
        case .bottomLeft:  opposite = CGPoint(x: originLocal.x + absRect.width, y: originLocal.y)
        case .bottomRight: opposite = originLocal
        }

        let newRect = CGRect(
            x: min(currentCanvas.x, opposite.x),
            y: min(currentCanvas.y, opposite.y),
            width: abs(currentCanvas.x - opposite.x),
            height: abs(currentCanvas.y - opposite.y)
        )
        guard newRect.width >= 8, newRect.height >= 8 else { return }

        // Convertir en normalized par rapport à l'image
        let newBounds = NormalizedRect(
            x: (newRect.minX - displayedRect.minX) / displayedRect.width,
            y: (newRect.minY - displayedRect.minY) / displayedRect.height,
            width: newRect.width / displayedRect.width,
            height: newRect.height / displayedRect.height
        )
        profile.setRegion(Region(id: regionId, kind: currentKind, bounds: newBounds))
    }

    // MARK: - Coordinate helpers

    private var imageSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }

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

    private func denormalize(rect: NormalizedRect, displayedRect: CGRect) -> CGRect {
        CGRect(
            x: displayedRect.minX + rect.x * displayedRect.width,
            y: displayedRect.minY + rect.y * displayedRect.height,
            width: rect.width * displayedRect.width,
            height: rect.height * displayedRect.height
        )
    }
}
