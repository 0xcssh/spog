import Foundation
import Observation

/// Le joueur tel que le serveur le connaît : pseudo, compte Apple, ligue de la semaine.
///
/// Aucun compte à créer : le joueur existe dès sa première requête, identifié par son
/// installation. Le pseudo sert à apparaître nommé au classement ; Sign in with Apple
/// sert seulement à retrouver sa collection sur un autre appareil.
@Observable
final class AccountStore {

    struct Profile: Decodable {
        let pseudo: String?
        let apple_linked: Bool
        let catches: Int
        let points: Int
        let first_spots: Int
    }

    struct League: Decodable {
        let joined: Bool
        /// Identifiant technique du palier (`bronze`…`diamond`), traduit par `league.tier.*`.
        let tier: String
        let ends_at: String
        let promote: Int
        let demote: Int
        let members: [Member]

        struct Member: Decodable, Identifiable {
            let rank: Int
            let pseudo: String?
            let points: Int
            let me: Bool
            var id: Int { rank }
        }

        var endsAt: Date? { ISO8601DateFormatter.withFractions.date(from: ends_at)
                            ?? ISO8601DateFormatter().date(from: ends_at) }

        /// La zone de relégation n'existe que dans un groupe assez grand pour qu'elle ait un
        /// sens — même règle que le serveur (`league_tier_for`).
        func zone(of member: Member) -> Zone {
            if member.rank <= promote && member.points > 0 { return .promotion }
            if members.count >= promote + demote && member.rank > members.count - demote { return .demotion }
            return .safe
        }
        enum Zone { case promotion, safe, demotion }
    }

    enum PseudoResult { case ok, taken, invalid, failed }

    private(set) var profile: Profile?
    private(set) var league: League?
    private(set) var isRefreshing = false

    /// Forme acceptée par le serveur, vérifiée ici pour répondre avant même l'envoi.
    static func isValidPseudo(_ text: String) -> Bool {
        text.range(of: "^[A-Za-z0-9_.]{3,20}$", options: .regularExpression) != nil
    }

    @MainActor
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        async let me = Backend.call(["action": "me"], as: Profile.self)
        async let board = Backend.call(["action": "league"], as: League.self)
        let (meResult, boardResult) = await (me, board)
        if let value = meResult.value { profile = value }
        if let value = boardResult.value { league = value }
    }

    @MainActor
    func setPseudo(_ pseudo: String) async -> PseudoResult {
        let trimmed = pseudo.trimmingCharacters(in: .whitespaces)
        guard Self.isValidPseudo(trimmed) else { return .invalid }
        guard let request = Backend.request(["action": "set_pseudo", "pseudo": trimmed], timeout: 20),
              let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return .failed }
        switch http.statusCode {
        case 200:
            await refresh()
            return .ok
        default:
            let code = (try? JSONDecoder().decode(Backend.ErrorPayload.self, from: data))?.code
            return code == "pseudo_taken" ? .taken : code == "pseudo_invalid" ? .invalid : .failed
        }
    }

    /// Rattache l'installation au compte Apple. Si ce compte existe déjà, la collection
    /// de l'autre appareil devient celle-ci côté serveur.
    @MainActor
    func linkApple(identityToken: Data) async -> Bool {
        guard let token = String(data: identityToken, encoding: .utf8) else { return false }
        let result = await Backend.call(["action": "apple_link", "identity_token": token], as: Profile.self)
        guard let value = result.value else { return false }
        profile = value
        await refresh()
        return true
    }

    /// Supprime le compte côté serveur (exigence App Store 5.1.1(v)), photos d'entraînement
    /// comprises. Le garage local reste : il appartient à l'appareil, pas au compte.
    @MainActor
    func deleteAccount() async -> Bool {
        await IdentifyService.forgetTrainingSamples()
        let result = await Backend.call(["action": "delete_account"], as: Backend.ErrorPayload.self)
        guard result.status == 200 else { return false }
        profile = nil
        league = nil
        await refresh()
        return true
    }
}

/// Envoi des prises au serveur, qui compte les points et décide du classement.
/// Silencieux par conception : une prise qui ne part pas reste à envoyer, elle repartira
/// au prochain lancement (voir `GarageStore.syncPending`).
enum CatchSync {

    struct Result: Decodable {
        let first_spot: Bool?
        let counted_points: Int?
        let error: String?
    }

    private static let iso = ISO8601DateFormatter()

    static func submit(_ item: Catch) async -> Result? {
        var body: [String: Any] = [
            "action": "catch",
            "catch_id": item.id.uuidString.lowercased(),
            "vehicle_id": item.vehicleID,
            "country": item.countryCode,
            "caught_at": iso.string(from: item.caughtAt),
            "location_verified": item.verified,
        ]
        if let scan = item.scanID { body["scan_id"] = scan }
        let result = await Backend.call(body, as: Result.self)
        // 403 : la prise appartient à un autre joueur — inutile de la renvoyer à l'infini.
        if result.status == 403 { return Result(first_spot: false, counted_points: 0, error: "not_owner") }
        return result.status == 200 ? result.value : nil
    }

    static func reassign(_ id: UUID, to vehicleID: String) async {
        _ = await Backend.call(["action": "reassign", "catch_id": id.uuidString.lowercased(),
                                "vehicle_id": vehicleID], as: Backend.ErrorPayload.self)
    }

    static func delete(_ id: UUID) async {
        _ = await Backend.call(["action": "delete_catch", "catch_id": id.uuidString.lowercased()],
                               as: Backend.ErrorPayload.self)
    }
}

extension ISO8601DateFormatter {
    /// Le serveur renvoie ses dates avec les millisecondes (`toISOString`).
    static let withFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
