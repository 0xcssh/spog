import Foundation
import Observation

/// Parrainage.
///
/// **Ce qui existe vraiment aujourd'hui** : le joueur a un code, il peut le partager,
/// et il peut saisir celui d'un ami. C'est tout, et c'est volontaire — sans comptes ni
/// serveur, personne ne peut verifier qu'un code existe, qu'il appartient a quelqu'un
/// d'autre, ni crediter une recompense. Un bonus donne en local serait de toute facon
/// gratuit a volonte : il suffirait de reinstaller l'app.
///
/// Le code saisi est donc **conserve tel quel, en attente**. Le jour ou les comptes
/// arrivent, il part au serveur qui tranche. Rien ici n'aura a etre reecrit.
@Observable
final class ReferralStore {

    /// Longueur d'un code. Assez court pour se recopier a la main, assez long pour ne
    /// pas se deviner : 32^6, soit environ un milliard de combinaisons.
    static let codeLength = 6

    /// Alphabet de Crockford : ni I, ni L, ni O, ni U. Les trois premieres se confondent
    /// avec 1 et 0 quand on recopie un code, la derniere fabrique des gros mots par hasard.
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Le code du joueur, tire une fois puis conserve.
    private(set) var myCode: String
    /// Le code saisi par le joueur. Nil tant qu'il n'a parraine personne.
    private(set) var enteredCode: String?
    /// Code arrive par un lien `spog://invite/...`, en attente d'etre propose.
    /// Il n'est **jamais** applique tout seul : accepter un parrainage est un choix,
    /// et un lien peut etre ouvert par accident.
    var pendingFromLink: String?

    private enum Keys {
        static let mine = "referral.myCode"
        static let entered = "referral.enteredCode"
    }

    init() {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: Keys.mine), Self.isValid(stored) {
            myCode = stored
        } else {
            let generated = Self.makeCode()
            defaults.set(generated, forKey: Keys.mine)
            myCode = generated
        }
        enteredCode = defaults.string(forKey: Keys.entered)
    }

    // MARK: Codes

    private static func makeCode() -> String {
        String((0..<codeLength).map { _ in alphabet.randomElement()! })
    }

    /// Met un code saisi a la main sous sa forme canonique : majuscules, sans espaces
    /// ni tirets, et les confusions classiques ramenees au bon caractere.
    /// Recopier « O » au lieu de « 0 » ne doit pas faire echouer une invitation.
    static func normalize(_ raw: String) -> String {
        var result = ""
        for character in raw.uppercased() {
            switch character {
            case "O":            result.append("0")
            case "I", "L":       result.append("1")
            case "U":            result.append("V")
            default:
                if alphabet.contains(character) { result.append(character) }
            }
        }
        return String(result.prefix(codeLength))
    }

    static func isValid(_ code: String) -> Bool {
        code.count == codeLength && code.allSatisfy(alphabet.contains)
    }

    /// Etat d'un code en cours de saisie. Sert a repondre pendant la frappe
    /// plutot qu'a l'envoi : un message d'erreur apres coup est toujours trop tard.
    enum Check: Equatable {
        case empty
        case tooShort
        case ownCode
        case ready
    }

    func check(_ raw: String) -> Check {
        let code = Self.normalize(raw)
        if code.isEmpty { return .empty }
        if code == myCode { return .ownCode }
        return Self.isValid(code) ? .ready : .tooShort
    }

    /// Enregistre le code. Rend faux si le code n'est pas utilisable.
    @discardableResult
    func apply(_ raw: String) -> Bool {
        guard check(raw) == .ready else { return false }
        let code = Self.normalize(raw)
        enteredCode = code
        UserDefaults.standard.set(code, forKey: Keys.entered)
        return true
    }

    func clearEntered() {
        enteredCode = nil
        UserDefaults.standard.removeObject(forKey: Keys.entered)
    }

    // MARK: Liens

    /// Adresse publique des invitations. **Elle n'existe pas encore** : tant qu'elle est
    /// nil, on partage le code seul plutot qu'un lien mort. Une seule ligne a changer le
    /// jour ou le site est en ligne, ici et nulle part ailleurs.
    static let inviteHost: String? = nil

    /// Lien web d'invitation, quand le domaine existera.
    var inviteLink: URL? {
        guard let host = Self.inviteHost else { return nil }
        return URL(string: "https://\(host)/i/\(myCode)")
    }

    /// Message de partage. Le code y figure **en clair** : le destinataire n'a pas
    /// forcement l'app, et un lien qu'il ne peut pas ouvrir ne lui apprend rien.
    var shareText: String {
        let base = String(localized: "referral.shareText \(myCode)")
        guard let link = inviteLink else { return base }
        return "\(base)\n\(link.absoluteString)"
    }

    /// Code porte par un lien `spog://invite/XXXXXX`. Rend nil si l'URL n'en contient pas.
    static func code(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "spog" else { return nil }
        let parts = ([url.host] + url.pathComponents).compactMap { $0 }
            .filter { $0 != "/" && !$0.isEmpty }
        guard parts.first?.lowercased() == "invite", parts.count >= 2 else { return nil }
        let code = normalize(parts[1])
        return isValid(code) ? code : nil
    }
}
