import SwiftUI

struct RootView: View {
    @State private var app = AppState()
    @State private var garage: GarageStore
    @State private var progress = ProgressStore()
    @State private var subscriptions = SubscriptionStore()
    @State private var profile = PlayerProfile()
    /// Une seule instance pour toute l'app : l'onboarding, les réglages et le scan
    /// parlent à la même position, et l'autorisation n'est demandée qu'une fois.
    @State private var location = LocationProvider()
    @State private var referral = ReferralStore()
    @State private var training = TrainingConsent()
    @State private var account = AccountStore()
    @State private var bounty = BountyStore()
    @State private var duels = DuelStore()
    @State private var tab: Tab = .garage
    /// La pastille de l'onglet actif glisse d'un onglet à l'autre au lieu d'apparaître.
    @Namespace private var tabPill

    init() {
        let state = AppState()
        _app = State(initialValue: state)
        _garage = State(initialValue: GarageStore(demoCountry: state.country))
    }

    /// Hauteur reservee sous le contenu pour la barre flottante.
    static let tabBarHeight: CGFloat = 76

    enum Tab: String, CaseIterable {
        case garage, scan, social, quests

        var icon: String {
            switch self {
            case .garage:  return "square.grid.2x2.fill"
            case .scan:    return "viewfinder"
            case .social:   return "person.2.fill"
            case .quests:   return "trophy.fill"
            }
        }
        var key: LocalizedStringKey {
            switch self {
            case .garage:  return "tab.garage"
            case .scan:    return "tab.scan"
            case .social:   return "tab.social"
            case .quests:   return "tab.quests"
            }
        }
    }

    var body: some View {
        Group {
            if app.hasOnboarded {
                main
            } else {
                OnboardingView()
            }
        }
        .environment(app)
        .environment(location)
        .environment(referral)
        .environment(garage)
        .environment(progress)
        .environment(subscriptions)
        .environment(profile)
        .environment(training)
        .environment(account)
        .environment(bounty)
        .environment(duels)
        // Prises restées en attente, puis l'état du joueur : au lancement, et à chaque
        // nouvelle prise (le classement bouge).
        .task(id: garage.catches.count) {
            await garage.syncPending()
            await account.refresh()
            // Le serveur connaît plus de cartes que l'appareil : réinstallation, ou cartes
            // faites sur un autre iPhone du même compte Apple. Les cartes ajoutées changent
            // `catches.count` et relancent cette tâche une fois ; ensuite les deux comptes
            // concordent et plus rien ne part.
            if let remote = account.profile?.catches, remote > garage.catches.count {
                await garage.restoreFromServer()
            }
        }
        // Juste après Sign in with Apple : sans attendre le prochain lancement, et même si
        // les comptes concordent (mêmes nombres, cartes différentes d'un appareil à l'autre).
        .task(id: account.appleLinks) {
            guard account.appleLinks > 0 else { return }
            await garage.restoreFromServer()
        }
        // Lien d'invitation `spog://invite/XXXXXX`. Le code est seulement **proposé** :
        // on n'accepte pas un parrainage à la place du joueur, un lien s'ouvre par accident.
        .onOpenURL { url in
            if let code = ReferralStore.code(from: url) { referral.pendingFromLink = code }
            // Défi reçu `spog://duel/XXXXXX` : l'onglet Social s'ouvre et propose de le
            // rejoindre, sans le faire à la place du joueur.
            if let code = DuelStore.code(from: url) {
                duels.pendingFromLink = code
                tab = .social
            }
        }
        .preferredColorScheme(.dark)
        // Les teintes sont calculées hors du fil principal : sinon la première ouverture
        // du garage repeint quatorze voitures d'un coup, et ça se voit.
        .task(id: garage.catches.count) {
            await CarArt.warm(garage.catches.map { ($0.vehicleID, $0.paint) })
        }
    }

    private var main: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                Group {
                    switch tab {
                    case .garage:  GarageView(onScan: { tab = .scan })
                    case .scan:    ScannerView()
                    case .social:   SocialView(onScan: { tab = .scan }, onOpenGarage: { tab = .garage })
                    case .quests:   QuestsView()
                    }
                }
                .frame(maxHeight: .infinity)
                .padding(.top, 10)
                .padding(.bottom, Self.tabBarHeight)
            }

            VStack {
                Spacer()
                tabBar
            }
        }
        .environment(app)
        .environment(location)
        .environment(referral)
        .environment(garage)
        .environment(progress)
        .preferredColorScheme(.dark)
    }

    /// Barre d'onglets : une capsule de verre pour la navigation, et à côté, détaché, le
    /// déclencheur du scan. Le scan est le geste du jeu ; noyé parmi trois onglets de même
    /// taille, il ne se distinguait pas d'un écran de réglages.
    private var tabBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(Tab.allCases.filter { $0 != .scan }, id: \.self) { item in
                    tabButton(item)
                }
            }
            .padding(5)
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Theme.surface).opacity(0.75)
                }
            }
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            .shadow(color: Theme.dropShadow, radius: 10, y: 4)

            scanButton
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .sensoryFeedback(.selection, trigger: tab)
    }

    private func tabButton(_ item: Tab) -> some View {
        let active = tab == item
        return Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) { tab = item }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.icon).font(.system(size: 14, weight: .semibold))
                if active {
                    Text(item.key)
                        .font(Theme.label(11)).tracking(1)
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            // L'onglet actif prend un gris clair et non plus le violet : le violet reste
            // au déclencheur du scan, seule action principale de la barre.
            .foregroundStyle(active ? Theme.textPrimary : Theme.textMuted)
            .frame(maxWidth: active ? nil : .infinity)
            .padding(.horizontal, active ? 16 : 10)
            .padding(.vertical, 12)
            .background {
                if active {
                    Capsule()
                        .fill(Theme.surfaceRaised)
                        .overlay(Capsule().strokeBorder(Theme.strokeStrong, lineWidth: 1))
                        .matchedGeometryEffect(id: "pill", in: tabPill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var scanButton: some View {
        let active = tab == .scan
        return Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) { tab = .scan }
        } label: {
            ZStack {
                Circle()
                    .fill(Theme.accentGradient)
                    .shadow(color: Theme.dropShadow, radius: 8, y: 4)
                Circle()
                    .strokeBorder(Theme.highlight.opacity(active ? 0.55 : 0.12), lineWidth: active ? 2 : 1)
                Image(systemName: Tab.scan.icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 60, height: 60)
            .accessibilityLabel(Text(Tab.scan.key))
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
    }
}
