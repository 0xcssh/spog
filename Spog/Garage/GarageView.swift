import SwiftUI

/// Le garage : la collection, en grille. Ecran d'accueil de l'app.
///
/// Refait le 09/10/2026 : le testeur ne trouvait « toujours pas un vrai garage » en
/// arrivant. L'écran se lit maintenant de haut en bas comme un tableau de bord — titre,
/// niveau et chiffres du garage, chasse de la semaine, outils, puis les cartes, avec des
/// emplacements à remplir pour que la grille ait toujours l'air d'un garage et non d'une
/// liste. La structure s'inspire de ce qui se fait dans le genre ; le vocabulaire, la
/// typographie et la chasse restent les nôtres (règle App Store 4.3, voir REFONTE.md).
struct GarageView: View {
    /// Emmene le joueur vers le scan depuis le garage vide. Le garage ne connait
    /// pas les onglets : c'est la vue racine qui sait ou aller.
    var onScan: (() -> Void)?

    @Environment(AppState.self) private var app
    @Environment(GarageStore.self) private var garage
    @Environment(BountyStore.self) private var bounty
    @Environment(SubscriptionStore.self) private var subscriptions
    @State private var selected: CardData?
    @State private var browsingCatalog = false
    @State private var showingSettings = false
    @State private var showingPaywall = false
    @State private var query = GarageQuery()
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    /// Modèles à faire désirer tant que la collection est maigre (voir `discoverStrip`).
    @State private var teasers: [Teaser] = []

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    /// En dessous de ce nombre de cartes, la grille ne remplit pas l'écran : on montre
    /// sous elle ce qu'il reste de beau à trouver, plutôt qu'un grand vide noir.
    private static let teaserThreshold = 6

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                HomeStatsCard(onOpenPro: openPro)
                BountyPanel()
                if garage.cardCount == 0 {
                    emptyState
                } else {
                    collection(garage.cards)
                }
                if garage.cardCount < Self.teaserThreshold && !teasers.isEmpty {
                    discoverStrip
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        // La chasse bouge à chaque prise (une cible trouvée, un premier chasseur désigné).
        .task(id: "\(garage.catches.count)-\(app.country)") { await bounty.refresh(country: app.country) }
        .task(id: app.country) { teasers = Self.rankedTeasers(country: app.country) }
        // Le prix de la ligne Spog Pro : chargé une fois, sans attendre le paywall.
        .task { if subscriptions.monthly == nil { await subscriptions.load() } }
        .fullScreenCover(item: $selected) { card in
            CardDetailView(card: card)
        }
        .fullScreenCover(isPresented: $showingPaywall) { PaywallView() }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $browsingCatalog) {
            NavigationStack {
                CatalogExplorerView()
                    .background(Theme.background)
            }
            .preferredColorScheme(.dark)
        }
    }

    private func openPro() {
        Analytics.track(.paywallShown, ["from": "garage"])
        showingPaywall = true
    }

    // MARK: En-tête

    /// Le logo S et « Ton garage » : l'onglet s'appelle « Collection », et un testeur
    /// cherchait son garage sans comprendre qu'il était déjà dedans. À droite, le Spogdex
    /// (le catalogue n'a plus d'onglet) et les réglages.
    private var header: some View {
        HStack(spacing: 10) {
            Image("LogoMark")
                .resizable()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            Text("garage.title")
                .font(Theme.display(24))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            HomeIconButton(icon: "square.grid.3x3", label: "home.a11y.dex") { browsingCatalog = true }
            HomeIconButton(icon: "gearshape", label: "home.a11y.settings") { showingSettings = true }
        }
        .padding(.top, 2)
    }

    // MARK: Collection

    /// Outils puis grille. Les cartes sont lues une seule fois par rafraîchissement :
    /// `garage.cards` relit chaque photo depuis le disque.
    private func collection(_ all: [CardData]) -> some View {
        let shown = query.apply(to: all, mainCurrency: garage.estimatedValue?.currency)
        return VStack(alignment: .leading, spacing: 12) {
            GarageToolbar(query: $query, searching: $searching, searchFocused: $searchFocused,
                          shown: shown.count, total: all.count)
            if shown.isEmpty {
                noResults
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(shown) { card in
                        Button { selected = card } label: { MiniCard(card: card) }
                            .buttonStyle(PressScaleStyle())
                    }
                    // Les emplacements ne complètent que la grille entière : sous un
                    // filtre, ils diraient qu'il manque des cartes là où il n'en manque pas.
                    if !query.isFiltering {
                        ForEach(0..<GarageQuery.emptySlots(after: shown.count), id: \.self) { _ in
                            EmptySlot(action: onScan)
                        }
                    }
                }
            }
        }
    }

    private var noResults: some View {
        VStack(spacing: 10) {
            Text("home.noResults")
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    query.text = ""
                    query.tierID = nil
                }
            } label: {
                Text("home.clearFilters")
                    .font(Theme.label(10)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(Theme.textPrimary)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    /// Premier lancement : la grille est vide pour de vrai. Une phrase, le bouton qui mène
    /// au scan, et les quatre emplacements qui attendent leurs cartes.
    private var emptyState: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("garage.empty.title")
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("garage.empty.body")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)

            if let onScan {
                Button(action: onScan) {
                    HStack(spacing: 8) {
                        Image(systemName: "viewfinder").font(.system(size: 13, weight: .bold))
                        Text("garage.empty.action")
                    }
                }
                .buttonStyle(NeonButtonStyle())
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in EmptySlot(action: onScan) }
            }
        }
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
                        .foregroundStyle(Theme.textSecondary)
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
        .padding(.top, 8)
    }

    /// Les modèles qui ont un rendu embarqué, du plus rare au plus courant dans ce pays.
    /// Le rendu embarqué s'affiche tout de suite pendant que le rendu carré haute
    /// définition arrive (huit modèles par pays au plus, payés une fois pour tous).
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

