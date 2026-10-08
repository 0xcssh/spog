import Foundation
import Observation

/// Duels de sept jours entre amis : celui qui marque le plus de points gagne. Le serveur
/// calcule les scores à partir des prises qui comptent au classement (primes comprises) ;
/// l'app crée les défis, les partage, et affiche où en est chacun.
@Observable
final class DuelStore {

    struct Duel: Decodable, Identifiable {
        let id: String
        /// Code à partager tant que personne n'a rejoint ; nul ensuite.
        let code: String?
        let joined: Bool
        let opponent: String?
        let my_points: Int
        let their_points: Int
        let ends_at: String?
        let finished: Bool

        var endsAt: Date? { ends_at.flatMap(IdentifyService.date) }
        var outcome: Outcome? {
            guard finished else { return nil }
            return my_points > their_points ? .won : my_points < their_points ? .lost : .draw
        }
        enum Outcome { case won, lost, draw }
    }

    private struct List: Decodable { let duels: [Duel] }
    private struct Created: Decodable { let code: String? }

    enum JoinResult { case ok, unknown, own, taken, failed }

    private(set) var duels: [Duel] = []
    /// Code reçu par un lien `spog://duel/XXXXXX`, en attente de confirmation du joueur :
    /// on ne rejoint pas un duel à sa place, un lien s'ouvre parfois par accident.
    var pendingFromLink: String?

    @MainActor
    func refresh() async {
        if let value = await Backend.call(["action": "duels"], as: List.self).value { duels = value.duels }
    }

    /// Crée un défi et renvoie son code, à partager.
    @MainActor
    func create() async -> String? {
        let code = await Backend.call(["action": "duel_create"], as: Created.self).value?.code
        await refresh()
        return code
    }

    @MainActor
    func join(_ code: String) async -> JoinResult {
        guard let request = Backend.request(["action": "duel_join", "code": code], timeout: 20),
              let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return .failed }
        if http.statusCode == 200 {
            if let value = try? JSONDecoder().decode(List.self, from: data) { duels = value.duels }
            return .ok
        }
        switch (try? JSONDecoder().decode(Backend.ErrorPayload.self, from: data))?.code {
        case "duel_unknown": return .unknown
        case "duel_own": return .own
        case "duel_taken": return .taken
        default: return .failed
        }
    }

    /// Texte du partage : le lien pour qui a l'app, le code pour qui doit la télécharger.
    static func shareText(_ code: String) -> String {
        String(localized: "duel.share \(code) \("spog://duel/\(code)")")
    }

    /// Code contenu dans un lien `spog://duel/XXXXXX`, s'il a la bonne forme.
    static func code(from url: URL) -> String? {
        guard url.scheme == "spog", url.host == "duel" else { return nil }
        let code = url.lastPathComponent.uppercased()
        return code.range(of: "^[A-Z0-9]{6}$", options: .regularExpression) != nil ? code : nil
    }
}
