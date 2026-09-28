import UIKit

/// Ce que le serveur renvoie pour une photo : des donnees, jamais du texte a afficher.
/// La rarete, les points et les regles du jeu n'apparaissent pas ici — ils vivent
/// dans le catalogue embarque, donc modifiables sans redeployer le backend.
struct Identification {
    let make: String
    let model: String
    let generation: String
    /// Carrosserie, dans la liste fermee des six geometries que l'app sait dessiner.
    /// Sert aux voitures que le catalogue ne connait pas encore : sans elle, impossible
    /// de mettre en scene une carte apprise.
    let body: String
    /// Teinte en anglais, prise dans une liste fermee. Rapprochee de la palette par CarPaint.
    let color: String
    let confidence: Double
    /// Cote d'occasion estimee, en fourchette. Nil quand le serveur n'a pas su, ce qui
    /// est frequent et voulu : il ne voit ni le kilometrage ni l'etat mecanique.
    let price: PriceBracket?

    /// Texte libre soumis au rapprochement avec le catalogue.
    var fullText: String {
        [make, model, generation].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Fourchette de cote. **Jamais un chiffre unique** : la photo ne contient pas de quoi
/// justifier une precision au centaine d'euros pres, et un montant exact serait cru sur
/// parole puis dementi par le premier joueur qui connait sa voiture.
struct PriceBracket: Equatable {
    let low: Int
    let high: Int
    /// Code ISO de la devise, decide par le serveur. L'app ne convertit rien :
    /// afficher une somme convertie a un taux inconnu serait une invention de plus.
    let currency: String
}

/// Appelle la Edge Function "identify", seul point de sortie reseau de l'app.
/// Voir supabase/functions/identify/index.ts pour le contrat.
enum IdentifyService {

    enum IdentifyError: LocalizedError {
        /// `code` vient du serveur et est stable ; `fallback` est son texte brut,
        /// affiche seulement si le code est inconnu de cette version de l'app.
        case server(code: String?, fallback: String?)
        case network
        case unreadableImage
        /// Aucune voiture sur la photo.
        case noVehicle
        /// Photo d'un ecran, d'une affiche ou d'une miniature : la regle du jeu
        /// est la camera en direct sur une vraie voiture.
        case notLive

        var errorDescription: String? {
            switch self {
            case .network:         String(localized: "scanError.network")
            case .unreadableImage: String(localized: "scanError.unreadableImage")
            case .noVehicle:       String(localized: "scanError.noVehicle")
            case .notLive:         String(localized: "scanError.notLive")
            case .server(let code, let fallback):
                Self.message(for: code) ?? fallback ?? String(localized: "scanError.failed")
            }
        }

        /// Traduction des codes du serveur. Un code inconnu (app plus ancienne que
        /// le backend) retombe sur le texte fourni par le serveur.
        private static func message(for code: String?) -> String? {
            switch code {
            case "rate_limited":     String(localized: "scanError.rateLimited")
            case "service_saturated": String(localized: "scanError.saturated")
            case "image_too_large":  String(localized: "scanError.imageTooLarge")
            case "missing_input":    String(localized: "scanError.unreadableImage")
            case "identification_failed", "unreadable_ai_response":
                                     String(localized: "scanError.failed")
            case "server_misconfigured", "bad_request", "method_not_allowed":
                                     String(localized: "scanError.unavailable")
            default: nil
            }
        }
    }

    /// Identifiant d'appareil anonyme, envoye au backend pour appliquer un quota
    /// anti-abus. `identifierForVendor` est fourni par Apple, propre a cet editeur,
    /// et reinitialise a la desinstallation — il n'identifie pas la personne.
    /// Le serveur n'en stocke que l'empreinte.
    private static let deviceIdentifier: String = {
        if let vendorID = UIDevice.current.identifierForVendor?.uuidString { return vendorID }
        let key = "fallbackDeviceIdentifier"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }()

    static func identify(_ photo: UIImage) async throws -> Identification {
        guard let base64 = compressedJPEGBase64(from: photo) else {
            throw IdentifyError.unreadableImage
        }
        guard let url = URL(string: "\(BackendConfig.supabaseURL)/functions/v1/identify") else {
            throw IdentifyError.network
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // 25 s : au-dela, mieux vaut rendre la main au joueur que le laisser devant
        // un viseur fige. Le serveur repond en 3 a 8 s dans les cas normaux.
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(BackendConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(deviceIdentifier, forHTTPHeaderField: "x-device-id")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["imageBase64": base64])

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw IdentifyError.network
        }
        guard let http = response as? HTTPURLResponse else { throw IdentifyError.network }

        struct ErrorPayload: Decodable { let code: String?; let error: String? }
        guard http.statusCode == 200 else {
            let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data)
            throw IdentifyError.server(code: payload?.code, fallback: payload?.error)
        }

        struct SuccessPayload: Decodable {
            let make: String, model: String, generation: String, color: String
            let body: String?
            let confidence: Double
            let is_screen: Bool, vehicle_present: Bool
            // Optionnels : une app installee avant le deploiement de la cote doit
            // continuer a fonctionner sans rien afficher de plus.
            let price_min: Int?, price_max: Int?, price_currency: String?
        }
        guard let payload = try? JSONDecoder().decode(SuccessPayload.self, from: data) else {
            throw IdentifyError.server(code: "unreadable_ai_response", fallback: nil)
        }

        // Les deux refus de la regle du jeu, avant tout le reste.
        if payload.is_screen { throw IdentifyError.notLive }
        guard payload.vehicle_present, !payload.model.isEmpty else { throw IdentifyError.noVehicle }

        var price: PriceBracket?
        if let low = payload.price_min, let high = payload.price_max, low > 0, high >= low {
            price = PriceBracket(low: low, high: high,
                                 currency: payload.price_currency ?? "EUR")
        }

        return Identification(make: payload.make,
                              model: payload.model,
                              generation: payload.generation,
                              // Optionnel a la lecture : une app installee avant que le
                              // serveur renvoie la carrosserie ne doit pas cesser de marcher.
                              body: payload.body ?? "sedan",
                              color: payload.color,
                              confidence: payload.confidence,
                              // Le serveur ecarte deja les fourchettes absurdes. On
                              // reverifie ici parce qu'une app reste en service longtemps
                              // apres qu'un serveur a change, et qu'afficher « 0 € »
                              // serait pire que ne rien afficher du tout.
                              price: price)
    }

    /// Recompresse la photo (max 1280 px) : bien assez pour reconnaitre une voiture,
    /// et bien plus leger a envoyer depuis un reseau mobile.
    private static func compressedJPEGBase64(from image: UIImage) -> String? {
        let maxDimension: CGFloat = 1280
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1 // sinon l'image sort a la densite de l'ecran, donc trois fois trop lourde
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }
}
