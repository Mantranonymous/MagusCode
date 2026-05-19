import AppKit
import CoreGraphics
import SwiftUI

/// Petite fenêtre flottante qui dessine un réticule animé à la position du
/// prochain click auto. Aide visuelle critique pour le mode Démo.
@MainActor
public final class ClickMarkerWindow {

    private var window: NSWindow?
    private var hosting: NSHostingController<AnyView>?

    public init() {}

    /// Place le marker au point donné (coords écran Quartz top-left).
    public func show(at point: CGPoint) {
        ensureWindow()
        guard let window = window else { return }
        let size: CGFloat = 60

        // Conversion Quartz top-left → NSWindow bottom-left
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let nsY = screenHeight - point.y - size / 2
        let nsX = point.x - size / 2
        window.setFrame(NSRect(x: nsX, y: nsY, width: size, height: size), display: true)
        window.orderFrontRegardless()
    }

    public func hide() {
        window?.orderOut(nil)
    }

    public func close() {
        window?.close()
        window = nil
        hosting = nil
    }

    private func ensureWindow() {
        guard window == nil else { return }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 60, height: 60),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        w.ignoresMouseEvents = true
        w.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary,
            .stationary, .ignoresCycle
        ]
        let hosting = NSHostingController(rootView: AnyView(ClickMarkerView()))
        w.contentViewController = hosting
        self.window = w
        self.hosting = hosting
    }
}

private struct ClickMarkerView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Réticule extérieur pulsant
            Circle()
                .stroke(Color.red.opacity(0.9), lineWidth: 2.5)
                .frame(width: 50, height: 50)
                .scaleEffect(pulse ? 1.0 : 0.7)
                .opacity(pulse ? 0.4 : 1.0)

            // Cercle plein central
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)

            // Lignes en croix
            Path { p in
                p.move(to: CGPoint(x: 30, y: 5))
                p.addLine(to: CGPoint(x: 30, y: 18))
                p.move(to: CGPoint(x: 30, y: 42))
                p.addLine(to: CGPoint(x: 30, y: 55))
                p.move(to: CGPoint(x: 5, y: 30))
                p.addLine(to: CGPoint(x: 18, y: 30))
                p.move(to: CGPoint(x: 42, y: 30))
                p.addLine(to: CGPoint(x: 55, y: 30))
            }
            .stroke(Color.red.opacity(0.85), lineWidth: 1.5)
        }
        .frame(width: 60, height: 60)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever()) {
                pulse.toggle()
            }
        }
    }
}
