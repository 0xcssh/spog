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

    /// Nombre de prises reellement effectuees. Sert au quota gratuit ;
    /// le garage de demonstration ne compte pas.
    var scansPerformed: Int {
        didSet { UserDefaults.standard.set(scansPerformed, forKey: Keys.scans) }
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
    }

    init() {
        let defaults = UserDefaults.standard
        country = defaults.string(forKey: Keys.country)
            ?? Locale.current.region?.identifier
            ?? "FR"
        locationMode = LocationMode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .manual
        scansPerformed = defaults.integer(forKey: Keys.scans)
        hasOnboarded = defaults.bool(forKey: Keys.onboarded)
    }
}
