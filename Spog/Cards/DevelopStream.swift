import Foundation

/// La réponse du serveur au passage en studio, en JSON d'un bloc ou dans l'événement
/// `done` du flux : les deux modes portent la même charge utile.
struct DevelopPayload: Decodable, Equatable {
    let image: String?
    let code: String?
    let develops_left: Int?
    let resets_at: String?
}

/// Un événement du flux du passage en studio (voir backend/functions/identify/handler.ts).
enum DevelopStreamEvent: Equatable {
    /// Une image intermédiaire, de plus en plus nette (`index` à partir de 0).
    case partial(Data, index: Int)
    /// Le rendu final et le décompte du jour, comme la réponse JSON.
    case done(DevelopPayload)
    /// Le rendu n'a pas abouti ; rien n'a été décompté.
    case failure(code: String?)

    private struct Partial: Decodable { let image: String; let index: Int? }

    /// Lit un événement SSE ; nil pour ce que l'app ne connaît pas (un événement ajouté
    /// plus tard au serveur ne doit pas faire échouer un ancien build).
    init?(_ event: SSEEvent) {
        let data = Data(event.data.utf8)
        switch event.name {
        case "partial":
            guard let partial = try? JSONDecoder().decode(Partial.self, from: data),
                  let jpeg = Data(base64Encoded: partial.image) else { return nil }
            self = .partial(jpeg, index: partial.index ?? 0)
        case "done":
            guard let payload = try? JSONDecoder().decode(DevelopPayload.self, from: data) else {
                self = .failure(code: "unreadable_ai_response")
                return
            }
            self = .done(payload)
        case "error":
            self = .failure(code: (try? JSONDecoder().decode(DevelopPayload.self, from: data))?.code)
        default:
            return nil
        }
    }
}

/// Un événement SSE complet : son nom et ses lignes `data:` réunies.
struct SSEEvent: Equatable {
    var name: String
    var data: String
}

/// Décodeur SSE ligne à ligne. On lui passe les lignes **y compris les vides** : c'est la
/// ligne vide qui clôt un événement. (`URLSession.AsyncBytes.lines` saute les lignes vides,
/// d'où le découpage à la main dans `DevelopService`.)
struct SSEDecoder {
    private var name = ""
    private var data: [String] = []

    /// Rend l'événement que cette ligne termine, s'il y en a un.
    mutating func feed(_ rawLine: String) -> SSEEvent? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty {
            defer { name = ""; data = [] }
            guard !name.isEmpty || !data.isEmpty else { return nil }
            return SSEEvent(name: name, data: data.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil }   // commentaire, battement de cœur
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }
        if field == "event" { name = String(value) } else if field == "data" { data.append(String(value)) }
        return nil
    }
}
