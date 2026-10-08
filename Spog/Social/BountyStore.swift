import Foundation
import Observation

/// Le pack de primes de la semaine : trois voitures à chasser dans la rue, les mêmes pour
/// tout le pays (voir backend/functions/identify/bounty.ts). Le serveur tire les cibles,
/// les compte et désigne le premier chasseur ; l'app ouvre le pack et suit la chasse.
@Observable
final class BountyStore {

    struct Pack: Decodable {
        let week: String
        let ends_at: String
        let country: String
        let opened: Bool
        let targets: [Target]

        var endsAt: Date? { IdentifyService.date(ends_at) }
        var foundCount: Int { targets.filter(\.found).count }
    }

    struct Target: Decodable, Identifiable {
        let vehicle_id: String
        let make: String
        let model: String
        let body: String
        /// Identifiant du palier de rareté locale, résolu par le catalogue de l'app.
        let tier: String
        let bonus: Int
        let first_bonus: Int
        let found: Bool
        let hunters: Int
        /// Pseudo du premier chasseur : absent si personne n'a trouvé, nul s'il n'a pas de pseudo.
        let first_hunter: String??

        var id: String { vehicle_id }
        var takenFirst: Bool { hunters > 0 }

        private enum CodingKeys: String, CodingKey {
            case vehicle_id, make, model, body, tier, bonus, first_bonus, found, hunters, first_hunter
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            vehicle_id = try c.decode(String.self, forKey: .vehicle_id)
            make = try c.decode(String.self, forKey: .make)
            model = try c.decode(String.self, forKey: .model)
            body = try c.decode(String.self, forKey: .body)
            tier = try c.decode(String.self, forKey: .tier)
            bonus = try c.decode(Int.self, forKey: .bonus)
            first_bonus = try c.decode(Int.self, forKey: .first_bonus)
            found = try c.decode(Bool.self, forKey: .found)
            hunters = try c.decode(Int.self, forKey: .hunters)
            // Trois états : clé absente (personne), valeur nulle (anonyme), pseudo.
            if !c.contains(.first_hunter) {
                first_hunter = nil
            } else if try c.decodeNil(forKey: .first_hunter) {
                first_hunter = .some(nil)
            } else {
                first_hunter = .some(try c.decode(String.self, forKey: .first_hunter))
            }
        }
    }

    private(set) var pack: Pack?

    @MainActor
    func refresh(country: String) async {
        let result = await Backend.call(["action": "bounty", "country": country], as: Pack.self)
        if let value = result.value { pack = value }
    }

    /// Ouvre le pack : le serveur le note, et révèle les cibles.
    @MainActor
    func open(country: String) async -> Pack? {
        let result = await Backend.call(["action": "open_bounty", "country": country], as: Pack.self)
        if let value = result.value { pack = value }
        return result.value
    }
}
