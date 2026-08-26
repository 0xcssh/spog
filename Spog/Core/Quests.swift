import Foundation

/// Objectif du jour. Tire de facon deterministe a partir de la date : tout le monde
/// a la meme quete le meme jour, et rouvrir l'app ne la fait pas changer.
struct DailyQuest {
    let id: String
    let kind: Kind
    let reward: Int

    enum Kind {
        case brand(String)          // une voiture de cette marque
        case body(String)           // une carrosserie donnee
        case rarity(RarityTier)     // au moins ce palier
        case count(Int)             // plusieurs prises aujourd'hui
        case freshModel             // un modele absent du garage
    }

    /// Intitule affiche, deja traduit.
    var title: String {
        switch kind {
        case .brand(let name):   return String(localized: "quest.brand \(name)")
        case .body(let body):    return String(localized: String.LocalizationValue("quest.body." + body))
        case .rarity(let tier):
            let name = String(localized: String.LocalizationValue(tier.key))
            return String(localized: "quest.rarity \(name)")
        case .count(let n):      return String(localized: "quest.count \(n)")
        case .freshModel:        return String(localized: "quest.fresh")
        }
    }

    /// La prise satisfait-elle la quete ?
    func isSatisfied(vehicle: Vehicle, tier: RarityTier,
                     isNewModel: Bool, todayCount: Int) -> Bool {
        switch kind {
        case .brand(let name):  return vehicle.make.caseInsensitiveCompare(name) == .orderedSame
        case .body(let body):   return vehicle.body == body
        case .rarity(let need): return tier.rank >= need.rank
        case .count(let n):     return todayCount >= n
        case .freshModel:       return isNewModel
        }
    }
}

/// Fabrique la quete du jour pour un pays donne.
/// Le pays compte : demander une Nissan en France est jouable, une Bugatti ne l'est pas.
enum QuestFactory {

    /// - Parameter favourite: carrosserie preferee du joueur. Elle entre dans la graine :
    ///   deux joueurs aux gouts differents n'ont pas la meme quete, mais **la quete d'un
    ///   joueur donne reste la meme toute la journee**. C'est cette derniere propriete qui
    ///   compte : sans elle, on rouvre l'app jusqu'a tomber sur une quete facile.
    static func quest(for day: Date, country: String, favourite: String? = nil) -> DailyQuest {
        let store = CatalogStore.shared
        let dayNumber = Int(day.timeIntervalSince1970 / 86_400)
        let taste = UInt64(abs((favourite ?? "").hashValue % 9_973))
        var rng = SeededRNG(seed: (UInt64(bitPattern: Int64(dayNumber)) &+ taste)
                                  &* 0x9E37_79B9_7F4A_7C15)
        let id = "\(dayNumber)-\(country)-\(favourite ?? "any")"

        // On ne propose que ce qui se croise vraiment dans le pays du joueur.
        let plausible = store.vehicles.filter { vehicle in
            store.resolve(vehicle, in: country).tier.rank <= 2
        }
        let brands = Array(Set(plausible.map(\.make))).sorted()
        let bodies = Array(Set(plausible.map(\.body))).sorted()

        switch rng.next(upTo: 10) {
        case 0, 1, 2:
            let name = brands.isEmpty ? "Renault" : brands[rng.next(upTo: brands.count)]
            return DailyQuest(id: id, kind: .brand(name), reward: 150)
        case 3, 4:
            // Une fois sur deux, la quete porte sur ce que le joueur aime :
            // c'est le seul usage de sa preference, et il est visible.
            if let favourite, bodies.contains(favourite), rng.next(upTo: 2) == 0 {
                return DailyQuest(id: id, kind: .body(favourite), reward: 150)
            }
            let body = bodies.isEmpty ? "suv" : bodies[rng.next(upTo: bodies.count)]
            return DailyQuest(id: id, kind: .body(body), reward: 150)
        case 5, 6:
            // Un palier au-dessus du quotidien, sans etre hors de portee.
            let tier = store.tiers.first { $0.rank == 2 } ?? store.tiers[0]
            return DailyQuest(id: id, kind: .rarity(tier), reward: 250)
        case 7, 8:
            return DailyQuest(id: id, kind: .count(3 + rng.next(upTo: 2)), reward: 200)
        default:
            return DailyQuest(id: id, kind: .freshModel, reward: 200)
        }
    }
}

/// Generateur pseudo-aleatoire reproductible : la meme graine donne la meme suite.
private struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x4D59_5DF4_D0F3_3173 : seed }

    mutating func next(upTo bound: Int) -> Int {
        guard bound > 0 else { return 0 }
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Int(state % UInt64(bound))
    }
}
