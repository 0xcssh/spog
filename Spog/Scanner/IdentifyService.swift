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
    /// Scans du jour restants selon le serveur, qui en est l'autorite, et l'heure de
    /// remise a zero. Nil pour un abonne.
    var scansLeft: Int? = nil
    var scansResetAt: Date? = nil
    /// Photo conservée pour l'entraînement, si le joueur l'a accepté : sert à y attacher
    /// son étiquette quand il confirme ou corrige le modèle.
    var sampleID: String? = nil
    /// Trace de l'identification côté serveur : la preuve, pour le classement, que la
    /// prise déclarée ensuite correspond à cette photo.
    var scanID: String? = nil
    /// Cote d'occasion dans la devise du pays de la prise. Nil quand le serveur n'a pas su,
    /// ce qui est fréquent et voulu : il ne voit ni le kilométrage ni l'état mécanique.
    var price: PriceBracket? = nil

    /// Texte libre soumis au rapprochement avec le catalogue.
    var fullText: String {
        [make, model, generation].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Appelle la fonction Neon "identify", seul point de sortie reseau de l'app.
/// Voir backend/functions/identify/handler.ts pour le contrat.
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
        /// Scans du jour epuises, constate par le serveur : Pro doit s'interposer, meme si
        /// le miroir local croyait qu'il en restait (autre appareil, reinstallation).
        case dailyLimit(resetsAt: Date?)

        var errorDescription: String? {
            switch self {
            case .network:         String(localized: "scanError.network")
            case .unreadableImage: String(localized: "scanError.unreadableImage")
            case .noVehicle:       String(localized: "scanError.noVehicle")
            case .notLive:         String(localized: "scanError.notLive")
            case .dailyLimit:      String(localized: "scanError.dailyLimit")
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

    /// - Parameter entitlement: transaction d'abonnement signee par Apple, si le joueur
    ///   en a une. Le serveur la verifie lui-meme ; sans elle, le scan est decompte
    ///   des scans offerts.
    /// - Parameter country: pays de la prise (code ISO à 2 lettres). Le serveur en déduit
    ///   le marché et la devise de la cote ; vide, il n'en calcule pas.
    static func identify(_ photo: UIImage, entitlement: String?,
                         trainingConsent: Bool, country: String) async throws -> Identification {
        guard let base64 = compressedJPEGBase64(from: photo) else {
            throw IdentifyError.unreadableImage
        }
        guard let url = URL(string: BackendConfig.identifyURL) else {
            throw IdentifyError.network
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // 25 s : au-dela, mieux vaut rendre la main au joueur que le laisser devant
        // un viseur fige. Le serveur repond en 3 a 8 s dans les cas normaux.
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Backend.deviceIdentifier, forHTTPHeaderField: "x-device-id")
        request.setValue(InstallIdentity.current, forHTTPHeaderField: "x-install-id")
        var body: [String: Any] = ["imageBase64": base64]
        if let entitlement { body["entitlement"] = entitlement }
        if trainingConsent { body["training_consent"] = true }
        if !country.isEmpty { body["country"] = country }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw IdentifyError.network
        }
        guard let http = response as? HTTPURLResponse else { throw IdentifyError.network }

        struct ErrorPayload: Decodable { let code: String?; let error: String?; let resets_at: String? }
        guard http.statusCode == 200 else {
            let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data)
            if payload?.code == "daily_limit" {
                throw IdentifyError.dailyLimit(resetsAt: payload?.resets_at.flatMap(Self.date))
            }
            throw IdentifyError.server(code: payload?.code, fallback: payload?.error)
        }

        struct SuccessPayload: Decodable {
            let make: String, model: String, generation: String, color: String
            let body: String?
            let confidence: Double
            let is_screen: Bool, vehicle_present: Bool
            let scans_left: Int?
            let resets_at: String?
            let sample_id: String?
            let scan_id: String?
            // Optionnels, et en Double plutôt qu'en Int : un serveur plus ancien ne les
            // envoie pas, et un montant qui ne tiendrait pas dans un Int ferait échouer
            // tout le décodage, donc le scan, pour une simple cote.
            let price_min: Double?
            let price_max: Double?
            let price_currency: String?
        }
        guard let payload = try? JSONDecoder().decode(SuccessPayload.self, from: data) else {
            throw IdentifyError.server(code: "unreadable_ai_response", fallback: nil)
        }

        // Les deux refus de la regle du jeu, avant tout le reste.
        if payload.is_screen { throw IdentifyError.notLive }
        guard payload.vehicle_present, !payload.model.isEmpty else { throw IdentifyError.noVehicle }

        return Identification(make: payload.make,
                              model: payload.model,
                              generation: payload.generation,
                              // Optionnel a la lecture : une app installee avant que le
                              // serveur renvoie la carrosserie ne doit pas cesser de marcher.
                              body: payload.body ?? "sedan",
                              color: payload.color,
                              confidence: payload.confidence,
                              scansLeft: payload.scans_left,
                              scansResetAt: payload.resets_at.flatMap(Self.date),
                              sampleID: payload.sample_id,
                              scanID: payload.scan_id,
                              price: PriceBracket.from(low: payload.price_min,
                                                       high: payload.price_max,
                                                       currency: payload.price_currency))
    }

    /// Dates du serveur : `toISOString`, avec les millisecondes.
    static func date(_ text: String) -> Date? {
        ISO8601DateFormatter.withFractions.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    // MARK: Entraînement

    enum LabelSource: String { case confirmed, corrected }

    /// Le joueur a désigné le bon modèle : c'est l'étiquette qui fait foi pour
    /// l'entraînement. Silencieux en cas d'échec — une étiquette perdue ne doit
    /// jamais gêner le jeu.
    static func label(sampleID: String, vehicleID: String, source: LabelSource) async {
        _ = await Backend.call(["action": "label", "sample_id": sampleID,
                                "vehicle_id": vehicleID, "source": source.rawValue],
                               as: Backend.ErrorPayload.self)
    }

    /// Retrait de l'accord : le serveur efface toutes les photos de cette installation.
    static func forgetTrainingSamples() async {
        _ = await Backend.call(["action": "forget"], as: Backend.ErrorPayload.self)
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
