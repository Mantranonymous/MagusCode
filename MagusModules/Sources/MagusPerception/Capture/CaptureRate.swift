import CoreMedia
import Foundation

/// Fréquence de capture. Active = pendant une session, idle = en attente.
public enum CaptureRate: Sendable {
    case active   // 30 fps
    case idle     // 5 fps

    public var fps: Int {
        switch self {
        case .active: return 30
        case .idle: return 5
        }
    }

    public var frameInterval: CMTime {
        CMTime(value: 1, timescale: Int32(fps))
    }
}
