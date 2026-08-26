import SwiftUI

/// Pastille affichant le pays de reperage, ouvre le selecteur.
struct MarketChip: View {
    @Environment(AppState.self) private var app
    @State private var showing = false
    private let store = CatalogStore.shared

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 7) {
                Image(systemName: app.isVerifiedCapture ? "location.fill" : "mappin")
                    .font(.system(size: 10, weight: .semibold))
                Text(store.countryName(app.country))
                    .font(Theme.label(11)).tracking(0.6)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Theme.accentBright)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.accent.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(Theme.accent.opacity(0.35), lineWidth: 1))
        }
        .sheet(isPresented: $showing) { MarketPickerSheet() }
    }
}

struct MarketPickerSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private let store = CatalogStore.shared

    private var results: [String] {
        guard !query.isEmpty else { return store.knownCountries }
        return store.knownCountries.filter {
            store.countryName($0).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(results, id: \.self) { code in
                Button {
                    app.country = code
                    dismiss()
                } label: {
                    HStack {
                        Text(store.countryName(code))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if code == app.country {
                            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                        } else {
                            Text(code).font(Theme.mono(11)).foregroundStyle(Theme.textMuted)
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .searchable(text: $query, prompt: Text("market.search"))
            .navigationTitle(Text("market.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}
