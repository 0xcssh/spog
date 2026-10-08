import SwiftUI

/// Etat partage de l'app. Le pays de reperage vit ici : c'est lui qui pilote la rarete.
/// Tout est persiste — un reglage qui se perd au redemarrage n'est pas un reglage.
@Observable
final class AppState {

    /// Pays ou l'utilisateur repere ses voitures.
    /// Deduit de l'appareil au premier lancement, jamais ecrit en dur.
    var country: String {
        didSet { UserDefaults.standard.set(country, forKey: Keys.country) }
    }

    /// Mode de determination du pays. En automatique, une capture est verifiable.
    var locationMode: LocationMode {
        didSet { UserDefaults.standard.set(locationMode.rawValue, forKey: Keys.mode) }
    }

    /// Nombre de prises reellement effectuees. Distingue le premier jour (10 scans) des
    /// suivants tant que le serveur n'a pas encore repondu ; le garage de demonstration
    /// ne compte pas.
    var scansPerformed: Int {
        didSet { UserDefaults.standard.set(scansPerformed, forKey: Keys.scans) }
    }

    /// Dernier decompte des scans du jour renvoye par le serveur, qui en est l'autorite,
    /// et l'heure a laquelle il expire (minuit UTC). Voir DailyAllowance.
    var scansLeftToday: Int? {
        didSet { UserDefaults.standard.set(scansLeftToday, forKey: Keys.scansLeft) }
    }
    var scansResetAt: Date? {
        didSet { UserDefaults.standard.set(scansResetAt, forKey: Keys.scansReset) }
    }

    /// Meme miroir pour les rendus studio du jour (1 en gratuit) : le serveur tranche, l'app
    /// n'affiche que ce qu'il a dit en dernier.
    var developsLeftToday: Int? {
        didSet { UserDefaults.standard.set(developsLeftToday, forKey: Keys.developsLeft) }
    }
    var developsResetAt: Date? {
        didSet { UserDefaults.standard.set(developsResetAt, forKey: Keys.developsReset) }
    }

    /// L'onboarding a-t-il ete vu ?
    var hasOnboarded: Bool {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: Keys.onboarded) }
    }

    enum LocationMode: String { case automatic, manual }

    var isVerifiedCapture: Bool { locationMode == .automatic }

    private enum Keys {
        static let country = "state.country"
        static let mode = "state.locationMode"
        static let onboarded = "state.onboarded"
        static let scans = "state.scansPerformed"
        static let scansLeft = "state.scansLeftToday"
        static let scansReset = "state.scansResetAt"
        static let developsLeft = "state.developsLeftToday"
        static let developsReset = "state.developsResetAt"
    }

    init() {
        let defaults = UserDefaults.standard
        country = defaults.string(forKey: Keys.country)
            ?? Locale.current.region?.identifier
            ?? "FR"
        locationMode = LocationMode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .manual
        scansPerformed = defaults.integer(forKey: Keys.scans)
        scansLeftToday = defaults.object(forKey: Keys.scansLeft) as? Int
        scansResetAt = defaults.object(forKey: Keys.scansReset) as? Date
        developsLeftToday = defaults.object(forKey: Keys.developsLeft) as? Int
        developsResetAt = defaults.object(forKey: Keys.developsReset) as? Date
        hasOnboarded = defaults.bool(forKey: Keys.onboarded)
    }
}
