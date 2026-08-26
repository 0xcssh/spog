import SwiftUI

/// Parcours du catalogue embarque. Montre que la rarete change avec le pays de reperage.
struct CatalogExplorerView: View {
    @Environment(AppState.self) private var app
    @State private var query = ""
    private let store = CatalogStore.shared

    private var results: [(Vehicle, RarityResolution)] {
        let base = query.isEmpty
            ? store.vehicles
            : store.vehicles.filter { $0.fullName.localizedCaseInsensitiveContains(query) }
        return base
            .map { ($0, store.resolve($0, in: app.country)) }
            .sorted {
                $0.1.tier.rank != $1.1.tier.rank
                    ? $0.1.tier.rank > $1.1.tier.rank
                    : $0.0.fullName < $1.0.fullName
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            list
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Overline(text: "catalog.section")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(store.vehicles.count)")
                        .font(Theme.display(26))
                        .foregroundStyle(Theme.textPrimary)
                    Text("catalog.vehicles")
                        .font(Theme.label(12)).tracking(1.4).textCase(.uppercase)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            MarketChip()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
            TextField(text: $query) { Text("catalog.search") }
                .textFieldStyle(.plain)
                .font(Theme.display(14, .medium))
                .foregroundStyle(Theme.textPrimary)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(results, id: \.0.id) { vehicle, resolution in
                    row(vehicle, resolution)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func row(_ vehicle: Vehicle, _ resolution: RarityResolution) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(resolution.tier.color)
                .frame(width: 3, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.make.uppercased())
                    .font(Theme.label(9)).tracking(1.4)
                    .foregroundStyle(Theme.textMuted)
                Text(vehicle.model)
                    .font(Theme.display(15, .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(resolution.tier.label)
                    .font(Theme.label(9)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(resolution.tier.color)
                Text("\(resolution.tier.points) pts")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(resolution.tier.color.opacity(0.18), lineWidth: 1)
        )
    }
}
