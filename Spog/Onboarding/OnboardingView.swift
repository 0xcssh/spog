import SwiftUI

/// Parcours d'entrée.
///
/// **On joue avant de répondre.** Les quatre premiers écrans ne demandent rien : une prise
/// de démonstration, son développement, le jeu, le modèle gratuit. Un joueur à qui l'on
/// demande un pseudo avant de lui avoir montré ce que fait l'app n'a aucune raison d'en
/// donner un. Les questions viennent ensuite.
///
/// Règle tenue : **on ne demande rien qui ne serve nulle part.** Le pseudo apparaît
/// au classement, la carrosserie préférée oriente la quête du jour, le pays et son mode
/// décident de la rareté et de la vérification des prises.
struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerProfile.self) private var profile

    @Environment(LocationProvider.self) private var location
    @Environment(ReferralStore.self) private var referral

    @State private var step: Step = .demo
    @State private var pickingCountry = false
    /// Position refusée : il faut le dire, sinon le repli en mode manuel est inexplicable.
    @State private var locationRefused = false
    /// Code d'invitation en cours de saisie. Vide = le joueur n'en a pas, c'est permis.
    @State private var referralCode = ""
    @FocusState private var typing: Bool

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

    enum Step: Int, CaseIterable {
        case demo, develop, game, freePlan, nickname, taste, market, referral, preparing, recap
    }

    var body: some View {
        ZStack {
            backdrop

            ScrollView {
                Group {
                    switch step {
                    case .demo:      demoStep
                    case .develop:   developStep
                    case .game:      gameStep
                    case .freePlan:  freePlanStep
                    case .nickname:  nicknameStep
                    case .taste:     tasteStep
                    case .market:    market
                    case .referral:  referralStep
                    case .preparing: preparing
                    case .recap:     recap
                    }
                }
                // Chaque étape entre par la droite et l'ancienne s'efface : sans `id`,
                // SwiftUI recycle la vue et l'écran change d'un bloc, sans transition.
                .id(step)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 28)),
                                        removal: .opacity))
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top) { topBar }
            // `safeAreaInset` est la seule construction qui repousse reellement les
            // commandes au-dessus du clavier. Un simple VStack les laisse dessous. Le
            // bouton reste donc le même pendant la saisie : un second bouton accroché
            // à la barre du clavier faisait doublon et flottait à droite, bricolé.
            .safeAreaInset(edge: .bottom) {
                if showsActionBar {
                    action
                        .padding(.horizontal, 24)
                        .padding(.top, 22)
                        .padding(.bottom, 10)
                        .background(alignment: .top) { footerFade }
                        .transition(.opacity)
                }
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
        }
    }

    /// Fond de tout le parcours : noir profond, une lueur violette en haut, une autre,
    /// plus sourde, en bas. Deux sources donnent de la profondeur ; une seule laissait le
    /// bas de l'écran en aplat noir.
    private var backdrop: some View {
        ZStack {
            Theme.background
            DotGrid(spacing: 22)
                .opacity(0.6)
            Theme.glow
                .frame(height: 520)
                .frame(maxHeight: .infinity, alignment: .top)
                .offset(y: -150)
            RadialGradient(colors: [Theme.accentDeep.opacity(0.28), .clear],
                           center: .bottom, startRadius: 4, endRadius: 360)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
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

    // MARK: 1 — Prise de démonstration

    /// L'accroche est une prise, pas un discours : une voiture est déjà dans le viseur,
    /// il reste à appuyer. Aucune caméra, aucune autorisation — on les demanderait à
    /// quelqu'un qui ne sait pas encore pourquoi.
    private var demoStep: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                Image("LogoMark")
                    .resizable()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(verbatim: "SPOG")
                    .font(Theme.display(17, .heavy)).tracking(5)
                    .foregroundStyle(Theme.textPrimary)
            }

            VStack(spacing: 6) {
                Text(demoPhase == .caught ? "onboarding.demo.caught" : "onboarding.demo.title")
                    .font(Theme.display(30))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("onboarding.tagline")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            ZStack {
                if demoPhase == .caught, let demo {
                    VStack(spacing: 12) {
                        CollectibleCardView(card: demoCard(demo), showsShotToggle: false)
                            .frame(maxWidth: 230)
                        Overline(text: "onboarding.demo.caughtTier \(tierName(demo.tier)) \(store.countryName(app.country))",
                                 color: demo.tier.color)
                    }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    VStack(spacing: 18) {
                        demoViewfinder
                        demoShutter
                    }
                    .transition(.opacity)
                }
            }

            Text("onboarding.demo.note")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .opacity(demoPhase == .caught ? 1 : 0)
        }
    }

    private var demoViewfinder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surface)
                .overlay(DotGrid(spacing: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)))

            if let raw = demo?.raw {
                // Le `Color.clear` fixe la taille : une image en remplissage imposerait
                // la sienne et pousserait le déclencheur hors de l'écran.
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
                    .fill(LinearGradient(colors: [.clear, Theme.accentBright, .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 2)
                    .shadow(color: Theme.accentBright, radius: 8)
                    .offset(y: scanSweep ? 110 : -110)
            }

            CornerBrackets(color: demoPhase == .scanning ? Theme.accentBright : Theme.accent)
                .padding(18)

            // L'éclair du déclenchement : sans lui, rien ne dit que la photo est prise.
            Theme.textPrimary
                .opacity(flash ? 0.8 : 0)
                .allowsHitTesting(false)
        }
        .aspectRatio(0.95, contentMode: .fit)
        .frame(maxWidth: 320)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.accent.opacity(0.4), lineWidth: 1))
        .shadow(color: Theme.accent.opacity(0.3), radius: 20)
    }

    private var demoShutter: some View {
        VStack(spacing: 10) {
            Button { shootDemo() } label: {
                ZStack {
                    Circle()
                        .stroke(Theme.accent.opacity(0.5), lineWidth: 2)
                        .frame(width: 90, height: 90)
                    Circle()
                        .fill(LinearGradient(colors: [Theme.accentBright, Theme.accent],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 76, height: 76)
                        .shadow(color: Theme.accent.opacity(0.7), radius: 18)
                    Image(systemName: "viewfinder")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Theme.background)
                }
                .opacity(demoPhase == .aiming ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .disabled(demoPhase != .aiming)
            .accessibilityLabel(Text("onboarding.demo.shutter"))

            Overline(text: demoPhase == .scanning ? "scan.working" : "onboarding.demo.hint",
                     color: demoPhase == .scanning ? Theme.accentBright : Theme.textMuted)
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

    private func demoCard(_ demo: OnboardingDemo) -> CardData {
        demo.card(developed: developed, place: store.countryName(app.country))
    }

    private func tierName(_ tier: RarityTier) -> String {
        String(localized: String.LocalizationValue(tier.key))
    }

    // MARK: 2 — Développement

    /// Le développement se touche du doigt plutôt que de s'expliquer : la même carte,
    /// d'abord le cliché terne, puis le rendu studio.
    private var developStep: some View {
        VStack(spacing: 18) {
            Text(developed ? "onboarding.develop.done" : "onboarding.develop.title")
                .font(Theme.display(30))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let demo {
                CollectibleCardView(card: demoCard(demo), interactive: developed,
                                    showsShotToggle: false)
                    .frame(maxWidth: 250)
                    .blur(radius: developing ? 5 : 0)
                    .brightness(developing ? 0.12 : 0)
                    .overlay { developLight }
                    .overlay {
                        // Par-dessus la carte, sinon sa propre zone d'image garderait le
                        // toucher pour elle et le développement ne partirait jamais.
                        if !developed {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { develop() }
                        }
                    }
            }

            if developed {
                Text("onboarding.develop.daily \(DailyAllowance.dailyDevelops)")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accentBright)
                    Text("onboarding.develop.hint")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8)
            }
        }
    }

    /// Bande de lumière qui balaie la carte pendant le développement.
    private var developLight: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, Theme.accentBright.opacity(0.75), .clear],
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

    // MARK: 3 — Le jeu

    private var gameStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Overline(text: "onboarding.game.overline", color: Theme.accentBright)
            Text("onboarding.game.title")
                .font(Theme.display(30))
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, 4)

            rarityContrast

            principle(icon: "trophy.fill", title: "onboarding.game.league.title",
                      body: "onboarding.game.league.body \(OnboardingRules.leagueSize) \(OnboardingRules.leaguePromote)")
            principle(icon: "scope", title: "onboarding.game.bounty.title",
                      body: "onboarding.game.bounty.body \(OnboardingRules.bountyTargets)")
            principle(icon: "flag.checkered", title: "onboarding.game.first.title",
                      body: "onboarding.game.first.body")
        }
    }

    /// La différence de Spog, montrée sur une vraie fiche du catalogue : le même modèle,
    /// deux pays, deux paliers.
    @ViewBuilder private var rarityContrast: some View {
        if let contrast = demo?.contrast {
            NeonFrame(radius: 16, neon: true, spread: 0.6) {
                VStack(alignment: .leading, spacing: 10) {
                    Overline(text: "onboarding.game.rarity.overline", color: Theme.accentBright)
                    Text("onboarding.game.rarity.title")
                        .font(Theme.display(17, .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    HStack(spacing: 12) {
                        if let art = CarArt.image(for: contrast.vehicle.id) {
                            Image(uiImage: art)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 92)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        Text(contrast.vehicle.fullName)
                            .font(Theme.mono(13, .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        tierChip(country: app.country, tier: contrast.here)
                        tierChip(country: contrast.elsewhereCountry, tier: contrast.elsewhere)
                    }

                    Text("onboarding.game.rarity.body")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
            }
        } else {
            principle(icon: "globe.europe.africa.fill", title: "onboarding.game.rarity.title",
                      body: "onboarding.game.rarity.body")
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

    // MARK: 4 — Le modèle gratuit

    /// Dit avant la première vraie photo, pas découvert au moment où le compteur tombe
    /// à zéro. Aucune promesse de publicité : elle n'existe pas encore dans l'app.
    private var freePlanStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Overline(text: "onboarding.free.overline", color: Theme.accentBright)
            Text("onboarding.free.title")
                .font(Theme.display(30))
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, 4)

            NeonFrame(radius: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(DailyAllowance.firstDayScans, format: .number)
                        .font(Theme.display(54, .heavy))
                        .foregroundStyle(Theme.accentBright)
                    Text("onboarding.free.today")
                        .font(Theme.display(16, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }

            principle(icon: "arrow.clockwise",
                      title: "onboarding.free.daily.title \(DailyAllowance.dailyScans)",
                      body: "onboarding.free.daily.body")
            principle(icon: "sparkles",
                      title: "onboarding.free.develop.title \(DailyAllowance.dailyDevelops)",
                      body: "onboarding.free.develop.body")
            principle(icon: "infinity", title: "onboarding.free.pro.title",
                      body: "onboarding.free.pro.body")

            // Sécurité routière : dit une fois, clairement, et tenu par le code —
            // le scan se bloque vraiment au-delà du seuil.
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RarityTier.trophyGold)
                Text("onboarding.safety \(ScannerView.maxScanSpeedText)")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    // MARK: 5 — Pseudo

    private var nicknameStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            @Bindable var player = profile
            Overline(text: "onboarding.profile.overline", color: Theme.accentBright)
            Text("onboarding.nickname.title")
                .font(Theme.display(30))
                .foregroundStyle(Theme.textPrimary)
            Text("onboarding.nickname.why")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(text: $player.nickname) {
                Text("onboarding.nickname.placeholder")
            }
            .focused($typing)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .onSubmit { next() }
            .font(Theme.display(19, .semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16).padding(.vertical, 16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(typing ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1))
            .padding(.top, 4)
            .onAppear { typing = true }
        }
    }

    // MARK: 6 — Goûts

    private var tasteStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Overline(text: "onboarding.profile.overline", color: Theme.accentBright)
            Text("onboarding.taste.title")
                .font(Theme.display(30))
                .foregroundStyle(Theme.textPrimary)
            Text("onboarding.taste.why")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("onboarding.taste.multi")
                .font(Theme.label(10)).tracking(0.8)
                .foregroundStyle(Theme.accent)

            // Plusieurs réponses : toucher n'enchaîne plus, sinon le premier choix
            // fermerait la question. C'est le bouton du bas qui avance.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 9),
                                GridItem(.flexible(), spacing: 9)], spacing: 9) {
                ForEach(PlayerProfile.choices, id: \.body) { choice in
                    tasteCard(choice.body, icon: choice.icon)
                }
            }
            .padding(.top, 4)
        }
    }

    private func tasteCard(_ body: String, icon: String) -> some View {
        let selected = profile.favouriteBodies.contains(body)
        return Button {
            @Bindable var player = profile
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                if selected { player.favouriteBodies.remove(body) }
                else        { player.favouriteBodies.insert(body) }
            }
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(selected ? Theme.accentBright : Theme.textSecondary)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.accentBright)
                            .offset(x: 16, y: -4)
                    }
                }
                Text(LocalizedStringKey("taste." + body))
                    .font(Theme.display(13, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(selected ? Theme.accent.opacity(0.12) : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Briques communes

    private func principle(icon: String, title: LocalizedStringKey,
                           body: LocalizedStringKey) -> some View {
        NeonFrame(radius: 16) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.accentBright)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.display(15, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(body)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }

    // MARK: 7 — Pays et mode

    private var market: some View {
        VStack(alignment: .leading, spacing: 13) {
            Overline(text: "onboarding.market.overline", color: Theme.accentBright)
            Text("onboarding.market.title")
                .font(Theme.display(30))
                .foregroundStyle(Theme.textPrimary)
            Text("onboarding.market.why")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)

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
    }

    /// Ce que la position donne, en direct. Sans ça le joueur choisit « automatique »,
    /// ne voit rien changer, et découvre au récapitulatif un pays qui n'est pas le sien.
    @ViewBuilder private var autoStatus: some View {
        if locationRefused {
            statusLine("exclamationmark.triangle.fill", "onboarding.location.denied",
                       color: RarityTier.trophyGold)
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

    /// Résout le pays **tout de suite**, pas au moment de terminer : le récapitulatif
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
                        .font(Theme.display(14, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(body)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(selected ? Theme.accent : Theme.textMuted)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: 8 — Code d'invitation

    /// Derniere question, et la seule qu'on peut laisser vide sans rien perdre.
    /// Elle est posee ici plutot qu'au premier ecran : demander un code a quelqu'un
    /// qui ne sait pas encore ce qu'est l'app n'a aucun sens.
    private var referralStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Overline(text: "onboarding.profile.overline", color: Theme.accentBright)
            Text("onboarding.referral.title")
                .font(Theme.display(30))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("onboarding.referral.why")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("onboarding.referral.optional")
                .font(Theme.label(10)).tracking(0.8)
                .foregroundStyle(Theme.accent)

            TextField(text: $referralCode) {
                Text("referral.placeholder")
            }
            .focused($typing)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit { next() }
            .font(Theme.mono(22, .bold))
            .tracking(6)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16).padding(.vertical, 16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(typing ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1))
            // Le code est remis en forme pendant la frappe : minuscules, tirets et
            // confusions O/0 ou I/1 corriges a la volee plutot que refuses a l'envoi.
            .onChange(of: referralCode) { _, typed in
                let cleaned = ReferralStore.normalize(typed)
                if cleaned != typed { referralCode = cleaned }
            }

            referralFeedback
        }
        .onAppear {
            // Code recu par un lien : on le propose deja rempli, jamais applique en douce.
            if referralCode.isEmpty, let pending = referral.pendingFromLink {
                referralCode = pending
            }
        }
    }

    /// Reponse pendant la frappe. Un message d'erreur decouvert apres coup arrive trop tard.
    @ViewBuilder private var referralFeedback: some View {
        switch referral.check(referralCode) {
        case .ready:
            statusLine("checkmark.circle.fill", "referral.valid", color: Theme.accent)
        case .ownCode:
            statusLine("exclamationmark.triangle.fill", "referral.ownCode",
                       color: RarityTier.trophyGold)
        case .tooShort:
            statusLine("ellipsis.circle", "referral.tooShort", color: Theme.textMuted)
        case .empty:
            EmptyView()
        }
    }

    // MARK: 9 — Préparation

    @State private var readySteps = 0

    private var preparing: some View {
        VStack(spacing: 24) {
            Image("LogoMark")
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .neonBorder(color: Theme.accent, radius: 24, intensity: 0.9, breathing: true)

            Text("onboarding.preparing.title")
                .font(Theme.display(22))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 11) {
                readyLine(0, "onboarding.preparing.catalog")
                readyLine(1, "onboarding.preparing.market")
                readyLine(2, "onboarding.preparing.quest")
                readyLine(3, "onboarding.preparing.garage")
            }
        }
        .task {
            // Une attente courte et honnête : chaque ligne correspond à une préparation réelle.
            for index in 0..<4 {
                try? await Task.sleep(for: .milliseconds(index == 0 ? 400 : 520))
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { readySteps = index + 1 }
            }
            try? await Task.sleep(for: .milliseconds(420))
            advance()
        }
    }

    private func readyLine(_ index: Int, _ text: LocalizedStringKey) -> some View {
        let done = readySteps > index
        return HStack(spacing: 11) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(done ? Theme.accent : Theme.textMuted.opacity(0.4))
            Text(text)
                .font(Theme.mono(12))
                .foregroundStyle(done ? Theme.textPrimary : Theme.textMuted)
            Spacer(minLength: 0)
        }
        .opacity(done ? 1 : 0.5)
    }

    // MARK: 10 — Récapitulatif

    private var recap: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("onboarding.recap.title \(profile.displayName)")
                .font(Theme.display(26))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            NeonFrame(radius: 16) {
                VStack(spacing: 0) {
                    recapRow("mappin", "onboarding.recap.place", placeText)
                    Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 46)
                    recapRow(app.locationMode == .automatic ? "location.fill" : "hand.tap.fill",
                             "onboarding.recap.mode",
                             String(localized: app.locationMode == .automatic
                                    ? "onboarding.auto.title" : "onboarding.manual.title"))
                    if !profile.favouriteBodies.isEmpty {
                        Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 46)
                        recapRow("heart.fill", "onboarding.recap.taste", favouritesText)
                    }
                    if let code = referral.enteredCode {
                        Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 46)
                        recapRow("person.2.fill", "onboarding.recap.referral", code)
                    }
                    Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 46)
                    recapRow("gift.fill", "onboarding.recap.free",
                             String(localized: "onboarding.recap.freeValue \(DailyAllowance.firstDayScans) \(DailyAllowance.dailyScans)"))
                }
            }

            Text("onboarding.recap.editable")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, 4)
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
                .frame(width: 22)
            Text(label)
                .font(Theme.display(14, .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            Text(value)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
    }

    // MARK: Navigation

    /// Barre du haut : retour et progression. La progression vit ici, loin du bouton :
    /// collée au-dessus de lui, elle se lisait comme une partie du bouton.
    @ViewBuilder private var topBar: some View {
        if step != .preparing {
            HStack(spacing: 14) {
                backButton
                progress
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
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

    private var progressSteps: [Step] { Step.allCases.filter { $0 != .preparing } }

    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(progressSteps, id: \.self) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? Theme.accent : Theme.textMuted.opacity(0.25))
                    .frame(height: 4)
                    .shadow(color: item == step ? Theme.accent.opacity(0.8) : .clear, radius: 5)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Le bouton du bas disparaît là où une autre action le remplace : avant la prise de
    /// démonstration, c'est le déclencheur qui doit attirer le doigt, et la préparation
    /// n'attend aucune réponse.
    private var showsActionBar: Bool {
        if step == .preparing { return false }
        if step == .demo && demoPhase != .caught { return false }
        return true
    }

    private var action: some View {
        Button { next() } label: {
            Text(step == .recap ? "onboarding.start" : "onboarding.next")
                .font(Theme.label(13)).tracking(1.4)
                .foregroundStyle(Theme.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(colors: [Theme.accentBright, Theme.accent],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Capsule())
                .shadow(color: Theme.accent.opacity(0.45), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
    }

    /// Quitte l'etape courante. Le code d'invitation est enregistre ici, au moment de
    /// passer a la suite : un champ laisse vide ou incomplet n'empeche jamais d'avancer.
    private func next() {
        typing = false
        if step == .referral { referral.apply(referralCode) }
        if step == .recap { finish() } else { advance() }
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { step = next }
        Analytics.track(.onboardingStep, ["step": "\(next)"])
    }

    private func back() {
        typing = false
        // La préparation ne se rejoue pas : depuis le récapitulatif, on remonte
        // directement à la dernière vraie question.
        let previous = step == .recap ? .referral : Step(rawValue: step.rawValue - 1)
        guard let previous else { return }
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
