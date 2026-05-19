import AppKit
import CoreGraphics
import MagusCommon
import SwiftUI
import os

/// Fenêtre flottante transparente posée par-dessus la fenêtre Dofus.
/// Borderless, ignore les clics, suit la position du jeu.
@MainActor
public final class OverlayWindow {

    private var window: NSWindow?
    private var hosting: NSHostingController<AnyView>?
    private let logger = MagusLogger.execution

    public init() {}

    /// Affiche l'overlay en l'ancrant dans le coin haut-droit de la fenêtre Dofus
    /// (`dofusBounds` en coordonnées d'écran, top-left origin Quartz).
    public func show<Content: View>(
        dofusBounds: CGRect,
        @ViewBuilder content: () -> Content
    ) {
        ensureWindow()
        hosting?.rootView = AnyView(content())
        reposition(dofusBounds: dofusBounds)
        window?.orderFrontRegardless()
    }

    public func hide() {
        window?.orderOut(nil)
    }

    public func close() {
        window?.close()
        window = nil
        hosting = nil
    }

    // MARK: - Internals

    private func ensureWindow() {
        guard window == nil else { return }
        let initialFrame = NSRect(x: 0, y: 0, width: 360, height: 80)
        let w = NSWindow(
            contentRect: initialFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        // Level très haut pour passer au-dessus d'un Dofus fullscreen
        w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        w.ignoresMouseEvents = true
        w.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

        let hostingController = NSHostingController(rootView: AnyView(EmptyView()))
        w.contentViewController = hostingController

        self.window = w
        self.hosting = hostingController
    }

    /// dofusBounds : top-left origin (Quartz). NSWindow utilise bottom-left.
    private func reposition(dofusBounds: CGRect) {
        guard let window = window else { return }

        // Trouver l'écran qui contient le centre de la fenêtre Dofus
        let centerCG = CGPoint(x: dofusBounds.midX, y: dofusBounds.midY)
        let targetScreen = NSScreen.screens.first { screen in
            // Le repère NSScreen est bottom-left, dofus est top-left → on flippe pour comparer
            let flippedCenterY = (NSScreen.screens.first?.frame.height ?? 0) - centerCG.y
            let nsCenter = NSPoint(x: centerCG.x, y: flippedCenterY)
            return screen.frame.contains(nsCenter)
        } ?? NSScreen.main ?? NSScreen.screens.first

        guard let screen = targetScreen else { return }

        let visible = screen.visibleFrame
        let width: CGFloat = 360
        let height: CGFloat = 80
        let margin: CGFloat = 12

        // dofusBounds est en Quartz (top-left). On convertit en NSScreen (bottom-left).
        let firstScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let dofusNSY = firstScreenHeight - dofusBounds.maxY
        let dofusNSTop = firstScreenHeight - dofusBounds.minY
        _ = dofusNSY

        // Cible : aligné au coin haut-droit de Dofus, vers l'intérieur
        var x = dofusBounds.maxX - width - margin
        var y = dofusNSTop - height - margin

        // Clamp dans la visibleFrame du screen
        x = max(visible.minX + margin, min(visible.maxX - width - margin, x))
        y = max(visible.minY + margin, min(visible.maxY - height - margin, y))

        let newFrame = NSRect(x: x, y: y, width: width, height: height)
        window.setFrame(newFrame, display: true)
    }
}
