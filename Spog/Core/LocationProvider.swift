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
    /// Vitesse courante en km/h. Nil quand elle est inconnue : suivi arrêté,
    /// autorisation refusée, ou appareil incapable de la mesurer (intérieur, GPS faible).
    private(set) var speedKmh: Double?

    /// Suivi continu de la position, uniquement pour la vitesse.
    private var watchingSpeed = false

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

    /// Suit la position en continu pour connaître la vitesse. **À n'activer que sur
    /// l'écran de scan** : un suivi permanent viderait la batterie pour rien.
    /// Sans autorisation, la vitesse reste inconnue — et un scan n'est jamais bloqué
    /// sur une vitesse qu'on ignore.
    func startWatchingSpeed() {
        guard status == .ready, !watchingSpeed else { return }
        watchingSpeed = true
        manager.startUpdatingLocation()
    }

    func stopWatchingSpeed() {
        guard watchingSpeed else { return }
        watchingSpeed = false
        manager.stopUpdatingLocation()
        speedKmh = nil
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

        if watchingSpeed {
            // `speed` vaut -1 quand l'appareil ne sait pas : on ne la traduit pas en zéro,
            // sinon une vitesse inconnue passerait pour un arrêt.
            let measured = location.speed
            DispatchQueue.main.async {
                self.speedKmh = measured >= 0 ? measured * 3.6 : nil
            }
        }

        // Le géocodage inverse est limité par Apple : on ne l'appelle que si quelqu'un
        // attend vraiment un pays, jamais à chaque point du suivi de vitesse.
        guard pendingRequest != nil else { return }
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
