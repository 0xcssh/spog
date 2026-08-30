import Testing
@testable import Spog

/// Le décompte des prises offertes : la frontière entre le gratuit et le payant.
///
/// Une erreur d'un cran ici se paie deux fois. Trop généreuse, elle offre des appels
/// facturés à l'infini. Trop stricte, elle présente le paywall à un joueur qui n'a pas
/// encore vu une seule carte — et celui-là ne revient pas.
struct ScanAllowanceTests {

    @Test("Un nouveau joueur a exactement les prises annoncées")
    func newPlayerGetsAllFreeScans() {
        // Le nombre montré dans l'onboarding et sur le paywall vient de la même
        // constante : promettre cinq prises et en donner quatre serait un mensonge.
        #expect(ScanAllowance.remaining(performed: 0, hasAccess: false)
                == SubscriptionStore.freeScans)
    }

    @Test("Chaque prise en retire une")
    func eachScanCountsDown() {
        #expect(ScanAllowance.remaining(performed: 1, hasAccess: false, free: 5) == 4)
        #expect(ScanAllowance.remaining(performed: 4, hasAccess: false, free: 5) == 1)
    }

    @Test("La cinquième prise est offerte, la sixième non")
    func theLastFreeScanIsAllowed() {
        // Le cas d'un cran d'écart : après quatre prises il en reste une, et elle doit
        // partir. Le paywall n'arrive qu'une fois les cinq consommées.
        #expect(ScanAllowance.mustPay(performed: 4, hasAccess: false, free: 5) == false)
        #expect(ScanAllowance.mustPay(performed: 5, hasAccess: false, free: 5) == true)
    }

    @Test("Le décompte ne passe jamais sous zéro")
    func neverGoesNegative() {
        // Un abonnement qui expire laisse un compteur au-delà du quota : le joueur
        // doit lire « 0 », pas « -12 ».
        #expect(ScanAllowance.remaining(performed: 17, hasAccess: false, free: 5) == 0)
    }

    @Test("Un abonné n'a pas de plafond")
    func subscriberHasNoCeiling() {
        #expect(ScanAllowance.remaining(performed: 0, hasAccess: true) == nil)
        #expect(ScanAllowance.remaining(performed: 900, hasAccess: true) == nil)
    }

    @Test("Un abonné ne voit jamais le paywall, même compteur épuisé")
    func subscriberNeverPays() {
        // Le pire défaut possible : représenter le paywall à quelqu'un qui vient
        // de payer.
        #expect(ScanAllowance.mustPay(performed: 0, hasAccess: true) == false)
        #expect(ScanAllowance.mustPay(performed: 10_000, hasAccess: true) == false)
    }

    @Test("Le quota offert reste celui annoncé partout dans l'app")
    func freeScanCountIsFive() {
        // Épinglé volontairement : l'onboarding, le paywall et les textes traduits
        // annoncent tous ce nombre. Le changer sans les reprendre rendrait l'app menteuse.
        #expect(SubscriptionStore.freeScans == 5)
    }
}
