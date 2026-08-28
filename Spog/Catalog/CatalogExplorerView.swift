import SwiftUI

/// Le Spogdex : le catalogue embarque, et surtout **ce qu'il reste a attraper**.
/// Montre aussi que la rarete change avec le pays de reperage.
///
/// C'est le moteur de completion de l'app : sans lui, rien ne donne envie de
/// photographier une Clio. Encore fallait-il pouvoir voir ce qui manque.
struct CatalogExplorerView: View {
    @Environment(AppState.self) private var app
    @Environment(GarageStore.self) private var garage
    @State private var query = ""
    @State private var filter: Filter = .all
    private let store = CatalogStore.shared

    enum Filter: CaseIterable {
        case all, caught, missing

        var key: LocalizedStringKey {
            switch self {
            case .all:     "dex.filter.all"
            case .caught:  "dex.filter.caught"
            case .missing: "dex.filter.missing"
            }
        }
    }

    private var results: [(Vehicle, RarityResolution)] {
        // La recherche passe par le catalogue : elle connait les alias de marche,
        // donc « Cerato » trouve la K3 et « Solaris » trouve l'Accent.
        let base = query.isEmpty ? store.vehicles : store.search(query)
        return base
            .filter { vehicle in
                switch filter {
                case .all:     true
                case .caught:  garage.hasModel(vehicle.id)
                case .missing: !garage.hasModel(vehicle.id)
                }
            }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Overline(text: "catalog.section")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        // Pas de dénominateur : la taille du catalogue n'est pas un
                        // plafond. L'IA nomme des modèles qu'il ne contient pas, et ils
                        // s'y ajoutent — annoncer un total ferait croire à une fin.
                        Text("\(garage.dexCaught)")
                            .font(Theme.display(26))
                            .foregroundStyle(Theme.textPrimary)
                        Text("dex.caught")
                            .font(Theme.label(12)).tracking(1.4).textCase(.uppercase)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                MarketChip()
            }

            filterBar
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var filterBar: some View {
        HStack(spacing: 7) {
            ForEach(Filter.allCases, id: \.self) { item in
                let selected = filter == item
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        filter = item
                    }
                } label: {
                    Text(item.key)
                        .font(Theme.label(10)).tracking(0.8)
                        .foregroundStyle(selected ? Theme.background : Theme.textSecondary)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background {
                            if selected {
                                Capsule().fill(LinearGradient(
                                    colors: [Theme.accentBright, Theme.accent],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                            } else {
                                Capsule().fill(Theme.surface)
                                    .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
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
                if results.isEmpty {
                    Text(filter == .caught && query.isEmpty
                         ? "dex.emptyCaught" : "confirm.noResult")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 30).padding(.horizontal, 20)
                }
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
        let caught = garage.hasModel(vehicle.id)
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(resolution.tier.color)
                .frame(width: 3, height: 30)
                .opacity(caught ? 1 : 0.35)

            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.make.uppercased())
                    .font(Theme.label(9)).tracking(1.4)
                    .foregroundStyle(Theme.textMuted)
                HStack(spacing: 6) {
                    Text(vehicle.model)
                        .font(Theme.display(15, .semibold))
                        .foregroundStyle(caught ? Theme.textPrimary : Theme.textSecondary)
                    // La coche marque ce qui est acquis. Le reste n'est pas caché :
                    // c'est précisément ce qui donne envie de sortir.
                    if caught {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.accent)
                    }
                    // Appris d'un scan, pas livré avec l'app : le joueur a agrandi
                    // son propre catalogue, autant que ça se voie.
                    if store.isLearned(vehicle.id) {
                        Text("dex.learned")
                            .font(Theme.label(8)).tracking(0.8).textCase(.uppercase)
                            .foregroundStyle(Theme.accentBright)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.18), in: Capsule())
                    }
                }
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
        .background(caught ? resolution.tier.color.opacity(0.07) : Theme.surface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(resolution.tier.color.opacity(caught ? 0.35 : 0.14), lineWidth: 1)
        )
    }
}
