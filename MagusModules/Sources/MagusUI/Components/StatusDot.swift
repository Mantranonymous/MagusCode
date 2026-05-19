import SwiftUI

public struct StatusDot: View {
    public enum State: Sendable {
        case done, current, pending, error
    }

    private let state: State
    private let size: CGFloat

    public init(state: State, size: CGFloat = 8) {
        self.state = state
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: state == .current ? 3 : 0)
                    .scaleEffect(state == .current ? 1.8 : 1.0)
            )
            .animation(.easeInOut(duration: 0.3), value: state)
    }

    private var color: Color {
        switch state {
        case .done: return Theme.Colors.success
        case .current: return Theme.Colors.accent
        case .pending: return Theme.Colors.textTertiary
        case .error: return Theme.Colors.danger
        }
    }
}
