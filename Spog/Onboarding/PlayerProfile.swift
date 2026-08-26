import Foundation
import Observation

/// Profil du joueur. Chaque champ a un usage réel dans l'app :
/// le pseudo apparaît au classement, la préférence oriente la quête du jour.
/// Rien n'est demandé qui ne serve à rien.
@Observable
final class PlayerProfile {

    var nickname: String {
        didSet { UserDefaults.standard.set(nickname, forKey: Keys.nickname) }
    }

    /// Carrosserie préférée, parmi celles du catalogue. Nil = pas de préférence.
    var favouriteBody: String? {
        didSet { UserDefaults.standard.set(favouriteBody, forKey: Keys.favourite) }
    }

    private enum Keys {
        static let nickname = "profile.nickname"
        static let favourite = "profile.favouriteBody"
    }

    init() {
        nickname = UserDefaults.standard.string(forKey: Keys.nickname) ?? ""
        favouriteBody = UserDefaults.standard.string(forKey: Keys.favourite)
    }

    /// Nom affiché : le pseudo choisi, ou un repli traduit si le joueur l'a laissé vide.
    var displayName: String {
        let trimmed = nickname.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? String(localized: "social.you") : trimmed
    }

    /// Les carrosseries proposées à l'onboarding, avec leur icône.
    static let choices: [(body: String, icon: String)] = [
        ("sport",  "flame.fill"),
        ("suv",    "car.rear.fill"),
        ("hatch",  "car.fill"),
        ("sedan",  "car.side.fill"),
        ("pickup", "truck.pickup.side.fill"),
        ("van",    "box.truck.fill"),
    ]
}
