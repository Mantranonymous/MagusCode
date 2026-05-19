import CoreGraphics
import Foundation

/// Une frame capturée depuis la fenêtre cible, prête pour OCR ou affichage.
public struct CaptureFrame: Sendable {
    public let image: CGImage
    public let windowBounds: CGRect
    public let timestamp: Date

    public init(image: CGImage, windowBounds: CGRect, timestamp: Date = Date()) {
        self.image = image
        self.windowBounds = windowBounds
        self.timestamp = timestamp
    }

    public var size: CGSize {
        CGSize(width: image.width, height: image.height)
    }
}
