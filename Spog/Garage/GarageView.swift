import SwiftUI

/// Le garage : la collection, en grille. Ecran d'accueil de l'app.
struct GarageView: View {
    /// Emmene le joueur vers le scan depuis le garage vide. Le garage ne connait
    /// pas les onglets : c'est la vue racine qui sait ou aller.
    var onScan: (() -> Void)?

    @Environment(AppState.self) private var app
    @Environment(GarageStore.self) private var garage
    @Environment(BountyStore.self) private var bounty
    @State private var selected: CardData?
    @State private var browsingCatalog = false
    @State private var showingSettings = false
    /// Modèles à faire désirer tant que la collection est maigre (voir `discoverStrip`).
    @State private var teasers: [Teaser] = []

    /// L'écart doit être plus large que le débordement du néon doré, sinon le halo d'une
    /// carte mord sur sa voisine et les deux paraissent encadrées ensemble.
    private let columns = [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)]

    /// En dessous de ce nombre de cartes, la grille ne remplit pas l'écran : on montre
    /// sous elle ce qu'il reste de beau à trouver, plutôt qu'un grand vide noir.
    private static let teaserThreshold = 6

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                statsPanel
                BountyPanel()
                collection
                if garage.cards.count < Self.teaserThreshold && !teasers.isEmpty {
                    discoverStrip
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        // La chasse bouge à chaque prise (une cible trouvée, un premier chasseur désigné).
        .task(id: "\(garage.catches.count)-\(app.country)") { await bounty.refresh(country: app.country) }
        .task(id: app.country) { teasers = Self.rankedTeasers(country: app.country) }
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

    // MARK: En-tête

    /// Le compteur est le héros de l'écran : un « 0 » perdu en 24 points faisait un
    /// en-tête maigre. En grand, avec le reste du Spogdex à côté, il dit où on en est.
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Overline(text: "garage.section", color: Theme.accentBright)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(garage.cards.count.formatted())
                        .font(Theme.hero(64))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient(colors: [Theme.textPrimary, Theme.accentBright],
                                                        startPoint: .top, endPoint: .bottom))
                        .contentTransition(.numericText(value: Double(garage.cards.count)))
                        .shadow(color: Theme.accent.opacity(0.45), radius: 18)
                    Text("garage.cards.unit")
                        .font(Theme.display(15, .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            HStack(spacing: 9) {
                // Le catalogue n'a plus d'onglet : on y accede d'ici.
                circleButton("list.bullet") { browsingCatalog = true }
                circleButton("gearshape.fill") { showingSettings = true }
            }
            .padding(.top, 6)
        }
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accentBright)
                .frame(width: 40, height: 40)
                .background(Theme.glassFill, in: Circle())
                .overlay(Circle().strokeBorder(Theme.glassEdge, lineWidth: 1))
                .shadow(color: Theme.dropShadow, radius: 8, y: 4)
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
    }

    /// Points, modèles, prises du jour, et la progression du Spogdex : de quoi savoir où
    /// on en est sans quitter l'écran d'accueil.
    private var statsPanel: some View {
        GlassCard(radius: 20, padding: 14) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    MetricCell(value: garage.totalPoints, label: "garage.stat.points", color: Theme.accentBright)
                    HairlineDivider()
                    MetricCell(value: garage.uniqueModels, label: "garage.stat.models")
                    HairlineDivider()
                    MetricCell(value: garage.todayCount, label: "garage.stat.today")
                }
                Button { browsingCatalog = true } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Image(systemName: "square.grid.3x3.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.accent)
                            Text("garage.dex \(garage.dexCaught) \(garage.dexTotal)")
                                .font(Theme.mono(10, .semibold))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.textMuted)
                        }
                        dexBar
                    }
                }
                .buttonStyle(PressScaleStyle(scale: 0.98))
            }
        }
    }

    private var dexBar: some View {
        let ratio = garage.dexTotal > 0 ? Double(garage.dexCaught) / Double(garage.dexTotal) : 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.textMuted.opacity(0.18))
                Capsule()
                    .fill(Theme.accentGradient)
                    // Un minimum visible : 1 modèle sur 867 doit déjà se voir.
                    .frame(width: max(ratio > 0 ? 8 : 0, geo.size.width * ratio))
                    .shadow(color: Theme.accent.opacity(0.7), radius: 5)
            }
        }
        .frame(height: 5)
    }

    // MARK: Collection

    @ViewBuilder private var collection: some View {
        if garage.cards.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Overline(text: "garage.collection")
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(garage.cards) { card in
                        Button { selected = card } label: { MiniCard(card: card) }
                            .buttonStyle(PressScaleStyle())
                    }
                }
            }
        }
    }

    /// Premier lancement : la grille est vide pour de vrai. Plutot qu'un ecran mort, on
    /// montre l'emplacement de la première carte, les trois gestes qui la remplissent, et
    /// le bouton qui y mène.
    private var emptyState: some View {
        GlassCard(radius: 24, tint: Theme.accent, padding: 20) {
            VStack(spacing: 18) {
                GhostCardSlot()
                    .frame(width: 128, height: 172)
                    .padding(.top, 4)

                VStack(spacing: 8) {
                    Text("garage.empty.title")
                        .font(Theme.display(24))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("garage.empty.body")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 0) {
                    step("viewfinder", "garage.step.spot")
                    stepConnector
                    step("sparkles", "garage.step.identify")
                    stepConnector
                    step("rectangle.stack.fill", "garage.step.collect")
                }

                if let onScan {
                    Button(action: onScan) {
                        HStack(spacing: 8) {
                            Image(systemName: "viewfinder").font(.system(size: 13, weight: .bold))
                            Text("garage.empty.action")
                        }
                    }
                    .buttonStyle(NeonButtonStyle())
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func step(_ icon: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accentBright)
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.12), in: Circle())
                .overlay(Circle().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
            Text(label)
                .font(Theme.label(9)).tracking(1).textCase(.uppercase)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var stepConnector: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Theme.accent.opacity(0.1), Theme.accent.opacity(0.5), Theme.accent.opacity(0.1)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: 22, height: 1)
            .padding(.bottom, 22)
    }

    // MARK: À découvrir

    /// Les plus belles prises possibles dans le pays du joueur, tirées du Spogdex. Elles
    /// donnent une raison concrète de sortir, là où la grille n'a pas encore de quoi
    /// remplir l'écran.
    private var discoverStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Overline(text: "garage.discover")
                Spacer()
                Button { browsingCatalog = true } label: {
                    Text("garage.discover.all")
                        .font(Theme.label(10)).tracking(1).textCase(.uppercase)
                        .foregroundStyle(Theme.accentBright)
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(teasers) { item in
                        Button { browsingCatalog = true } label: {
                            TeaserCard(vehicle: item.vehicle, tier: item.tier)
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            // Les cartes débordent jusqu'au bord de l'écran : la rangée se lit comme
            // une rangée qui continue, pas comme une boîte fermée.
            .padding(.horizontal, -20)
            .contentMargins(.horizontal, 20, for: .scrollContent)
        }
    }

    /// Les modèles qui ont un rendu embarqué, du plus rare au plus courant dans ce pays.
    /// Seuls les rendus embarqués : aucun appel réseau pour un simple aperçu.
    private static func rankedTeasers(country: String) -> [Teaser] {
        let catalog = CatalogStore.shared
        let ranked = catalog.vehicles
            .map { Teaser(vehicle: $0, tier: catalog.resolve($0, in: country).tier) }
            .sorted { $0.tier.rank > $1.tier.rank }
        var picked: [Teaser] = []
        for item in ranked where CarArt.image(for: item.vehicle.id) != nil {
            picked.append(item)
            if picked.count == 8 { break }
        }
        return picked
    }
}

/// Un modèle à faire désirer, avec sa rareté dans le pays du joueur.
private struct Teaser: Identifiable {
    let vehicle: Vehicle
    let tier: RarityTier
    var id: String { vehicle.id }
}

/// Emplacement de la première carte : un cadre en pointillés lumineux, une silhouette, et
/// un reflet qui passe. Il montre la forme exacte de ce que le joueur va obtenir.
private struct GhostCardSlot: View {
    @State private var float = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        shape
            .fill(LinearGradient(colors: [Theme.accent.opacity(0.18), Theme.surface],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(DotGrid(spacing: 9).clipShape(shape))
            .overlay {
                VStack(spacing: 10) {
                    Text(verbatim: "#001")
                        .font(Theme.mono(10, .bold))
                        .foregroundStyle(Theme.textMuted)
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(LinearGradient(colors: [Theme.textPrimary.opacity(0.55), Theme.accent.opacity(0.4)],
                                                        startPoint: .top, endPoint: .bottom))
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accentBright)
                        .frame(width: 28, height: 28)
                        .background(Theme.accent.opacity(0.18), in: Circle())
                }
            }
            .shimmer(duration: 3.2)
            .overlay(shape.strokeBorder(Theme.accentBright.opacity(0.7),
                                        style: StrokeStyle(lineWidth: 1.4, dash: [6, 5])))
            .shadow(color: Theme.accent.opacity(0.45), radius: 16)
            .rotationEffect(.degrees(float ? -3 : 3))
            .offset(y: float ? -4 : 4)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { float = true }
            }
    }
}

