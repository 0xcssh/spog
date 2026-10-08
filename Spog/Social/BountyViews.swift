import SwiftUI

/// La chasse de la semaine, en tête du garage : un pack scellé à ouvrir, puis les trois
/// cibles épinglées jusqu'à lundi.
struct BountyPanel: View {
    @Environment(AppState.self) private var app
    @Environment(BountyStore.self) private var bounty
    @State private var opening: BountyStore.Pack?
    @State private var busy = false

    var body: some View {
        if let pack = bounty.pack {
            GlassCard(radius: 22, tint: Theme.accent, padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    header(pack)
                    if pack.opened {
                        targets(pack)
                    } else {
                        sealed
                    }
                }
            }
            // Les rendus partent dès que les cibles sont connues : quand le joueur fait
            // défiler jusqu'au panneau, ils sont souvent déjà là.
            .task(id: pack.id) {
                if pack.opened { VehicleArtService.prefetch(pack.targets.map(\.vehicle_id)) }
            }
            .fullScreenCover(item: $opening) { pack in
                BountyOpeningView(pack: pack) { opening = nil }
            }
        }
    }

    private func header(_ pack: BountyStore.Pack) -> some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: "scope")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.background)
                .frame(width: 32, height: 32)
                .background(Theme.accentGradient, in: Circle())
                .shadow(color: Theme.accent.opacity(0.6), radius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Overline(text: "bounty.overline", color: Theme.accentBright)
                Group {
                    if pack.opened {
                        Text("bounty.progress \(pack.foundCount) \(pack.targets.count)")
                    } else {
                        Text("bounty.sealed.title")
                    }
                }
                .font(Theme.display(18))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            if let ends = pack.endsAt {
                InfoChip(icon: "clock",
                         text: Text("bounty.endsIn \(ends.formatted(.relative(presentation: .numeric)))"),
                         color: Theme.textSecondary)
            }
        }
    }

    // MARK: Pack scellé

    private var sealed: some View {
        HStack(spacing: 16) {
            SealedPack()
                .frame(width: 82, height: 112)
            VStack(alignment: .leading, spacing: 12) {
                Text("bounty.sealed")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task {
                        busy = true
                        if let pack = await bounty.open(country: app.country) { opening = pack }
                        busy = false
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles").font(.system(size: 11, weight: .bold))
                        Text("bounty.open")
                    }
                }
                .buttonStyle(NeonButtonStyle(fullWidth: false))
                .disabled(busy)
                .opacity(busy ? 0.5 : 1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Cibles

    private func targets(_ pack: BountyStore.Pack) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 9) {
                ForEach(pack.targets) { target in
                    BountyTargetCard(target: target, compact: true)
                }
            }
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                Text("bounty.hint")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Une cible du pack : son rendu studio, le modèle, la rareté locale, le bonus, et l'état
/// de la course. Compacte dans le garage (trois de front), en rangée à l'ouverture.
struct BountyTargetCard: View {
    let target: BountyStore.Target
    var compact: Bool = false

    private var tier: RarityTier { CatalogStore.shared.tier(target.tier) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous) }

    var body: some View {
        Group {
            if compact { compactLayout } else { wideLayout }
        }
        .background {
            ZStack {
                shape.fill(Theme.glassFill)
                shape.fill(tier.color.opacity(target.found ? 0.16 : 0.06))
            }
        }
        .overlay(shape.strokeBorder(tier.color.opacity(target.found ? 0.75 : 0.32), lineWidth: 1))
        .shadow(color: tier.color.opacity(target.found ? 0.45 : 0.18), radius: target.found ? 14 : 8)
    }

    private var art: some View {
        BountyArtView(vehicleID: target.vehicle_id, carBody: CarBody(target.body), tint: tier.color)
            .overlay(alignment: .topTrailing) {
                if target.found {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: compact ? 13 : 18))
                        .foregroundStyle(tier.color)
                        .shadow(color: tier.color.opacity(0.8), radius: 6)
                        .padding(6)
                }
            }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            art
                .frame(height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.bottom, 3)
            Text(target.make.uppercased())
                .font(Theme.label(8)).tracking(1.2)
                .foregroundStyle(tier.color)
                .lineLimit(1)
            Text(target.model)
                .font(Theme.display(13, .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(status)
                .font(Theme.mono(8, .semibold))
                .foregroundStyle(target.found ? tier.color : Theme.textSecondary)
                .lineLimit(2).minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var wideLayout: some View {
        HStack(spacing: 14) {
            art
                .frame(width: 132, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(target.make.uppercased())
                    .font(Theme.label(9)).tracking(1.4)
                    .foregroundStyle(tier.color)
                    .lineLimit(1)
                Text(target.model)
                    .font(Theme.display(18))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(tier.label)
                    .font(Theme.label(9)).tracking(1).textCase(.uppercase)
                    .foregroundStyle(tier.color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(tier.color.opacity(0.14), in: Capsule())
                Text(status)
                    .font(Theme.mono(10, .medium))
                    .foregroundStyle(target.found ? tier.color : Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Ce qui se joue sur cette cible : déjà trouvée, prise par un autre, ou ouverte avec le
    /// gros bonus du premier chasseur.
    private var status: String {
        if target.found { return String(localized: "bounty.found") }
        if target.takenFirst {
            if case .some(.some(let pseudo)) = target.first_hunter {
                return String(localized: "bounty.takenBy \(pseudo) \(target.bonus)")
            }
            return String(localized: "bounty.taken \(target.bonus)")
        }
        return String(localized: "bounty.open.bonus \(target.bonus + target.first_bonus)")
    }
}

/// Le visuel d'une cible : la silhouette tout de suite, puis le rendu studio en fondu dès
/// qu'il arrive (embarqué, en cache, ou généré par le serveur à la première demande).
struct BountyArtView: View {
    let vehicleID: String
    let carBody: CarBody
    let tint: Color
    @State private var image: UIImage?

    init(vehicleID: String, carBody: CarBody, tint: Color) {
        self.vehicleID = vehicleID
        self.carBody = carBody
        self.tint = tint
        // Ce qui est déjà sur l'appareil s'affiche dès la première image, sans fondu :
        // un rendu connu qui « arrive » à chaque ouverture ferait croire à un chargement.
        _image = State(initialValue: VehicleArtService.cachedImage(for: vehicleID))
    }

    var body: some View {
        // Le fond donne la taille ; l'image se pose dessus. Une image en remplissage posée
        // directement dans une pile la ferait grandir au-delà du cadre prévu.
        Rectangle()
            .fill(LinearGradient(colors: [tint.opacity(0.26), Theme.surface],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                RadialGradient(colors: [tint.opacity(0.35), .clear],
                               center: .bottom, startRadius: 2, endRadius: 110)
            }
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    Image(systemName: carBody.symbol)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(LinearGradient(colors: [Theme.textPrimary.opacity(0.75), tint.opacity(0.45)],
                                                        startPoint: .top, endPoint: .bottom))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .shimmer()
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: vehicleID) {
                guard image == nil else { return }
                guard let loaded = await VehicleArtService.image(for: vehicleID) else { return }
                withAnimation(.easeInOut(duration: 0.7)) { image = loaded }
            }
    }
}

/// Le pack scellé : une enveloppe néon, la seule image du jeu qui promette sans montrer.
private struct SealedPack: View {
    @State private var glow = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        shape
            .fill(LinearGradient(colors: [Theme.accent.opacity(0.75), Theme.accentDeep, Theme.surfaceRaised],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(DotGrid(spacing: 8).clipShape(shape))
            .overlay {
                VStack(spacing: 8) {
                    Image("LogoMark")
                        .resizable().scaledToFit()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    // Trois traits : les trois cibles qu'il renferme.
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule().fill(Theme.highlight.opacity(0.55)).frame(width: 10, height: 3)
                        }
                    }
                }
            }
            .overlay(shape.fill(Theme.sheen))
            .shimmer()
            .overlay(shape.strokeBorder(Theme.accentBright.opacity(glow ? 0.95 : 0.45), lineWidth: 1.2))
            .shadow(color: Theme.accent.opacity(glow ? 0.75 : 0.3), radius: glow ? 18 : 8)
            .rotationEffect(.degrees(glow ? -2 : 2))
            .offset(y: glow ? -3 : 3)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { glow = true }
            }
    }
}

/// L'ouverture du pack : les trois cartes se retournent une à une, la plus rare en dernier.
/// C'est le frisson de l'ouverture, sans rien vendre au hasard : le pack ne donne pas la
/// voiture, il donne une mission.
struct BountyOpeningView: View {
    let pack: BountyStore.Pack
    let onDone: () -> Void
    @State private var revealed = 0
    @State private var appeared = false

    private var allRevealed: Bool { revealed >= pack.targets.count }

    /// Teinte de la dernière carte retournée : la lueur du fond la suit, et la plus rare
    /// arrive en dernier, ce qui fait monter la lumière d'un cran à chaque carte.
    private var burst: Color {
        guard revealed > 0, revealed <= pack.targets.count else { return Theme.accent }
        return CatalogStore.shared.tier(pack.targets[revealed - 1].tier).color
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            RadialGradient(colors: [burst.opacity(0.32), .clear],
                           center: .center, startRadius: 10, endRadius: 380)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: revealed)

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        Overline(text: "bounty.overline", color: Theme.accentBright)
                        Text("bounty.reveal.title")
                            .font(Theme.display(30))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                        if let ends = pack.endsAt {
                            InfoChip(icon: "clock",
                                     text: Text("bounty.endsIn \(ends.formatted(.relative(presentation: .numeric)))"))
                        }
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)

                    VStack(spacing: 12) {
                        ForEach(Array(pack.targets.enumerated()), id: \.element.id) { index, target in
                            ZStack {
                                if index < revealed {
                                    BountyTargetCard(target: target)
                                        .transition(.asymmetric(
                                            insertion: .modifier(active: FlipIn(angle: -90), identity: FlipIn(angle: 0)),
                                            removal: .opacity))
                                } else {
                                    CardBack()
                                        .transition(.opacity)
                                }
                            }
                            .frame(maxWidth: 360)
                        }
                    }

                    VStack(spacing: 16) {
                        Text("bounty.hint")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(action: onDone) {
                            Text("bounty.reveal.done")
                        }
                        .buttonStyle(NeonButtonStyle())
                        .frame(maxWidth: 360)
                    }
                    .opacity(allRevealed ? 1 : 0)
                    .offset(y: allRevealed ? 0 : 16)
                    .animation(.easeOut(duration: 0.45), value: allRevealed)
                }
                .padding(.horizontal, 22)
                .padding(.top, 36)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .medium), trigger: revealed)
        .task {
            // Les trois rendus partent avant la première carte : la génération d'un rendu
            // inédit prend une vingtaine de secondes, autant la lancer pendant le spectacle.
            VehicleArtService.prefetch(pack.targets.map(\.vehicle_id))
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            // Une carte toutes les 0,7 s : assez lent pour l'attente, assez vif pour ne pas lasser.
            for index in pack.targets.indices {
                try? await Task.sleep(for: .milliseconds(index == 0 ? 650 : 750))
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { revealed = index + 1 }
            }
        }
    }
}

/// Dos d'une carte pas encore retournée : la marque Spog, et un reflet qui passe.
private struct CardBack: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        shape
            .fill(LinearGradient(colors: [Theme.surfaceRaised, Theme.surface],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(DotGrid(spacing: 10).clipShape(shape))
            .overlay {
                Image("LogoMark")
                    .resizable().scaledToFit()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .opacity(0.55)
            }
            .shimmer(duration: 2.2)
            .overlay(shape.strokeBorder(Theme.glassEdge, lineWidth: 1))
            .frame(height: 110)
    }
}

/// Retournement d'une carte autour de son axe vertical. L'opacité suit l'angle : à
/// quatre-vingt-dix degrés la carte est vue par la tranche, elle ne doit pas se voir.
private struct FlipIn: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .opacity(1 - min(1, abs(angle) / 90))
    }
}

extension BountyStore.Pack: Identifiable {
    var id: String { "\(week)-\(country)" }
}
