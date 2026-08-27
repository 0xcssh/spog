import CoreLocation
import Observation

/// Fournit le pays de repérage quand l'utilisateur choisit le mode automatique.
/// La position est convertie sur-le-champ en code pays et nom de ville, puis jetée :
/// aucune coordonnée n'est conservée ni transmise.
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {

    enum Status { case unknown, denied, ready }

    private(set) var status: Status = .unknown
    /// Dernier pays connu, code ISO à deux lettres.
    private(set) var countryCode: String?
    /// Ville, déjà traduite par le système.
    private(set) var city: String?
    /// Vrai tant que la position n'a pas répondu. Sans ça l'écran reste muet
    /// et le joueur croit que rien ne se passe.
    private(set) var isResolving = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var pendingRequest: ((String?) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer  // la ville suffit
        refreshStatus()
    }

    /// Demande l'autorisation. À n'appeler que sur un geste explicite.
    func requestAccess() {
        manager.requestWhenInUseAuthorization()
    }

    /// Relève le pays courant. Rend `nil` si la position n'est pas disponible :
    /// **un scan ne doit jamais échouer à cause de la localisation.**
    ///
    /// L'autorisation pas encore accordée n'est **pas** un échec : la demande reste
    /// en attente et repart toute seule quand le joueur répond à la question d'iOS.
    /// Rendre `nil` tout de suite, comme avant, laissait le pays de l'appareil en place
    /// — un iPhone réglé sur la France affichait « France » depuis le Viêt Nam.
    func currentCountry(_ completion: @escaping (String?) -> Void) {
        pendingRequest = completion
        isResolving = true
        switch status {
        case .ready:
            manager.requestLocation()
        case .unknown:
            manager.requestWhenInUseAuthorization() // la suite arrive par le délégué
        case .denied:
            finish(countryCode)
        }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshStatus()
        switch status {
        case .ready:  manager.requestLocation()
        case .denied: finish(countryCode)   // refus : on rend la main, on ne fait pas attendre
        case .unknown: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { finish(nil); return }
        geocoder.reverseGeocodeLocation(location) { [weak self] places, _ in
            guard let self else { return }
            let place = places?.first
            // On ne garde que le pays et la ville. La position est abandonnée ici.
            if let code = place?.isoCountryCode { self.countryCode = code }
            self.city = place?.locality
            self.finish(self.countryCode)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(countryCode)
    }

    // MARK: Interne

    private func refreshStatus() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: status = .ready
        case .denied, .restricted:                    status = .denied
        default:                                      status = .unknown
        }
    }

    private func finish(_ code: String?) {
        let callback = pendingRequest
        pendingRequest = nil
        DispatchQueue.main.async {
            self.isResolving = false
            callback?(code)
        }
    }
}