/// Aperçu d'un modèle du Spogdex pas encore attrapé : son rendu studio, sa rareté locale.
private struct TeaserCard: View {
    let vehicle: Vehicle
    let tier: RarityTier

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle()
                .fill(RadialGradient(colors: [tier.color.opacity(0.35), Theme.surface],
                                     center: .bottom, startRadius: 2, endRadius: 110))
                .overlay {
                    if let art = CarArt.image(for: vehicle.id) {
                        StudioArt(image: art)
                    }
                }
                .frame(height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .padding(.bottom, 4)
            Text(vehicle.make.uppercased())
                .font(Theme.label(8)).tracking(1.2)
                .foregroundStyle(tier.color)
                .lineLimit(1)
            Text(vehicle.model)
                .font(Theme.display(14, .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            HStack {
                Text(tier.label)
                    .font(Theme.label(8)).tracking(1).textCase(.uppercase)
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                Text(verbatim: "+\(tier.points)")
                    .font(Theme.mono(10, .bold))
                    .foregroundStyle(tier.color)
            }
        }
        .padding(8)
        .frame(width: 148)
        .background(Theme.glassFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(tier.color.opacity(0.35), lineWidth: 1))
    }
}

/// Vignette du garage. Reprend le vocabulaire de la vraie carte en plus compact.
struct MiniCard: View {
    let card: CardData

