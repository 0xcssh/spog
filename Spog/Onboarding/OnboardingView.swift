import SwiftUI

/// Parcours d'entrée, en six écrans.
///
/// **On joue avant de répondre.** Le premier écran est une prise de démonstration qu'on
/// passe aussitôt en studio, le deuxième montre le jeu. Un joueur à qui l'on demande un
/// pseudo avant de lui avoir montré ce que fait l'app n'a aucune raison d'en donner un.
/// Les questions viennent ensuite, regroupées : profil, compte (facultatif), terrain de
/// chasse, départ.
///
/// Ce qui a été retiré, et pourquoi (testeur, 08/10/2026) : l'écran des scans offerts
/// parlait de limites à quelqu'un qui n'avait pas encore joué — le décompte reste au
/// scan, Pro au paywall ; l'attente « préparation » ne préparait rien qu'on ne voie
/// ailleurs ; le code d'invitation, que presque personne n'a, occupait une étape entière
/// et n'est plus qu'un lien sur l'écran de départ. Neuf segments de progression se
/// lisaient comme un long formulaire.
///
/// Règle tenue : **on ne demande rien qui ne serve nulle part.** Le pseudo apparaît
/// au classement, la carrosserie préférée oriente la quête du jour, le pays et son mode
/// décident de la rareté et de la vérification des prises.
struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerProfile.self) private var profile

    @Environment(LocationProvider.self) private var location
    @Environment(ReferralStore.self) private var referral
    /// Injecté par `RootView` sur le `Group` qui contient aussi l'onboarding : il est donc
    /// là avant même que le joueur ait fini son premier lancement.
    @Environment(AccountStore.self) private var account

    @State private var step: Step = .demo
    @State private var pickingCountry = false
    /// Position refusée : il faut le dire, sinon le repli en mode manuel est inexplicable.
    @State private var locationRefused = false
    /// Code d'invitation en cours de saisie. Vide = le joueur n'en a pas, c'est permis.
    @State private var referralCode = ""
    /// Le champ du code ne s'ouvre qu'à la demande : la plupart des joueurs n'en ont pas.
    @State private var showsReferral = false
    @FocusState private var typing: Bool
    /// Hauteur de l'écran hors clavier. Les visuels se dimensionnent sur elle : sans ça,
    /// ouvrir le clavier rétrécissait la grille des goûts sous le doigt du joueur.
    @State private var restingHeight: CGFloat = 0

    private let store = CatalogStore.shared

    /// Prise de démonstration, préparée à l'ouverture. Elle vit ici et non dans l'étape :
    /// revenir en arrière ne doit pas faire perdre la carte déjà attrapée.
    @State private var demo: OnboardingDemo?
    @State private var demoPhase: DemoPhase = .aiming
    @State private var flash = false
    @State private var scanSweep = false
    @State private var developing = false
    @State private var developed = false
    @State private var developSweep: CGFloat = -0.4

    enum DemoPhase { case aiming, scanning, caught }

    /// Où en est la connexion Apple de l'étape compte. Une annulation ramène à `idle` :
    /// le joueur a changé d'avis, ce n'est pas une erreur à lui montrer.
    @State private var appleLink: AppleLinkState = .idle
    enum AppleLinkState { case idle, linked, failed }

    /// Les noms des cas partent tels quels dans `.onboardingStep` : les renommer casse la
    /// continuité des courbes d'analytics.
    enum Step: Int, CaseIterable {
        case demo, game, profile, account, location, ready
    }

    /// Place disponible pour le contenu d'une étape, gouttières et barres déduites.
    /// Chaque écran répartit son contenu sur toute cette hauteur au lieu de s'empiler en
    /// haut : sur les captures du testeur, la moitié basse de chaque écran était vide.
    struct Metrics {
        let width: CGFloat
        let height: CGFloat
        /// iPhone SE et mini : on retire le décor et le détail avant de faire défiler.
        /// Seuil mesuré : un 6,1 pouces laisse ~600 pt au contenu, un mini ~570.
        var compact: Bool { height < 590 }

        func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            min(max(value, low), high)
        }
    }

    var body: some View {
        ZStack {
            backdrop

            GeometryReader { geo in
                let sizing = typing && restingHeight > 0 ? restingHeight : geo.size.height
                let metrics = Metrics(width: max(geo.size.width - 48, 220),
                                      height: max(sizing - 24, 420))
                ScrollView {
                    stepContent(metrics)
                        // Chaque étape entre par la droite et l'ancienne s'efface : sans `id`,
                        // SwiftUI recycle la vue et l'écran change d'un bloc, sans transition.
                        .id(step)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 28)),
                                                removal: .opacity))
                        // Hauteur minimale = l'écran : les `Spacer` des étapes s'étirent
                        // jusqu'au bouton. Plus haut que l'écran (petit iPhone, clavier),
                        // le contenu défile au lieu de déborder.
                        .frame(maxWidth: .infinity, minHeight: max(geo.size.height - 24, 0),
                               alignment: .top)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: geo.size.height, initial: true) { _, height in
                    if !typing { restingHeight = height }
                }
            }
            .safeAreaInset(edge: .top) { topBar }
            // `safeAreaInset` est la seule construction qui repousse reellement les
            // commandes au-dessus du clavier. Un simple VStack les laisse dessous. Le
            // bouton reste donc le même pendant la saisie : un second bouton accroché
            // à la barre du clavier faisait doublon et flottait à droite, bricolé.
            .safeAreaInset(edge: .bottom) {
                action
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 10)
                    .background(alignment: .top) { footerFade }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $pickingCountry) { MarketPickerSheet() }
        .sensoryFeedback(.success, trigger: demoPhase == .caught)
        .sensoryFeedback(.impact(weight: .light), trigger: developed)
        .task {
            // Le pays connu à l'ouverture est celui de l'appareil : c'est lui qui choisit
            // la voiture de démonstration. S'il change plus loin, la démonstration est
            // déjà jouée, et rien ne la contredit.
            if demo == nil { demo = OnboardingDemo.make(country: app.country) }
            // Rendu haute définition s'il est déjà là ou s'il arrive : la démo commence
            // toujours sur le rendu embarqué, qui marche hors ligne, et gagne en netteté
            // ensuite sans changer de carte.
            guard let current = demo,
                  let sharper = await VehicleArtService.remoteImage(for: current.vehicle.id)
            else { return }
            // Détourée et posée sur le studio unique ; si Vision n'y arrive pas, le rendu
            // tel quel, recadré comme avant.
            let cutout = await ModelCutoutService.hdCutout(for: current.vehicle.id, from: sharper)
            let candidate: OnboardingDemo?
            if let cutout {
                candidate = current.upgraded(withCutout: cutout)
            } else {
                candidate = current.upgraded(with: sharper)
            }
            guard let upgraded = candidate else { return }
            withAnimation(.easeInOut(duration: 0.3)) { demo = upgraded }
        }
    }

    @ViewBuilder private func stepContent(_ m: Metrics) -> some View {
        switch step {
        case .demo:     demoStep(m)
        case .game:     gameStep(m)
        case .profile:  profileStep(m)
        case .account:  accountStep(m)
        case .location: locationStep(m)
        case .ready:    readyStep(m)
        }
    }

    /// Fond de tout le parcours : le même noir neutre que le reste de l'app. Les deux
    /// lueurs violettes et la trame de points sont parties avec la sobriété du 09/10/2026.
    private var backdrop: some View {
        AmbientBackground()
    }

    /// Fondu vers le fond de l'écran, jamais une bande opaque : le contenu qui défile
    /// s'efface sous le bouton au lieu d'être coupé net.
    private var footerFade: some View {
        LinearGradient(stops: [.init(color: Theme.background.opacity(0), location: 0),
                               .init(color: Theme.background.opacity(0.92), location: 0.4),
                               .init(color: Theme.background, location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
    }

    // MARK: 1 — Prise de démonstration et passage en studio

    /// L'accroche est une prise, pas un discours : une voiture est déjà dans le viseur,
    /// il reste à appuyer. Aucune caméra, aucune autorisation — on les demanderait à
    /// quelqu'un qui ne sait pas encore pourquoi. La carte obtenue passe en studio sur le
    /// même écran : c'est le même geste, le couper en deux étapes l'allongeait pour rien.
    private func demoStep(_ m: Metrics) -> some View {
        // La scène garde la même hauteur du viseur à la carte : rien ne saute à la prise.
        let stage = m.clamp(m.height - (m.compact ? 238 : 300), 210, 470)
        return VStack(spacing: 0) {
            VStack(spacing: m.compact ? 6 : 10) {
                if !m.compact { brandRow }
                Text(demoTitle)
                    .font(Theme.display(m.compact ? 26 : 32))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
                Text("onboarding.tagline")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 14)

            ZStack {
                if demoPhase == .caught, let demo {
                    demoCard(demo)
                        .frame(width: stage * 0.70)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    demoViewfinder(height: stage, maxWidth: m.width)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: stage)

            Spacer(minLength: 14)

            demoFooter
                .frame(maxWidth: .infinity)
                .frame(minHeight: m.compact ? 96 : 116, alignment: .top)
        }
    }

    private var brandRow: some View {
        HStack(spacing: 10) {
            Image("LogoMark")
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(verbatim: "SPOG")
                .font(Theme.display(16, .heavy)).tracking(5)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var demoTitle: LocalizedStringKey {
        if developed { return "onboarding.develop.done" }
        return demoPhase == .caught ? "onboarding.demo.caught" : "onboarding.demo.title"
    }

    private func demoViewfinder(height: CGFloat, maxWidth: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.surface)
                .overlay(DotGrid(spacing: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)))

            if let raw = demo?.raw ?? demo?.studio {
                // Le cliché est déjà cadré presque carré : il remplit le viseur, la voiture
                // au centre, sans bande vide au-dessus ni au-dessous.
                Color.clear
                    .overlay {
                        Image(uiImage: raw)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
            }

            if demoPhase == .scanning {
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, Theme.highlight.opacity(0.7), .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1.5)
                    .offset(y: (scanSweep ? 0.4 : -0.4) * height)
            }

            // Mêmes équerres blanches que le vrai viseur.
            CornerBrackets(color: demoPhase == .scanning ? Theme.textPrimary : Theme.textPrimary.opacity(0.8))
                .padding(18)

            // L'éclair du déclenchement : sans lui, rien ne dit que la photo est prise.
            Theme.textPrimary
                .opacity(flash ? 0.8 : 0)
                .allowsHitTesting(false)
        }
        .aspectRatio(0.95, contentMode: .fit)
        .frame(maxWidth: maxWidth, maxHeight: height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.strokeStrong, lineWidth: 1))
    }

    /// Sous la scène : le déclencheur avant la prise, puis la rareté obtenue et ce qu'il
    /// reste à faire. Le passage en studio se déclenche aussi par le bouton du bas.
    @ViewBuilder private var demoFooter: some View {
        if demoPhase == .caught, let demo {
            VStack(spacing: 10) {
                Overline(text: "onboarding.demo.caughtTier \(tierName(demo.tier)) \(store.countryName(app.country))",
                         color: demo.tier.color)
                if developed {
                    Text("onboarding.demo.note")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("onboarding.develop.hint")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 8)
                }
            }
            .transition(.opacity)
        } else {
            demoShutter
        }
    }

    private var demoShutter: some View {
        VStack(spacing: 10) {
            Button { shootDemo() } label: {
                ZStack {
                    Circle()
                        .stroke(Theme.highlight.opacity(0.35), lineWidth: 2)
                        .frame(width: 84, height: 84)
                    Circle()
                        .fill(Theme.accentGradient)
                        .frame(width: 70, height: 70)
                    Image(systemName: "viewfinder")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .opacity(demoPhase == .aiming ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .disabled(demoPhase != .aiming)
            .accessibilityLabel(Text("onboarding.demo.shutter"))

            Overline(text: demoPhase == .scanning ? "scan.working" : "onboarding.demo.hint",
                     color: demoPhase == .scanning ? Theme.textSecondary : Theme.textMuted)
        }
    }

    /// Le temps d'une vraie identification, en plus court : assez pour qu'on voie le
    /// viseur travailler, pas assez pour que l'attente devienne le souvenir de l'écran.
    private func shootDemo() {
        guard demoPhase == .aiming else { return }
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeIn(duration: 0.35)) { flash = false }
            demoPhase = .scanning
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                scanSweep = true
            }
            try? await Task.sleep(for: .milliseconds(1700))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { demoPhase = .caught }
        }
    }

    /// La carte attrapée. Toucher la carte la passe en studio : la même carte, d'abord le
    /// cliché terne, puis le rendu net.
    private func demoCard(_ demo: OnboardingDemo) -> some View {
        CollectibleCardView(card: demo.card(developed: developed,
                                            place: store.countryName(app.country)),
                            interactive: developed, showsShotToggle: false)
            .blur(radius: developing ? 5 : 0)
            .brightness(developing ? 0.12 : 0)
            .overlay { developLight }
            .overlay {
                // Par-dessus la carte, sinon sa propre zone d'image garderait le
                // toucher pour elle et le passage en studio ne partirait jamais.
                if !developed {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { develop() }
                }
            }
    }

    private func tierName(_ tier: RarityTier) -> String {
        String(localized: String.LocalizationValue(tier.key))
    }

    /// Bande de lumière qui balaie la carte pendant le passage en studio.
    private var developLight: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, Theme.highlight.opacity(0.35), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: geo.size.height * 0.4)
                .offset(y: developSweep * geo.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .blendMode(.plusLighter)
        .opacity(developing ? 1 : 0)
        .allowsHitTesting(false)
    }

    /// L'image change sous la lumière, au milieu du balayage : un fondu direct d'une
    /// image à l'autre se lit comme un simple changement de photo.
    private func develop() {
        guard !developed, !developing else { return }
        developSweep = -0.4
        withAnimation(.easeOut(duration: 0.2)) { developing = true }
        withAnimation(.linear(duration: 1.3)) { developSweep = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeInOut(duration: 0.3)) { developed = true }
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.easeOut(duration: 0.4)) { developing = false }
        }
    }

    // MARK: 2 — Le jeu

    private func gameStep(_ m: Metrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            stepHeader(overline: "onboarding.game.overline", title: "onboarding.game.title",
                       compact: m.compact)
            Spacer(minLength: m.compact ? 12 : 16)
            rarityContrast(m)
            Spacer(minLength: m.compact ? 12 : 16)
            rulesPanel(m)
            Spacer(minLength: 0)
        }
    }

    /// La différence de Spog, montrée sur une vraie fiche du catalogue : le même modèle,
    /// deux pays, deux paliers. C'est le visuel de l'écran : le rendu prend la hauteur
    /// qui reste, et c'est lui qui rétrécit en premier sur un petit iPhone.
    @ViewBuilder private func rarityContrast(_ m: Metrics) -> some View {
        if let contrast = demo?.contrast {
            NeonFrame(radius: 18, neon: true, spread: 0.6) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("onboarding.game.rarity.title")
                        .font(Theme.display(m.compact ? 18 : 20, .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Le studio unique, comme partout : rendu HD détouré dès qu'il est là,
                    // découpe du rendu embarqué en attendant (le modèle en a toujours un).
                    ModelArt(vehicleID: contrast.vehicle.id, body: CarBody(contrast.vehicle.body),
                             tint: contrast.elsewhere.color)
                        .frame(maxWidth: .infinity)
                        .frame(height: m.clamp(m.height - 540, 56, 130))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(contrast.vehicle.fullName)
                        .font(Theme.mono(13, .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 8) {
                        tierChip(country: app.country, tier: contrast.here)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.textMuted)
                        tierChip(country: contrast.elsewhereCountry, tier: contrast.elsewhere)
                    }

                    // Sur petit écran, les deux paliers côte à côte disent déjà tout.
                    if !m.compact {
                        Text("onboarding.game.rarity.body")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
            }
        } else {
            NeonFrame(radius: 18) {
                ruleRow(icon: "globe.europe.africa.fill", title: "onboarding.game.rarity.title",
                        body: "onboarding.game.rarity.body", showsBody: true)
            }
        }
    }

    private func tierChip(country: String, tier: RarityTier) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(store.countryName(country))
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(tier.label)
                .font(Theme.mono(11, .bold))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(tier.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(tier.color.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(tier.color.opacity(0.4), lineWidth: 1))
    }

    /// Les trois règles dans un seul panneau : trois cadres néon empilés faisaient une
    /// colonne de boîtes identiques où l'œil ne savait où se poser. Sur petit écran, les
    /// titres seuls : le détail se retrouve dans l'app, le premier lancement doit tenir
    /// sans défiler.
    private func rulesPanel(_ m: Metrics) -> some View {
        NeonFrame(radius: 18) {
            VStack(spacing: 0) {
                ruleRow(icon: "trophy.fill", title: "onboarding.game.league.title",
                        body: "onboarding.game.league.body \(OnboardingRules.leagueSize) \(OnboardingRules.leaguePromote)",
                        showsBody: !m.compact)
                rowDivider
                ruleRow(icon: "scope", title: "onboarding.game.bounty.title",
                        body: "onboarding.game.bounty.body \(OnboardingRules.bountyTargets)",
                        showsBody: !m.compact)
                rowDivider
                ruleRow(icon: "flag.checkered", title: "onboarding.game.first.title",
                        body: "onboarding.game.first.body", showsBody: !m.compact)
            }
            .padding(.vertical, 2)
        }
    }

    private func ruleRow(icon: String, title: LocalizedStringKey,
                         body: LocalizedStringKey, showsBody: Bool) -> some View {
        HStack(alignment: showsBody ? .top : .center, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accentBright)
                .frame(width: 34, height: 34)
                .background(Theme.accent.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.display(15, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if showsBody {
                    Text(body)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var rowDivider: some View {
        Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 61)
    }

    // MARK: Briques communes

    /// En-tête des écrans de questions : une étiquette, un titre fort, une raison.
    private func stepHeader(overline: LocalizedStringKey, title: LocalizedStringKey,
                            why: LocalizedStringKey? = nil, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Overline(text: overline)
            Text(title)
                .font(Theme.display(compact ? 26 : 30))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let why {
                Text(why)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusLine(_ icon: String, _ text: LocalizedStringKey,
                            color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    // MARK: 3 — Profil : pseudo et goûts

    /// Deux questions courtes sur un seul écran : chacune seule laissait un écran presque
    /// vide, et doublait la longueur apparente du parcours.
    private func profileStep(_ m: Metrics) -> some View {
        // Les cases des goûts prennent la hauteur qui reste : grandes sur un grand écran,
        // jamais sous la taille d'un doigt sur un petit.
        let cell = m.clamp((m.height - 400) / 3, 56, 104)
        return VStack(alignment: .leading, spacing: 0) {
            stepHeader(overline: "onboarding.profile.overline", title: "onboarding.nickname.title",
                       why: "onboarding.nickname.why", compact: m.compact)
            nicknameField
                .padding(.top, 14)

            Spacer(minLength: m.compact ? 18 : 22)

            VStack(alignment: .leading, spacing: 6) {
                Text("onboarding.taste.title")
                    .font(Theme.display(20))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !m.compact {
                    Text("onboarding.taste.why")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("onboarding.taste.multi")
                    .font(Theme.label(10)).tracking(0.8)
                    .foregroundStyle(Theme.accent)
            }

            // Plusieurs réponses : toucher n'enchaîne pas, sinon le premier choix fermerait
            // la question. C'est le bouton du bas qui avance.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(PlayerProfile.choices, id: \.body) { choice in
                    tasteCard(choice.body, icon: choice.icon, height: cell)
                }
            }
            .padding(.top, 12)

            Spacer(minLength: 0)
        }
    }

    /// Pas de clavier ouvert d'office : il cacherait la moitié de l'écran, goûts compris.
    private var nicknameField: some View {
        @Bindable var player = profile
        return TextField(text: $player.nickname) {
            Text("onboarding.nickname.placeholder")
        }
        .focused($typing)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.done)
        .onSubmit { typing = false }
        .font(Theme.display(19, .semibold))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 16).padding(.vertical, 15)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(typing ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1))
    }

    private func tasteCard(_ body: String, icon: String, height: CGFloat) -> some View {
        let selected = profile.favouriteBodies.contains(body)
        return Button {
            @Bindable var player = profile
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                if selected { player.favouriteBodies.remove(body) }
                else        { player.favouriteBodies.insert(body) }
            }
        } label: {
            VStack(spacing: height > 80 ? 10 : 6) {
                Image(systemName: icon)
                    .font(.system(size: height > 80 ? 24 : 19, weight: .medium))
                    .foregroundStyle(selected ? Theme.accentBright : Theme.textSecondary)
                Text(LocalizedStringKey("taste." + body))
                    .font(Theme.display(13, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.accentBright)
                        .padding(9)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .background(selected ? Theme.accent.opacity(0.14) : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Theme.accent.opacity(0.7) : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: 4 — Compte

    /// Juste après le pseudo : le joueur vient de se donner un nom, c'est le moment où le
    /// garder a un sens. Jamais obligatoire — « Plus tard » avance aussi bien, et l'onglet
    /// Social repropose la même chose. Les bénéfices sont ceux que le serveur tient
    /// vraiment (`apple_link`) : rien n'est promis qui n'existe pas.
    private func accountStep(_ m: Metrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            stepHeader(overline: "onboarding.account.overline", title: "onboarding.account.title",
                       why: m.compact ? nil : LocalizedStringKey("onboarding.account.why"),
                       compact: m.compact)

            Spacer(minLength: m.compact ? 12 : 16)

            // La fiche du joueur n'apparaît que s'il reste de la place : sur un petit
            // iPhone, les bénéfices et le bouton passent avant le décor.
            if m.height >= 640 {
                accountPreview
                Spacer(minLength: 14)
            }

            NeonFrame(radius: 18) {
                AccountBenefitsList(showsDetails: !m.compact)
                    .padding(14)
            }

            Spacer(minLength: m.compact ? 14 : 18)

            VStack(alignment: .leading, spacing: 10) {
                if appleLinked {
                    accountLinkedBadge
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else {
                    AppleLinkButton { outcome in handleApple(outcome) }
                    if appleLink == .failed {
                        statusLine("exclamationmark.triangle.fill", "onboarding.account.failed",
                                   color: Theme.warning)
                    }
                    AccountPrivacyNote()
                }
            }
        }
        .sensoryFeedback(.success, trigger: appleLinked)
    }

    /// Relié pendant cette étape, ou déjà relié (compte Apple retrouvé sur cet appareil).
    private var appleLinked: Bool {
        appleLink == .linked || account.profile?.apple_linked == true
    }

    /// La fiche du joueur avec le pseudo qu'il vient de choisir : ce qu'il risque de perdre
    /// devient concret, et la pastille passe à « sauvegardé » sous ses yeux.
    private var accountPreview: some View {
        let nickname = profile.nickname.trimmingCharacters(in: .whitespaces)
        let handle = nickname.isEmpty ? profile.displayName : "@\(nickname)"
        let initial = String(profile.displayName.prefix(1)).uppercased()
        let chip: LocalizedStringKey = appleLinked ? "onboarding.account.saved" : "onboarding.account.unsaved"
        return GlassCard(radius: 18, padding: 14) {
            HStack(spacing: 13) {
                ZStack {
                    Circle().fill(Theme.surfaceRaised)
                    Text(verbatim: initial)
                        .font(Theme.hero(20))
                        .foregroundStyle(Theme.textPrimary)
                }
                .frame(width: 46, height: 46)
                .overlay(Circle().strokeBorder(Theme.strokeStrong, lineWidth: 1))
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: handle)
                        .font(Theme.display(18))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    InfoChip(icon: appleLinked ? "checkmark.shield.fill" : "exclamationmark.shield",
                             text: Text(chip),
                             color: appleLinked ? Theme.neutralAccent : Theme.textMuted)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// La coche de réussite, à la place du bouton : on passe à la suite tout seul.
    private var accountLinkedBadge: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("onboarding.account.done")
                .font(Theme.display(15, .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(minHeight: 50)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.strokeStrong, lineWidth: 1))
    }

    private func handleApple(_ outcome: AppleLinkButton.Outcome) {
        switch outcome {
        case .cancelled:
            appleLink = .idle
        case .failed:
            withAnimation(.easeOut(duration: 0.25)) { appleLink = .failed }
        case .linked:
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { appleLink = .linked }
            reservePseudo()
            Task { @MainActor in
                // Le temps de voir la coche : enchaîner aussitôt ferait croire à un saut.
                try? await Task.sleep(for: .milliseconds(1100))
                // Le joueur a pu avancer ou revenir lui-même entre-temps.
                if step == .account { advance() }
            }
        }
    }

    /// Le pseudo de l'étape précédente ne vit que sur le téléphone tant que le joueur ne
    /// l'enregistre pas dans l'onglet Social. Le compte promet « ton pseudo, à ton nom » :
    /// on le réserve donc ici, s'il a la forme acceptée et que le compte n'en porte pas
    /// déjà un (un compte Apple retrouvé garde le sien). Un refus (pris, réseau) reste
    /// silencieux : le joueur pourra toujours le choisir plus tard.
    private func reservePseudo() {
        let pseudo = profile.nickname.trimmingCharacters(in: .whitespaces)
        guard account.profile?.pseudo == nil, AccountStore.isValidPseudo(pseudo) else { return }
        Task { @MainActor in _ = await account.setPseudo(pseudo) }
    }

    // MARK: 5 — Pays et mode

    private func locationStep(_ m: Metrics) -> some View {
        // Le visuel n'apparaît que s'il reste vraiment de la place : sur un petit iPhone,
        // les deux modes et l'avertissement passent avant le décor.
        let beacon = min(m.height - 510, 170)
        return VStack(alignment: .leading, spacing: 0) {
            stepHeader(overline: "onboarding.market.overline", title: "onboarding.market.title",
                       why: "onboarding.market.why", compact: m.compact)

            Spacer(minLength: 14)

            if beacon >= 80 {
                LocationBeacon(icon: app.locationMode == .automatic ? "location.fill" : "mappin",
                               searching: app.locationMode == .automatic && location.isResolving)
                    .frame(width: beacon, height: beacon)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 14)
            }

            VStack(spacing: 10) {
                modeCard(.automatic, icon: "location.fill",
                         title: "onboarding.auto.title", body: "onboarding.auto.body")
                modeCard(.manual, icon: "mappin",
                         title: "onboarding.manual.title", body: "onboarding.manual.body")

                autoStatus

                if app.locationMode == .manual {
                    Button { pickingCountry = true } label: {
                        HStack {
                            Text(store.countryName(app.country))
                                .font(Theme.display(15, .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .padding(.horizontal, 15).padding(.vertical, 14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 16)

            safetyNote
        }
    }

    /// Sécurité routière : dite ici parce que c'est la position qui permet au scan de se
    /// bloquer vraiment au-delà du seuil. Elle avait migré sur l'écran des scans offerts,
    /// supprimé : sans elle, rien ne l'annonçait plus avant la première prise.
    private var safetyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.warning)
            Text("onboarding.safety \(ScannerView.maxScanSpeedText)")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        // L'ambre ne reste que sur l'icône : un encadré doré entier criait plus fort que
        // le bouton principal de l'écran.
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Theme.stroke, lineWidth: 1))
    }

    /// Ce que la position donne, en direct. Sans ça le joueur choisit « automatique »,
    /// ne voit rien changer, et découvre à la fin un pays qui n'est pas le sien.
    @ViewBuilder private var autoStatus: some View {
        if locationRefused {
            statusLine("exclamationmark.triangle.fill", "onboarding.location.denied",
                       color: Theme.warning)
        } else if app.locationMode == .automatic {
            if location.isResolving {
                statusLine("location.circle", "onboarding.locating", color: Theme.textMuted)
            } else if location.countryCode != nil {
                statusLine("checkmark.circle.fill",
                           LocalizedStringKey("onboarding.location.found \(placeText)"),
                           color: Theme.accent)
            }
        }
    }

    /// Résout le pays **tout de suite**, pas au moment de terminer : l'écran de départ
    /// doit montrer ce qui est vrai. Un refus fait retomber en mode manuel, sinon les
    /// prises seraient marquées vérifiables alors que le pays est déclaré à la main.
    private func resolveAutomatically() {
        locationRefused = false
        location.currentCountry { code in
            @Bindable var state = app
            if let code {
                state.country = code
            } else if location.status == .denied {
                state.locationMode = .manual
                locationRefused = true
            }
        }
    }

    private func modeCard(_ mode: AppState.LocationMode, icon: String,
                          title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        let selected = app.locationMode == mode
        return Button {
            @Bindable var state = app
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.locationMode = mode }
            if mode == .automatic { resolveAutomatically() } else { locationRefused = false }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? Theme.accentBright : Theme.textMuted)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.display(15, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(body)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? Theme.accent : Theme.textMuted)
            }
            .padding(15)
            .background(selected ? Theme.accent.opacity(0.1) : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: 6 — Départ

    /// Une seule fin, forte : le récapitulatif et l'écran d'attente « préparation » se
    /// succédaient sans rien apprendre de plus au joueur. Le code d'invitation vit ici,
    /// replié : un lien pour ceux qui en ont un, rien pour les autres.
    private func readyStep(_ m: Metrics) -> some View {
        let logo = m.clamp(m.height * 0.19, 72, 124)
        return VStack(spacing: 0) {
            Spacer(minLength: 6)

            Image("LogoMark")
                .resizable()
                .frame(width: logo, height: logo)
                .clipShape(RoundedRectangle(cornerRadius: logo * 0.25, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: logo * 0.25, style: .continuous)
                    .strokeBorder(Theme.strokeStrong, lineWidth: 1))

            VStack(spacing: 8) {
                Text("onboarding.recap.title \(profile.displayName)")
                    .font(Theme.display(m.compact ? 26 : 30))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("onboarding.ready.subtitle")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, m.compact ? 16 : 24)

            Spacer(minLength: 18)

            VStack(alignment: .leading, spacing: 8) {
                NeonFrame(radius: 16) {
                    VStack(spacing: 0) {
                        recapRow("mappin", "onboarding.recap.place", placeText)
                        rowDivider
                        recapRow(app.locationMode == .automatic ? "location.fill" : "hand.tap.fill",
                                 "onboarding.recap.mode",
                                 String(localized: app.locationMode == .automatic
                                        ? "onboarding.auto.title" : "onboarding.manual.title"))
                        if !profile.favouriteBodies.isEmpty {
                            rowDivider
                            recapRow("heart.fill", "onboarding.recap.taste", favouritesText)
                        }
                    }
                }
                Text("onboarding.recap.editable")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 4)
            }

            Spacer(minLength: 18)

            referralSection
        }
        .onAppear {
            // Code reçu par un lien : on le montre déjà rempli, jamais appliqué en douce.
            if referralCode.isEmpty, let pending = referral.pendingFromLink {
                referralCode = pending
                showsReferral = true
            }
        }
    }

    @ViewBuilder private var referralSection: some View {
        if showsReferral {
            VStack(alignment: .leading, spacing: 8) {
                TextField(text: $referralCode) {
                    Text("referral.placeholder")
                }
                .focused($typing)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { typing = false }
                .font(Theme.mono(20, .bold))
                .tracking(6)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(typing ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1))
                // Le code est remis en forme pendant la frappe : minuscules, tirets et
                // confusions O/0 ou I/1 corrigés à la volée plutôt que refusés à l'envoi.
                .onChange(of: referralCode) { _, typed in
                    let cleaned = ReferralStore.normalize(typed)
                    if cleaned != typed { referralCode = cleaned }
                }

                referralFeedback

                Text("onboarding.referral.why")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showsReferral = true }
                // Le champ n'existe qu'après l'animation : lui donner le focus dans le même
                // instant ne ferait rien.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    typing = true
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("onboarding.referral.link")
                        .font(Theme.mono(11, .semibold))
                }
                .foregroundStyle(Theme.accentBright)
                .padding(.vertical, 10).padding(.horizontal, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }

    /// Réponse pendant la frappe. Un message d'erreur découvert après coup arrive trop tard.
    @ViewBuilder private var referralFeedback: some View {
        switch referral.check(referralCode) {
        case .ready:
            statusLine("checkmark.circle.fill", "referral.valid", color: Theme.accent)
        case .ownCode:
            statusLine("exclamationmark.triangle.fill", "referral.ownCode",
                       color: Theme.warning)
        case .tooShort:
            statusLine("ellipsis.circle", "referral.tooShort", color: Theme.textMuted)
        case .empty:
            EmptyView()
        }
    }

    /// Le lieu tel qu'on le connaît vraiment à cet instant — jamais une valeur par défaut
    /// présentée comme un résultat. En automatique, tant que la position n'a pas répondu,
    /// on le dit au lieu d'afficher le pays de l'appareil.
    private var placeText: String {
        if app.locationMode == .automatic && location.isResolving {
            return String(localized: "onboarding.locating")
        }
        let country = store.countryName(app.country)
        if let city = location.city, app.locationMode == .automatic {
            return "\(city), \(country)"
        }
        return country
    }

    private var favouritesText: String {
        profile.favouriteList
            .map { String(localized: String.LocalizationValue("taste." + $0)) }
            .joined(separator: ", ")
    }

    private func recapRow(_ icon: String, _ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.accentBright)
                .frame(width: 34)
            Text(label)
                .font(Theme.display(14, .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            Text(value)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
    }

    // MARK: Navigation

    /// Barre du haut : retour et progression. La progression vit ici, loin du bouton :
    /// collée au-dessus de lui, elle se lisait comme une partie du bouton.
    private var topBar: some View {
        HStack(spacing: 14) {
            backButton
            progress
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    /// Marche arrière. Un parcours d'entrée sans retour est une impasse : une faute de
    /// frappe dans le pseudo obligeait à désinstaller l'app pour la corriger.
    /// Absent de la première étape : la place reste réservée pour que la barre de
    /// progression ne saute pas d'un écran à l'autre.
    private var backButton: some View {
        Button { back() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Theme.surface))
                .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .opacity(step == .demo ? 0 : 1)
        .disabled(step == .demo)
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? Theme.accent : Theme.textMuted.opacity(0.25))
                    .frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    /// Avant la prise de démonstration, c'est le déclencheur qui doit attirer le doigt :
    /// le bouton du bas est là mais invisible, pour que la scène ne change pas de hauteur
    /// au moment où il apparaît.
    private var actionVisible: Bool {
        !(step == .demo && demoPhase != .caught)
    }

    private var actionTitle: LocalizedStringKey {
        switch step {
        case .demo:  return developed ? "onboarding.next" : "onboarding.develop.action"
        case .ready: return "onboarding.start"
        // La sortie reste claire : sans compte, on avance quand même.
        case .account: return appleLinked ? "onboarding.next" : "onboarding.account.later"
        default:     return "onboarding.next"
        }
    }

    /// Sur l'étape compte, l'action principale est le bouton Apple : « Plus tard » prend
    /// un style discret pour ne pas lui disputer le regard.
    private var actionIsQuiet: Bool {
        step == .account && !appleLinked
    }

    private var action: some View {
        Button { next() } label: {
            Text(actionTitle)
                .font(Theme.label(13)).tracking(1.4)
                .foregroundStyle(actionIsQuiet ? Theme.textSecondary : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background {
                    if actionIsQuiet {
                        Capsule().fill(Theme.surface)
                            .overlay(Capsule().strokeBorder(Theme.strokeStrong, lineWidth: 1))
                    } else {
                        Capsule().fill(Theme.accentGradient)
                    }
                }
                .contentTransition(.opacity)
        }
        .buttonStyle(.plain)
        .opacity(actionVisible ? 1 : 0)
        .disabled(!actionVisible || developing)
        .animation(.easeOut(duration: 0.25), value: actionVisible)
    }

    /// Quitte l'étape courante. Sur la prise de démonstration, le bouton fait d'abord
    /// passer la carte en studio : sans ça, le joueur pressé sautait le seul moment qui
    /// montre ce que devient une photo. Le code d'invitation est enregistré au départ :
    /// un champ laissé vide ou incomplet n'empêche jamais d'avancer.
    private func next() {
        typing = false
        switch step {
        case .demo where !developed:
            develop()
        case .ready:
            referral.apply(referralCode)
            finish()
        default:
            advance()
        }
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { step = next }
        Analytics.track(.onboardingStep, ["step": "\(next)"])
    }

    private func back() {
        typing = false
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { step = previous }
    }

    private func finish() {
        @Bindable var state = app
        // Le pays est déjà résolu à l'étape du repérage. Si la position tarde encore,
        // elle arrivera par le même chemin et corrigera le pays toute seule : on
        // n'immobilise pas le joueur devant un écran d'attente.
        state.hasOnboarded = true
        Analytics.track(.onboardingCompleted)
    }
}

/// Le visuel de l'écran de localisation : un repère au centre d'ondes concentriques, qui
/// émet tant que la position est recherchée. Il donne une forme à un choix abstrait
/// (« automatique » ou « je choisis ») et occupe le haut de l'écran avec intention.
private struct LocationBeacon: View {
    let icon: String
    let searching: Bool
    @State private var pulse = false

    /// Écrit à la main : avec un `@State` privé, l'initialiseur implicite peut devenir
    /// privé lui aussi, et l'écran qui l'utilise ne pourrait plus l'appeler.
    init(icon: String, searching: Bool) {
        self.icon = icon
        self.searching = searching
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                // Anneaux en filets blancs ; le disque central garde seul le violet.
                ForEach(0..<3, id: \.self) { ring in
                    Circle()
                        .stroke(Theme.highlight.opacity(0.16 - Double(ring) * 0.04), lineWidth: 1)
                        .frame(width: side * (0.46 + CGFloat(ring) * 0.27),
                               height: side * (0.46 + CGFloat(ring) * 0.27))
                }
                // L'onde qui part du centre : plus rapide pendant la recherche, pour que
                // l'attente se voie sans qu'il faille lire la ligne d'état.
                Circle()
                    .stroke(Theme.highlight.opacity(0.5), lineWidth: 1.5)
                    .frame(width: side, height: side)
                    .scaleEffect(pulse ? 1 : 0.3)
                    .opacity(pulse ? 0 : (searching ? 0.9 : 0.5))
                Circle()
                    .fill(Theme.accentGradient)
                    .frame(width: side * 0.3, height: side * 0.3)
                Image(systemName: icon)
                    .font(.system(size: side * 0.12, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: searching ? 1.4 : 2.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}