// MARK: - Outils

/// Rangée d'outils au-dessus de la grille : recherche, filtre par rareté, tri, et le
/// compte des cartes affichées quand un filtre en retire.
private struct GarageToolbar: View {
    @Binding var query: GarageQuery
    @Binding var searching: Bool
    var searchFocused: FocusState<Bool>.Binding
    let shown: Int
    let total: Int

    private var tiers: [RarityTier] { CatalogStore.shared.tiers }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                HomeIconButton(icon: searching ? "xmark" : "magnifyingglass",
                               label: "home.a11y.search", action: toggleSearch)
                rarityMenu
                sortMenu
                Spacer(minLength: 0)
                if query.isFiltering {
                    Text(verbatim: "\(shown)/\(total)")
                        .font(Theme.mono(10, .semibold))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            if searching {
                searchField
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func toggleSearch() {
        withAnimation(.easeOut(duration: 0.2)) {
            searching.toggle()
            if !searching { query.text = "" }
        }
        searchFocused.wrappedValue = searching
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
            TextField(String(localized: "home.search.placeholder"), text: $query.text)
                .font(Theme.body(14))
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused(searchFocused)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private var rarityMenu: some View {
        Menu {
            Picker(selection: $query.tierID) {
                Text("home.filter.all").tag(String?.none)
                ForEach(tiers) { tier in
                    Text(tier.label).tag(Optional(tier.id))
                }
            } label: { EmptyView() }
        } label: {
            ToolChip(dot: selectedTier?.color) {
                if let tier = selectedTier { Text(tier.label) } else { Text("home.filter.all") }
            }
        }
        .accessibilityLabel(Text("home.a11y.filter"))
    }

    private var sortMenu: some View {
        Menu {
            Picker(selection: $query.sort) {
                ForEach(GarageQuery.Sort.allCases) { sort in
                    Text(LocalizedStringKey(sort.labelKey)).tag(sort)
                }
            } label: { EmptyView() }
        } label: {
            ToolChip(icon: "arrow.up.arrow.down") {
                Text(LocalizedStringKey(query.sort.labelKey))
            }
        }
        .accessibilityLabel(Text("home.a11y.sort"))
    }

    private var selectedTier: RarityTier? {
        guard let id = query.tierID else { return nil }
        return tiers.first { $0.id == id }
    }
}

/// Capsule d'outil à filet fin. La pastille, quand il y en a une, est le seul endroit où
/// la couleur du palier filtré apparaît.
private struct ToolChip<Title: View>: View {
    var icon: String? = nil
    var dot: Color? = nil
    @ViewBuilder var title: Title

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            }
            if let dot {
                Circle().fill(dot).frame(width: 6, height: 6)
            }
            title
                .font(Theme.label(10)).tracking(1.1)
                .textCase(.uppercase)
                .lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

/// Bouton rond à filet fin, pour les icônes de l'en-tête et des outils.
private struct HomeIconButton: View {
    let icon: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Cases de la grille

/// Hauteur commune des cases : une vignette et un emplacement vide côte à côte doivent
/// s'aligner, sinon la rangée boite.
private enum GridCell {
    static let height: CGFloat = 214
    static let artHeight: CGFloat = 124
    static let radius: CGFloat = 14
}

/// Emplacement à remplir : un cadre en pointillés, un plus, « À repérer ». Il mène au scan.
private struct EmptySlot: View {
    var action: (() -> Void)?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GridCell.radius, style: .continuous)
        Button { action?() } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("home.slot.empty")
                    .font(Theme.label(9)).tracking(1.4).textCase(.uppercase)
            }
            .foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity)
            .frame(height: GridCell.height)
            .background(Theme.surface.opacity(0.4), in: shape)
            .overlay(shape.strokeBorder(Theme.strokeStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .contentShape(shape)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(action == nil)
    }
}

/// Un modèle à faire désirer, avec sa rareté dans le pays du joueur.
private struct Teaser: Identifiable {
    let vehicle: Vehicle
    let tier: RarityTier
    var id: String { vehicle.id }
}

/// Aperçu d'un modèle du Spogdex pas encore attrapé : son rendu studio, sa rareté locale.
private struct TeaserCard: View {
    let vehicle: Vehicle
    let tier: RarityTier

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GridCell.radius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            // Bord à bord : le rendu carré du modèle remplit tout le haut de la carte. Le
            // rapport 1,4 ne rogne que du studio au-dessus et au-dessous de la voiture.
            ModelArt(vehicleID: vehicle.id, body: CarBody(vehicle.body), tint: tier.color)
                .aspectRatio(1.4, contentMode: .fit)
            RarityStrip(tier: tier)
            VStack(alignment: .leading, spacing: 3) {
                Text(vehicle.make.uppercased())
                    .font(Theme.label(8)).tracking(1.2)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                Text(vehicle.model)
                    .font(Theme.display(14, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(verbatim: "+\(tier.points)")
                    .font(Theme.mono(10, .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .frame(width: 148)
        .background(Theme.surface, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

/// Bande de rareté des vignettes : le palier en petites capitales neutres, et une jauge
/// de six crans à la couleur du palier. C'est le seul endroit coloré de la vignette.
private struct RarityStrip: View {
    let tier: RarityTier

    var body: some View {
        HStack(spacing: 6) {
            Text(tier.label)
                .font(Theme.label(8)).tracking(1.3).textCase(.uppercase)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { index in
                    Capsule()
                        .fill(index <= tier.rank ? tier.color : Theme.surfaceRaised)
                        .frame(width: 7, height: 3)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surfaceRaised.opacity(0.6))
        .overlay(alignment: .top) {
            Rectangle().fill(tier.color.opacity(0.8)).frame(height: 1)
        }
    }
}

/// Vignette du garage : la photo plein cadre en haut, la bande de rareté, la marque, le
/// modèle, et la date de la prise. Reprend le vocabulaire de la vraie carte en plus compact.
struct MiniCard: View {
    let card: CardData

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GridCell.radius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            artwork
                .frame(height: GridCell.artHeight)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topLeading) { serialTag }
                .overlay(alignment: .topTrailing) { markTag }
            RarityStrip(tier: card.tier)
            info
            Spacer(minLength: 0)
        }
        .frame(height: GridCell.height)
        .background(Theme.surface, in: shape)
        .clipShape(shape)
        // Un trophée garde un filet doré, fin et sans halo : il se repère dans la grille
        // sans transformer la rangée en guirlande.
        .overlay(shape.strokeBorder(card.tier.frameColor?.opacity(0.45) ?? Theme.stroke, lineWidth: 1))
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(card.vehicle.make.uppercased())
                .font(Theme.label(8)).tracking(1.4)
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
            Text(card.vehicle.model)
                .font(Theme.display(16, .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 4) {
                Text(card.caughtAt, format: .dateTime.day().month(.abbreviated).year(.twoDigits))
                    .font(Theme.mono(9))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(verbatim: "+\(card.tier.points)")
                    .font(Theme.mono(10, .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 5)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private var serialTag: some View {
        Text(String(format: "%03d", card.serial))
            .font(Theme.mono(9, .bold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(6)
    }

    @ViewBuilder private var markTag: some View {
        if card.firstSpot || card.verified {
            Image(systemName: card.firstSpot ? "flag.fill" : "checkmark.seal.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(card.firstSpot ? RarityTier.trophyGold : Theme.textPrimary)
                .frame(width: 20, height: 20)
                .background(.ultraThinMaterial, in: Circle())
                .padding(6)
        }
    }

    /// Le fond donne la taille, l'image se pose dessus : une image en remplissage posée
    /// dans une pile la ferait grandir au-delà de la vignette.
    private var artwork: some View {
        Rectangle()
            .fill(Theme.surfaceRaised)
            .overlay {
                if let developed = card.shot?.developed {
                    // Passée en studio : la même voiture, en rendu, montrée en entier sur
                    // son propre studio flouté.
                    DevelopedArt(image: developed)
                } else if let stylized = card.shot?.stylized {
                    // **La voiture reellement croisee, pas le modele.** Meme ordre de
                    // priorite que la fiche detaillee : un covering zebre, une livree
                    // de taxi ou un kit large n'existent que sur la photo du joueur.
                    // Le rendu studio les remplacerait par un exemplaire de catalogue.
                    Image(uiImage: stylized)
                        .resizable().scaledToFill()
                } else {
                    // Aucune photo : une carte de demonstration, ou un modele du
                    // Spogdex. Le rendu carré du modèle, en plein cadre ; en attendant,
                    // le rendu embarqué ou la silhouette (voir ModelArt).
                    ModelArt(vehicleID: card.vehicle.id, body: CarBody(card.vehicle.body),
                             tint: card.tier.color, paint: card.paint)
                }
            }
            .clipped()
    }
}
