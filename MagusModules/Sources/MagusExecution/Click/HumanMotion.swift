import CoreGraphics
import Foundation

/// Génère une trajectoire de souris "humaine" entre deux points via une courbe
/// de Bézier cubique avec points de contrôle randomisés + easing non-uniforme.
public enum HumanMotion {

    /// Retourne une liste de points intermédiaires à parcourir, avec leur délai.
    public static func path(
        from: CGPoint,
        to: CGPoint,
        steps: Int? = nil,
        jitter: CGFloat = 2.0
    ) -> [(point: CGPoint, delayNs: UInt64)] {
        let distance = hypot(to.x - from.x, to.y - from.y)
        guard distance > 1 else {
            return [(point: to, delayNs: 0)]
        }

        let nSteps = steps ?? max(8, min(30, Int(distance / 25)))

        // Points de contrôle : perpendiculaires à la ligne directe avec un offset randomisé
        let dx = to.x - from.x
        let dy = to.y - from.y
        let perpX = -dy
        let perpY = dx
        let perpNorm = sqrt(perpX * perpX + perpY * perpY)
        let perpUnitX = perpNorm > 0 ? perpX / perpNorm : 0
        let perpUnitY = perpNorm > 0 ? perpY / perpNorm : 0

        // Amplitude de la courbe : proportionnelle à la distance, randomisée
        let curveAmplitude = distance * CGFloat.random(in: 0.05...0.20)
        let curveSign: CGFloat = Bool.random() ? 1 : -1

        let ctrl1 = CGPoint(
            x: from.x + dx * 0.33 + perpUnitX * curveAmplitude * curveSign,
            y: from.y + dy * 0.33 + perpUnitY * curveAmplitude * curveSign
        )
        let ctrl2 = CGPoint(
            x: from.x + dx * 0.66 + perpUnitX * curveAmplitude * curveSign * 0.5,
            y: from.y + dy * 0.66 + perpUnitY * curveAmplitude * curveSign * 0.5
        )

        var points: [(CGPoint, UInt64)] = []
        for i in 1...nSteps {
            let t = Double(i) / Double(nSteps)
            // Ease in-out (cubic) pour démarrage/arrivée lents
            let eased = easeInOutCubic(t)
            let p = bezier(t: eased, p0: from, p1: ctrl1, p2: ctrl2, p3: to)

            // Jitter (sauf sur le dernier point pour viser pile)
            let jitteredX = i == nSteps ? p.x : p.x + CGFloat.random(in: -jitter...jitter)
            let jitteredY = i == nSteps ? p.y : p.y + CGFloat.random(in: -jitter...jitter)

            // Délai entre points : log-normal légère (10-25ms typique)
            let baseMs = Double.random(in: 8...20)
            let delayNs = UInt64(baseMs * 1_000_000)
            points.append((CGPoint(x: jitteredX, y: jitteredY), delayNs))
        }
        return points
    }

    private static func easeInOutCubic(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    private static func bezier(t: Double, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) -> CGPoint {
        let ti = 1 - t
        let ti2 = ti * ti
        let ti3 = ti2 * ti
        let t2 = t * t
        let t3 = t2 * t

        let x = ti3 * p0.x + 3 * ti2 * t * p1.x + 3 * ti * t2 * p2.x + t3 * p3.x
        let y = ti3 * p0.y + 3 * ti2 * t * p1.y + 3 * ti * t2 * p2.y + t3 * p3.y
        return CGPoint(x: x, y: y)
    }
}
