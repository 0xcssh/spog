import StoreKit
import Observation

/// Abonnement, via StoreKit 2.
///
/// L'essai gratuit de 3 jours est une *Introductory Offer* gérée par Apple et liée
/// à l'Apple ID : on ne réinvente surtout pas cette logique côté app, sinon un même
/// utilisateur pourrait enchaîner les essais.
@Observable
final class SubscriptionStore {

    static let monthlyID = "com.mandaloregroup.spog.premium.monthly"
    static let yearlyID  = "com.mandaloregroup.spog.premium.yearly"
    static let productIDs = [monthlyID, yearlyID]
    /// Prises offertes avant que le paywall se présente. Cinq : assez pour avoir vu
    /// plusieurs cartes et compris le jeu, trop peu pour se faire une collection.
    static let freeScans = 5

    private(set) var monthly: Product?
    private(set) var yearly: Product?
    /// Formule mise en avant. L'annuelle par defaut : c'est la plus interessante
    /// pour le joueur comme pour nous, autant la proposer d'emblee.
    var selected: Plan = .yearly

    enum Plan { case monthly, yearly }
    private(set) var isSubscribed = false
    /// Transaction active, telle qu'Apple l'a signée. Envoyée au serveur, qui la vérifie
    /// lui-même : c'est lui qui décide si un scan est payé, pas l'app.
    private(set) var entitlementJWS: String?
    private(set) var isWorking = false
    private(set) var lastError: String?

    /// Droit aux prises illimitees. C'est cette propriete que l'app interroge,
    /// jamais `isSubscribed` directement : elle seule connait le contournement de test.
    var hasAccess: Bool {
#if DEBUG
        isSubscribed || debugBypass
#else
        isSubscribed
#endif
    }

#if DEBUG
    /// TEMP — contournement du paywall, **uniquement en build de developpement**.
    /// Il ne peut pas partir sur l'App Store par megarde : ce code n'existe pas
    /// en Release, contrairement a un simple drapeau qu'on oublierait d'enlever.
    /// Persiste, sinon il faudrait le reactiver a chaque lancement.
    private static let bypassKey = "debug.paywallBypass"
    private(set) var debugBypass = false

    func enableDebugBypass() {
        debugBypass = true
        UserDefaults.standard.set(true, forKey: Self.bypassKey)
    }

    func clearDebugBypass() {
        debugBypass = false
        UserDefaults.standard.set(false, forKey: Self.bypassKey)
    }
#endif

    private var updatesTask: Task<Void, Never>?

    init() {
#if DEBUG
        debugBypass = UserDefaults.standard.bool(forKey: Self.bypassKey)
#endif
        // Les transactions peuvent arriver hors achat : renouvellement, remboursement,
        // achat fait sur un autre appareil. Il faut écouter en permanence.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
        Task { await load() }
    }

    deinit { updatesTask?.cancel() }

    func load() async {
        let products = (try? await Product.products(for: Self.productIDs)) ?? []
        monthly = products.first { $0.id == Self.monthlyID }
        yearly  = products.first { $0.id == Self.yearlyID }
        await refresh()
    }

    /// Produit correspondant a la formule choisie.
    var product: Product? { selected == .yearly ? yearly : monthly }

    /// Vérifie les droits en cours auprès de StoreKit.
    func refresh() async {
        var active = false
        var jws: String?
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  Self.productIDs.contains(transaction.productID) else { continue }
            if transaction.revocationDate == nil {
                active = true
                jws = entitlement.jwsRepresentation
            }
        }
        let value = active, signed = jws
        await MainActor.run { isSubscribed = value; entitlementJWS = signed }
    }

    @discardableResult
    func purchase() async -> Bool {
        guard let product else { return false }
        await MainActor.run { isWorking = true; lastError = nil }
        defer { Task { @MainActor in isWorking = false } }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refresh()
                    return true
                }
                await MainActor.run { lastError = String(localized: "paywall.error.unverified") }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            await MainActor.run { lastError = String(localized: "paywall.error.failed") }
        }
        return false
    }

    func restore() async {
        await MainActor.run { isWorking = true }
        defer { Task { @MainActor in isWorking = false } }
        try? await AppStore.sync()
        await refresh()
    }

    // MARK: Affichage

    /// Prix formate par StoreKit, donc deja dans la devise et le format du pays.
    var priceText: String { product?.displayPrice ?? "—" }

    /// Prix ramene au mois pour l'annuel : c'est la seule comparaison honnete
    /// entre deux formules de durees differentes.
    func monthlyEquivalent(for product: Product) -> String? {
        guard product.subscription?.subscriptionPeriod.unit == .year else { return nil }
        let perMonth = product.price / 12
        return perMonth.formatted(product.priceFormatStyle)
    }

    /// Economie de l'annuel face au mensuel, en pourcentage entier.
    var yearlySaving: Int? {
        guard let monthly, let yearly else { return nil }
        let twelveMonths = monthly.price * 12
        guard twelveMonths > 0 else { return nil }
        let ratio = (twelveMonths - yearly.price) / twelveMonths
        let percent = Int((ratio as NSDecimalNumber).doubleValue * 100)
        return percent > 0 ? percent : nil
    }

    /// Duree de l'essai gratuit, telle qu'Apple la declare.
    var trialDays: Int? {
        guard let offer = product?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let period = offer.period
        switch period.unit {
        case .day:   return period.value
        case .week:  return period.value * 7
        case .month: return period.value * 30
        case .year:  return period.value * 365
        @unknown default: return nil
        }
    }
}
