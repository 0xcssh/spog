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
    @State private var tab: Tab = .garage

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
        // Prises restées en attente, puis l'état du joueur : au lancement, et à chaque
        // nouvelle prise (le classement bouge).
        .task(id: garage.catches.count) {
            await garage.syncPending()
            await account.refresh()
        }
        // Lien d'invitation `spog://invite/XXXXXX`. Le code est seulement **proposé** :
        // on n'accepte pas un parrainage à la place du joueur, un lien s'ouvre par accident.
        .onOpenURL { url in
            if let code = ReferralStore.code(from: url) { referral.pendingFromLink = code }
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
            Theme.background.ignoresSafeArea()
            Theme.glow
                .frame(height: 420)
                .frame(maxHeight: .infinity, alignment: .top)
                .offset(y: -140)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Group {
                    switch tab {
                    case .garage:  GarageView(onScan: { tab = .scan })
                    case .scan:    ScannerView()
                    case .social:   SocialView()
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

    /// Barre a icones : seul l'onglet actif affiche son libelle.
    private var tabBar: some View {
        HStack(spacing: 3) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { tab = item }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.icon).font(.system(size: 13, weight: .semibold))
                        if tab == item {
                            Text(item.key).font(Theme.label(11)).tracking(1)
                        }
                    }
                    .foregroundStyle(tab == item ? Theme.background : Theme.textSecondary)
                    .padding(.horizontal, tab == item ? 15 : 13)
                    .padding(.vertical, 11)
                    .background {
                        if tab == item {
                            Capsule().fill(
                                LinearGradient(colors: [Theme.accentBright, Theme.accent],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.strokeStrong, lineWidth: 1))
        .padding(.bottom, 6)
    }
}
