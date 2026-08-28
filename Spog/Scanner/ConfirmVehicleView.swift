import SwiftUI

/// Ecran de confirmation, quand l'IA n'est pas assez sure d'elle.
/// Regle posee dans le plan : au-dessus du seuil la carte se cree seule,
/// en dessous c'est le joueur qui tranche. Une mauvaise carte est pire
/// qu'une question de plus.
struct ConfirmVehicleView: View {
    let photo: UIImage?
    /// Ce que l'IA a cru lire. Montre tel quel : le joueur juge sur piece.
    let reading: String
    let candidates: [Vehicle]
    let onPick: (Vehicle) -> Void
    /// Ajoute au catalogue ce que l'IA a lu. Propose seulement quand elle a lu
    /// quelque chose d'exploitable.
    let onLearn: () -> Void
    let onCancel: () -> Void

    @Environment(AppState.self) private var app
    @State private var query = ""
    private let catalog = CatalogStore.shared

    private var results: [Vehicle] {
        query.isEmpty ? candidates : Array(catalog.search(query).prefix(40))
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            DotGrid(spacing: 22).ignoresSafeArea().opacity(0.5)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if !reading.isEmpty {
                    readingBanner
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                }

                if !reading.isEmpty {
                    learnButton
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                searchField
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                list

                Button(action: onCancel) {
                    Text("confirm.none")
                        .font(Theme.label(11)).tracking(1.2).textCase(.uppercase)
                        .foregroundStyle(Theme.textMuted)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Overline(text: "confirm.section")
                Text("confirm.title")
                    .font(Theme.display(24))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            if let photo {
                Image(uiImage: photo)
                    .resizable().scaledToFill()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1))
            }
        }
    }

    /// Ce que l'IA a lu, en clair. Sans ca le joueur ne comprend pas pourquoi on lui demande.
    private var readingBanner: some View {
        HStack(spacing: 9) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("confirm.reading \(reading)")
                .font(Theme.display(13))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Theme.accent.opacity(0.25), lineWidth: 1))
    }

    /// Aucune des propositions ne convient parce que la voiture n'est pas au catalogue :
    /// c'est frequent hors d'Europe. Plutot qu'une impasse, on l'y ajoute.
    private var learnButton: some View {
        Button(action: onLearn) {
            HStack(spacing: 9) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.background)
                VStack(alignment: .leading, spacing: 2) {
                    Text("confirm.learn \(reading)")
                        .font(Theme.display(14, .semibold))
                        .foregroundStyle(Theme.background)
                        .multilineTextAlignment(.leading)
                    Text("confirm.learn.why")
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.background.opacity(0.75))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [Theme.accentBright, Theme.accent],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View { SearchField(query: $query) }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if results.isEmpty {
                    Text("confirm.noResult")
                        .font(Theme.display(13))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.top, 30)
                }
                ForEach(results) { vehicle in
                    Button { onPick(vehicle) } label: { row(vehicle) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    /// La ligne et le champ de recherche sont ceux du selecteur de vehicule :
    /// deux ecrans qui posent la meme question doivent la poser pareil.
    private func row(_ vehicle: Vehicle) -> some View {
        VehicleRow(vehicle: vehicle, resolution: catalog.resolve(vehicle, in: app.country))
    }

}
