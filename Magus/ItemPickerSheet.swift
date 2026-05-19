import MagusCore
import MagusPersistence
import MagusReferenceData
import MagusUI
import SwiftUI

struct ItemPickerSheet: View {
    let appState: AppState
    @Binding var isPresented: Bool

    @State private var query: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.Colors.border)
            searchField
            Divider().background(Theme.Colors.border)
            resultsList
        }
        .frame(width: 520, height: 560)
        .background(Theme.Colors.bg)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Choisir un item")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Recherche dans la base DofusDB (anneau, ceinture, amulette, bottes...)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            MagusButton("Fermer", style: .ghost) { isPresented = false }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface)
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Colors.textTertiary)
            TextField("Tape le nom de l'item (ex: Gelano, Strigide...)", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textPrimary)
                .onChange(of: query) { _, newValue in
                    appState.searchItems(query: newValue)
                }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if appState.itemSearchResults.isEmpty {
                    Text(query.count < 2 ? "Tape au moins 2 lettres..." : "Aucun item trouvé")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .padding(Theme.Spacing.lg)
                } else {
                    ForEach(appState.itemSearchResults) { item in
                        resultRow(item: item)
                        Divider().background(Theme.Colors.border)
                    }
                }
            }
        }
        .background(Theme.Colors.bg)
    }

    private func resultRow(item: RefItem) -> some View {
        Button {
            appState.selectItem(id: item.id)
            isPresented = false
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.nameFR ?? "?")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Niveau \(item.level ?? 0) · id \(item.id)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
