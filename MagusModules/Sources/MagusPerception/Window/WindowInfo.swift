import CoreGraphics
import Foundation

/// Informations sur une fenêtre découverte (typiquement Dofus).
public struct WindowInfo: Equatable, Hashable, Sendable {
    public let windowID: CGWindowID
    public let processID: pid_t
    public let bundleIdentifier: String?
    public let title: String?
    public let bounds: CGRect

    public init(
        windowID: CGWindowID,
        processID: pid_t,
        bundleIdentifier: String?,
        title: String?,
        bounds: CGRect
    ) {
        self.windowID = windowID
        self.processID = processID
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.bounds = bounds
    }

    public var size: CGSize { bounds.size }
}
