import SwiftUI

struct ContentView: View {
    var body: some View {
        HStack(spacing: 0) {
            sidebarPanel
            Divider()
            workspacePanel
            Divider()
            inspectorPanel
        }
        .frame(minWidth: 1100, minHeight: 700)
        .background(Color(red: 0.039, green: 0.043, blue: 0.055))
        .preferredColorScheme(.dark)
    }

    private var sidebarPanel: some View {
        VStack {
            Spacer()
            Text(String(localized: "Sidebar"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.051, green: 0.055, blue: 0.071))
    }

    private var workspacePanel: some View {
        VStack {
            Spacer()
            Text(String(localized: "Magus"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white.opacity(0.3))
            Text(String(localized: "Assistant Forgemagie"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.15))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspectorPanel: some View {
        VStack {
            Spacer()
            Text(String(localized: "Inspecteur"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.051, green: 0.055, blue: 0.071))
    }
}

#Preview {
    ContentView()
}