    var body: some View {
        // Chaque carte porte **son** contour. Deux réglages distincts :
        // — un trophée reçoit le néon doré, mais avec un halo resserré, sinon deux
        //   cartes voisines fusionnent en un seul cadre autour de la rangée ;
        // — une carte ordinaire reçoit un filet à la couleur de son palier, franchement
        //   visible. Le filet neutre d'origine était à 7 % de blanc : invisible, la
        //   carte flottait sans contour.
        NeonFrame(color: card.tier.frameColor ?? card.tier.color, radius: 18,
                  intensity: card.tier.isTrophy ? card.tier.frameIntensity : 0.7,
                  neon: card.tier.isTrophy, spread: 0.28) {
            VStack(alignment: .leading, spacing: 0) {
                artwork
                    .frame(height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        Text(String(format: "%03d", card.serial))
                            .font(Theme.mono(9, .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(6)
                    }
                    .overlay(alignment: .topTrailing) {
                        if card.firstSpot || card.verified {
                            Image(systemName: card.firstSpot ? "flag.fill" : "checkmark.seal.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(card.firstSpot ? RarityTier.trophyGold : Theme.textPrimary)
                                .frame(width: 20, height: 20)
                                .background(.ultraThinMaterial, in: Circle())
                                .padding(6)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.vehicle.make.uppercased())
                        .font(Theme.label(8)).tracking(1.4)
                        .foregroundStyle(card.tier.color)
                        .lineLimit(1)
                    Text(card.vehicle.model)
                        .font(Theme.display(15, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    HStack {
                        Text(card.tier.label)
                            .font(Theme.label(8)).tracking(1).textCase(.uppercase)
                            .foregroundStyle(card.tier.color)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(card.tier.color.opacity(0.14), in: Capsule())
                        Spacer()
                        Text("\(card.tier.points)")
                            .font(Theme.mono(11, .bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 4)
                .padding(.top, 9)
            }
            .padding(7)
        }
    }

    /// Le fond donne la taille, l'image se pose dessus : une image en remplissage posée
    /// dans une pile la ferait grandir au-delà de la vignette.
    private var artwork: some View {
        Rectangle()
            .fill(RadialGradient(colors: [card.tier.color.opacity(0.38), Theme.surface],
                                 center: .center, startRadius: 2, endRadius: 90))
            .overlay {
                if let developed = card.shot?.developed {
                    // Passée en studio : la même voiture, en rendu, montrée en entier.
                    StudioArt(image: developed)
                } else if let stylized = card.shot?.stylized {
                    // **La voiture reellement croisee, pas le modele.** Meme ordre de
                    // priorite que la fiche detaillee : un covering zebre, une livree
                    // de taxi ou un kit large n'existent que sur la photo du joueur.
                    // Le rendu studio les remplacerait par un exemplaire de catalogue.
                    Image(uiImage: stylized)
                        .resizable().scaledToFill()
                } else if let art = CarArt.image(for: card.vehicle.id, paint: card.paint) {
                    // Aucune photo : une carte de demonstration, ou un modele du
                    // Spogdex. Le rendu du modele fait alors reconnaitre la voiture.
                    StudioArt(image: art)
                } else {
                    // Ni rendu, ni photo : la silhouette de la carrosserie.
                    Image(systemName: CarBody(card.vehicle.body).symbol)
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(colors: [Theme.textPrimary.opacity(0.85),
                                                    Theme.textSecondary.opacity(0.3)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                }
            }
            .overlay(alignment: .bottom) {
                // Fondu vers la carte : l'image s'y enfonce au lieu de s'arrêter net.
                LinearGradient(colors: [.clear, Theme.surface.opacity(0.55)],
                               startPoint: .center, endPoint: .bottom)
            }
            .clipped()
    }
}
