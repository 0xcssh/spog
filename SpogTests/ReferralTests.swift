import Testing
import Foundation
@testable import Spog

/// Les codes de parrainage.
///
/// Un code se recopie à la main, depuis un message ou une capture d'écran. Toute la
/// normalisation existe pour ça : le joueur qui tape « O » au lieu de « 0 » ne doit pas
/// se voir refuser l'invitation de son ami sans explication.
struct ReferralTests {

    // MARK: Normalisation

    @Test("Les confusions de recopie sont rattrapées")
    func normalizeFixesLookalikes() {
        #expect(ReferralStore.normalize("O") == "0")
        #expect(ReferralStore.normalize("I") == "1")
        #expect(ReferralStore.normalize("L") == "1")
        #expect(ReferralStore.normalize("U") == "V")
    }

    @Test("La casse, les espaces et les tirets sont ignorés")
    func normalizeIgnoresFormatting() {
        #expect(ReferralStore.normalize("ab-12 cd") == "AB12CD")
        #expect(ReferralStore.normalize("abc123") == "ABC123")
    }

    @Test("Un code trop long est coupé à la bonne longueur")
    func normalizeTruncates() {
        #expect(ReferralStore.normalize("ABC123XYZ").count == ReferralStore.codeLength)
    }

    @Test("La normalisation est idempotente")
    func normalizeIsStable() {
        // Le champ de saisie normalise à chaque frappe : normaliser deux fois doit
        // donner la même chose, sinon le texte se déforme sous les doigts du joueur.
        let once = ReferralStore.normalize("o1l-u9")
        #expect(ReferralStore.normalize(once) == once)
    }

    // MARK: Validité

    @Test("Un code valide fait la bonne longueur et n'utilise que l'alphabet")
    func validityRules() {
        #expect(ReferralStore.isValid("ABC123"))
        #expect(!ReferralStore.isValid("ABC12"))       // trop court
        #expect(!ReferralStore.isValid("ABC1234"))     // trop long
        #expect(!ReferralStore.isValid("ABC12O"))      // O n'appartient pas à l'alphabet
        #expect(!ReferralStore.isValid(""))
    }

    @Test("Les lettres écartées ne sortent jamais d'une normalisation")
    func excludedLettersNeverSurvive() {
        // I, L, O et U sont écartés justement parce qu'ils se confondent. S'ils
        // ressortaient, on aurait rétabli l'ambiguïté qu'on cherchait à supprimer.
        let normalized = ReferralStore.normalize("ILOU12")
        #expect(!normalized.contains("I"))
        #expect(!normalized.contains("L"))
        #expect(!normalized.contains("O"))
        #expect(!normalized.contains("U"))
    }

    // MARK: Liens d'invitation

    @Test("Un lien d'invitation livre son code")
    func linkYieldsCode() {
        #expect(ReferralStore.code(from: URL(string: "spog://invite/ABC123")!) == "ABC123")
        // La casse du lien ne compte pas : un client de messagerie peut l'abîmer.
        #expect(ReferralStore.code(from: URL(string: "spog://invite/abc123")!) == "ABC123")
    }

    @Test("Un lien étranger ne livre rien")
    func foreignLinksYieldNothing() {
        // Le point d'entrée d'une app est une porte ouverte : tout ce qui n'est pas
        // exactement une invitation Spog doit repartir les mains vides.
        #expect(ReferralStore.code(from: URL(string: "https://example.com/invite/ABC123")!) == nil)
        #expect(ReferralStore.code(from: URL(string: "spog://garage/ABC123")!) == nil)
        #expect(ReferralStore.code(from: URL(string: "spog://invite")!) == nil)
        #expect(ReferralStore.code(from: URL(string: "spog://invite/TROPCOURT1")!) == nil)
    }

    @Test("Un lien portant un code invalide ne livre rien")
    func invalidCodeInLinkYieldsNothing() {
        #expect(ReferralStore.code(from: URL(string: "spog://invite/AB1")!) == nil)
    }

    // MARK: Saisie

    @Test("La saisie est jugée pendant la frappe")
    func checkReportsProgress() {
        let store = ReferralStore()
        #expect(store.check("") == .empty)
        #expect(store.check("AB1") == .tooShort)
        #expect(store.check("ABC123") == .ready)
    }

    @Test("Son propre code est refusé")
    func ownCodeIsRejected() {
        // Se parrainer soi-même serait le premier réflexe de tout le monde.
        let store = ReferralStore()
        #expect(store.check(store.myCode) == .ownCode)
        #expect(store.apply(store.myCode) == false)
    }

    @Test("Le code du joueur est valide dès la première ouverture")
    func generatedCodeIsValid() {
        #expect(ReferralStore.isValid(ReferralStore().myCode))
    }

    @Test("Un code refusé n'est pas enregistré")
    func rejectedCodeIsNotStored() {
        let store = ReferralStore()
        store.clearEntered()
        #expect(store.apply("AB1") == false)
        #expect(store.enteredCode == nil)
    }
}
