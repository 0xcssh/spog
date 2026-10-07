import SwiftUI

/// Parcours d'entrée. Sept étapes, dont deux qui posent une question au joueur.
/// Règle tenue : **on ne demande rien qui ne serve nulle part.** Le pseudo apparaît
/// au classement, la carrosserie préférée oriente la quête du jour.
struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerProfile.self) private var profile

    @Environment(LocationProvider.self) private var location
    @Environment(ReferralStore.self) private var referral

    @State private var step: Step = .welcome
    @State private var pickingCountry = false
    /// Position refusée : il faut le dire, sinon le repli en mode manuel est inexplicable.
    @State private var locationRefused = false
    /// Code d'invitation en cours de saisie. Vide = le joueur n'en a pas, c'est permis.
    @State private var referralCode = ""
    @FocusState private var typing: Bool

    private let store = CatalogStore.shared
    /// Hauteur disponible pour le contenu, mesuree une fois.
    @State private var contentHeight: CGFloat = 0

    enum Step: Int, CaseIterable {
        case welcome, nickname, taste, how, market, referral, preparing, recap
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Theme.glow
                .frame(height: 460)
                .frame(maxHeight: .infinity, alignment: .top)
                .offset(y: -120)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // `safeAreaInset` est la seule construction qui repousse reellement les
            // commandes au-dessus du clavier. Un simple VStack les laisse dessous.
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 10)
                    Group {
                        switch step {
                        case .welcome:   welcome
                        case .nickname:  nicknameStep
                        case .taste:     tasteStep
                        case .how:       howItWorks
                        case .market:    market
                        case .referral:  referralStep
                        case .preparing: preparing
                        case .recap:     recap
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: 10)
                }
                .frame(minHeight: contentHeight)
                .padding(.horizontal, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                // Pendant la saisie, la barre du clavier porte l'action :
                // afficher les deux ferait doublon.
                if step != .preparing && !typing {
                    VStack(spacing: 0) {
                        dots
                        action
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
                    .background(.ultraThinMaterial)
                }
            }
        }
        .overlay(alignment: .topLeading) { backButton }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $pickingCountry) { MarketPickerSheet() }
        .background {
            GeometryReader { geo in
                Color.clear.onAppear { contentHeight = geo.size.height * 0.72 }
            }
        }
    }

    // MARK: 1 — Bienvenue

    private var welcome: some View {
        VStack(spacing: 20) {
            Image("LogoMark")
                .resizable()
                .frame(width: 118, height: 118)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .neonBorder(color: Theme.accent, radius: 30, intensity: 0.8, breathing: true)

            Text(verbatim: "SPOG")
                .font(Theme.display(30, .heavy)).tracking(8)
                .foregroundStyle(Theme.textPrimary)

            Text("onboarding.tagline")
                .font(Theme.mono(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }

    // MARK: 2 — Pseudo

    private var nicknameStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            @Bindable var player = profile
            Text("onboarding.nickname.title")
                .font(Theme.display(26))
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
        // Sur un petit ecran le clavier recouvre le bas de l'ecran : l'action
        // doit exister au-dessus de lui, sinon l'utilisateur est bloque.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { next() } label: {
                    Text("onboarding.next")
                        .font(Theme.label(13)).tracking(1)
                        .foregroundStyle(Theme.accentBright)
                }
            }
        }
    }

    // MARK: 3 — Goûts

    private var tasteStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("onboarding.taste.title")
                .font(Theme.display(26))
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

    // MARK: 4 — Le principe

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("onboarding.how.title")
                .font(Theme.display(26))
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, 4)
            principle(icon: "eye.fill", title: "onboarding.spot.title", body: "onboarding.spot.body")
            principle(icon: "viewfinder", title: "onboarding.snap.title", body: "onboarding.snap.body")
            principle(icon: "square.grid.2x2.fill", title: "onboarding.collect.title",
                      body: "onboarding.collect.body")

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

    // MARK: 5 — Pays et mode

    private var market: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("onboarding.market.title")
                .font(Theme.display(24))
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

    // MARK: 6 — Code d'invitation

    /// Derniere question, et la seule qu'on peut laisser vide sans rien perdre.
    /// Elle est posee ici plutot qu'au premier ecran : demander un code a quelqu'un
    /// qui ne sait pas encore ce qu'est l'app n'a aucun sens.
    private var referralStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("onboarding.referral.title")
                .font(Theme.display(26))
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { next() } label: {
                    Text("onboarding.next")
                        .font(Theme.label(13)).tracking(1)
                        .foregroundStyle(Theme.accentBright)
                }
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

    // MARK: 7 — Preparation

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

    // MARK: 7 — Récapitulatif

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
                             "\(SubscriptionStore.freeScans)")
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

    /// Marche arrière. Un parcours d'entrée sans retour est une impasse : une faute de
    /// frappe dans le pseudo obligeait à désinstaller l'app pour la corriger.
    /// Absent de la première étape, et de la préparation qui n'attend aucune réponse.
    @ViewBuilder private var backButton: some View {
        if step != .welcome && step != .preparing {
            Button { back() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.surface))
                    .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.leading, 20)
            .padding(.top, 4)
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases.filter { $0 != .preparing }, id: \.self) { item in
                Capsule()
                    .fill(item == step ? Theme.accent : Theme.textMuted.opacity(0.3))
                    .frame(width: item == step ? 18 : 6, height: 6)
            }
        }
        .padding(.bottom, 16)
    }

    private var action: some View {
        Button { next() } label: {
            Text(step == .recap ? "onboarding.start" : "onboarding.next")
                .font(Theme.label(13)).tracking(1.4)
                .foregroundStyle(Theme.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [Theme.accentBright, Theme.accent],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Capsule())
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
        let previous = step == .recap ? .market : Step(rawValue: step.rawValue - 1)
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
