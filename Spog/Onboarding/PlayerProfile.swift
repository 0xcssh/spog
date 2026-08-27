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

    /// Carrosseries préférées. **Plusieurs réponses possibles** : personne n'aime
    /// exactement un type de voiture, et forcer un choix unique donnait une réponse fausse.
    /// Vide = pas de préférence, ce qui reste un choix valable.
    var favouriteBodies: Set<String> {
        didSet { UserDefaults.standard.set(favouriteList, forKey: Keys.favourites) }
    }

    /// Ordre stable, pour l'affichage comme pour les graines de quête.
    /// Un `Set` n'a pas d'ordre : s'en servir tel quel rendrait la quête du jour instable.
    var favouriteList: [String] { favouriteBodies.sorted() }

    private enum Keys {
        static let nickname = "profile.nickname"
        static let favourite = "profile.favouriteBody"    // ancienne clé, réponse unique
        static let favourites = "profile.favouriteBodies"
    }

    init() {
        let defaults = UserDefaults.standard
        nickname = defaults.string(forKey: Keys.nickname) ?? ""
        if let stored = defaults.array(forKey: Keys.favourites) as? [String] {
            favouriteBodies = Set(stored)
        } else if let single = defaults.string(forKey: Keys.favourite) {
            // Profil créé quand la question n'acceptait qu'une réponse : on la garde.
            favouriteBodies = [single]
        } else {
            favouriteBodies = []
        }
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
