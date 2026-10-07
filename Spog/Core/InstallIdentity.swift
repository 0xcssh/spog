import Foundation
import Security

/// Identifiant d'installation, envoyé au serveur qui compte les scans offerts.
///
/// Rangé dans le **trousseau**, pas dans les réglages : le trousseau survit à la
/// désinstallation de l'app, les réglages non. Avec `identifierForVendor` ou
/// `UserDefaults`, supprimer puis réinstaller Spog rendait les cinq scans offerts.
///
/// Ce n'est pas une identité : un tirage aléatoire, propre à cet appareil (jamais
/// synchronisé par iCloud), dont le serveur ne garde que l'empreinte.
enum InstallIdentity {

    private static let service = "com.mandalore-group.spog.install"
    private static let account = "install-id"

    static let current: String = {
        if let existing = read() { return existing }
        let generated = UUID().uuidString
        // Un trousseau indisponible (rarissime) ne doit pas bloquer le scan : le
        // serveur retombe alors sur l'identifiant d'appareil.
        write(generated)
        return read() ?? generated
    }()

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String) {
        var query = baseQuery
        query[kSecValueData as String] = Data(value.utf8)
        // Lisible après le premier déverrouillage : un scan peut partir pendant que
        // l'écran se verrouille, et `WhenUnlocked` le ferait échouer.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }
}
