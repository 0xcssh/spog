import SwiftUI

/// Choix d'un vehicule dans le catalogue, par recherche libre.
///
/// Deux ecrans en ont besoin et posent la meme question : l'ecran de confirmation quand
/// l'IA doute, et la fiche de carte quand le joueur veut corriger une identification.
/// Une seule ligne dessinee, un seul comportement de recherche.
struct VehiclePickerSheet: View {
    let title: LocalizedStringKey
    /// Propositions montrees quand la recherche est vide. Rien : tout le catalogue.
    var suggestions: [Vehicle] = []
    let onPick: (Vehicle) -> Void

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private let catalog = CatalogStore.shared

    private var results: [Vehicle] {
        if !query.isEmpty { return Array(catalog.search(query).prefix(60)) }
        return suggestions.isEmpty ? Array(catalog.vehicles.prefix(60)) : suggestions
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchField(query: $query)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        if results.isEmpty {
                            Text("confirm.noResult")
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.textMuted)
                                .padding(.top, 30)
                        }
                        ForEach(results) { vehicle in
                            Button {
                                onPick(vehicle)
                                dismiss()
                            } label: {
                                VehicleRow(vehicle: vehicle,
                                           resolution: catalog.resolve(vehicle, in: app.country))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .background(Theme.background)
            .navigationTitle(Text(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Text("common.close") }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Une ligne de catalogue : marque, modele, palier dans le pays de reperage.
struct VehicleRow: View {
    let vehicle: Vehicle
    let resolution: RarityResolution

    var body: some View {
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
            Text(resolution.tier.label)
                .font(Theme.label(9)).tracking(1.2).textCase(.uppercase)
                .foregroundStyle(resolution.tier.color)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(resolution.tier.color.opacity(0.18), lineWidth: 1))
    }
}

/// Champ de recherche du catalogue. La recherche passe par `CatalogStore`, qui connait
/// les alias de marche : « Cerato » trouve la K3, « Rogue » le X-Trail.
struct SearchField: View {
    @Binding var query: String

    var body: some View {
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
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }
}
