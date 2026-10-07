import UIKit

/// Le client unique de la fonction Neon. Toutes les requêtes portent les deux identifiants
/// anonymes que le serveur sait compter : l'appareil (`identifierForVendor`) et
/// l'installation (trousseau, voir InstallIdentity). Aucune vue ne parle au réseau
/// autrement que par ici ou par IdentifyService, qui s'appuie aussi sur ce fichier.
enum Backend {

    /// Identifiant d'appareil anonyme, propre à cet éditeur et réinitialisé à la
    /// désinstallation. Le serveur n'en garde que l'empreinte.
    static let deviceIdentifier: String = {
        if let vendorID = UIDevice.current.identifierForVendor?.uuidString { return vendorID }
        let key = "fallbackDeviceIdentifier"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }()

    static func request(_ body: [String: Any], timeout: TimeInterval) -> URLRequest? {
        guard let url = URL(string: BackendConfig.identifyURL),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceIdentifier, forHTTPHeaderField: "x-device-id")
        request.setValue(InstallIdentity.current, forHTTPHeaderField: "x-install-id")
        request.httpBody = data
        return request
    }

    /// Appelle une action et décode sa réponse. Nil sur toute erreur : les appelants
    /// décident eux-mêmes si l'échec se montre au joueur ou se rattrape plus tard.
    static func call<T: Decodable>(_ body: [String: Any], as type: T.Type,
                                   timeout: TimeInterval = 20) async -> (value: T?, status: Int) {
        guard let request = request(body, timeout: timeout),
              let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return (nil, 0) }
        return (try? JSONDecoder().decode(T.self, from: data), http.statusCode)
    }

    /// Code d'erreur stable renvoyé par le serveur (`pseudo_taken`, `rate_limited`…).
    struct ErrorPayload: Decodable { let code: String? }
}
