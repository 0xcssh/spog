import SwiftUI

/// Le garage : la collection, en grille. Ecran d'accueil de l'app.
struct GarageView: View {
    /// Emmene le joueur vers le scan depuis le garage vide. Le garage ne connait
    /// pas les onglets : c'est la vue racine qui sait ou aller.
    var onScan: (() -> Void)?

    @Environment(AppState.self) private var app
    @Environment(GarageStore.self) private var garage
    @State private var selected: CardData?
    @State private var browsingCatalog = false
    @State private var showingSettings = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                grid
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .fullScreenCover(item: $selected) { card in
            CardDetailView(card: card)
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $browsingCatalog) {
            NavigationStack {
                CatalogExplorerView()
                    .background(Theme.background)
            }
            .preferredColorScheme(.dark)
        }
    }

    private var header: some View {
        SectionHeader(overline: "garage.section",
                      title: "\(garage.cards.count)",
                      trailing: AnyView(
                        HStack(spacing: 9) {
                            // Le catalogue n'a plus d'onglet : on y accede d'ici.
                            circleButton("list.bullet") { browsingCatalog = true }
                            circleButton("gearshape.fill") { showingSettings = true }
                        }
                      ))
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accentBright)
                .frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(Theme.accent.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var grid: some View {
        if garage.cards.isEmpty {
            emptyState
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(garage.cards) { card in
                    Button { selected = card } label: { MiniCard(card: card) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    /// Premier lancement : la grille est vide pour de vrai. Plutot qu'un ecran mort,
    /// on dit ce qui manque et on donne le geste qui le remplit.
    private var emptyState: some View {
        NeonFrame(radius: 20) {
            VStack(spacing: 14) {
                Image(systemName: "car.2.fill")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.accent.opacity(0.7))
                    .padding(.top, 8)

                Text("garage.empty.title")
                    .font(Theme.display(19, .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("garage.empty.body")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)

                if let onScan {
                    Button(action: onScan) {
                        Text("garage.empty.action")
                            .font(Theme.label(12)).tracking(1.2)
                            .foregroundStyle(Theme.background)
                            .padding(.horizontal, 22).padding(.vertical, 14)
                            .background(
                                LinearGradient(colors: [Theme.accentBright, Theme.accent],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 6)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(18)
        }
        .padding(.top, 20)
    }
}

/// Vignette du garage. Reprend le vocabulaire de la vraie carte en plus compact.
struct MiniCard: View {
    let card: CardData

    var body: some View {
        NeonFrame(color: card.tier.frameColor ?? Theme.stroke, radius: 16,
                  intensity: card.tier.frameIntensity, neon: card.tier.isTrophy) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(String(format: "%03d", card.serial))
                        .font(Theme.mono(10, .semibold))
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                    if card.verified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textMuted)
                    }
                }

                ZStack {
                    RadialGradient(colors: [card.tier.color.opacity(0.35), .clear],
                                   center: .center, startRadius: 2, endRadius: 70)
                    if let art = CarArt.image(for: card.vehicle.id, paint: card.paint) {
                        // Rendu du modele : c'est lui qui fait reconnaitre la voiture.
                        Image(uiImage: art)
                            .resizable().scaledToFill()
                    } else {
                        // Repli tant qu'un modele n'a pas son rendu.
                        Image(systemName: "car.side.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(
                                LinearGradient(colors: [Theme.textPrimary.opacity(0.85),
                                                        Theme.textSecondary.opacity(0.3)],
                                               startPoint: .top, endPoint: .bottom)
                            )
                    }
                }
                .frame(height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.vertical, 6)

                Text(card.vehicle.make.uppercased())
                    .font(Theme.label(8)).tracking(1.4)
                    .foregroundStyle(card.tier.color)
                Text(card.vehicle.model)
                    .font(Theme.display(13, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.75)

                HStack {
                    Text(card.tier.label)
                        .font(Theme.label(8)).tracking(1).textCase(.uppercase)
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                    Text("\(card.tier.points)")
                        .font(Theme.mono(10, .bold))
                        .foregroundStyle(card.tier.color)
                }
                .padding(.top, 5)
            }
            .padding(11)
        }
    }
}
