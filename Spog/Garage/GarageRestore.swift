import Foundation

/// Une carte telle que le serveur la garde (action `garage`, backend/functions/identify/social.ts).
///
/// Presque tout est optionnel : les prises envoyées par les builds d'avant la migration 008
/// n'ont ni numéro, ni teinte, ni cote, et une réponse partielle ne doit jamais faire
/// échouer le décodage de tout le garage.
struct RemoteCatch: Decodable, Equatable {
    let id: String
    let vehicle_id: String
    let country: String
    let caught_at: String
    let first_spot: Bool?
    let location_verified: Bool?
    let scan_id: String?
    let serial: Int?
    /// 0xRRGGBB. Lu en `Int` : un `UInt32` ferait échouer tout le décodage sur une valeur
    /// négative, alors qu'on veut seulement ignorer la teinte.
    let paint: Int?
    let price: Price?

    struct Price: Decodable, Equatable {
        let low: Double?
        let high: Double?
        let currency: String?
    }

    var caughtAt: Date? {
        ISO8601DateFormatter.withFractions.date(from: caught_at) ?? ISO8601DateFormatter().date(from: caught_at)
    }
}

/// Réponse de l'action `garage`.
struct RemoteGarage: Decodable {
    let catches: [RemoteCatch]
}

/// Fusion des cartes du serveur dans le garage de l'appareil, après une réinstallation ou
/// sur un nouvel iPhone. Fonction pure, séparée de `GarageStore` pour se tester sans disque.
///
/// Règles : on n'ajoute que ce qui manque, on ne touche jamais à une prise locale (elle a sa
/// photo, le serveur n'a qu'un résumé), et une carte restaurée n'a pas de photo — elles ne
/// quittent jamais l'appareil. Elle s'affiche donc avec le rendu du modèle (`ModelArt`).
enum GarageRestore {

    static func merged(local: [Catch], remote: [RemoteCatch], excluding removed: Set<UUID> = []) -> [Catch] {
        var known = Set(local.map(\.id)).union(removed)
        var fresh: [(remote: RemoteCatch, id: UUID, date: Date)] = []
        for item in remote {
            guard let id = UUID(uuidString: item.id), let date = item.caughtAt,
                  !item.vehicle_id.isEmpty, !item.country.isEmpty,
                  known.insert(id).inserted else { continue }
            fresh.append((remote: item, id: id, date: date))
        }
        guard !fresh.isEmpty else { return local }
        fresh.sort { $0.date < $1.date }

        // Les numéros manquants viennent après tous ceux qu'on connaît, locaux comme
        // serveur : deux cartes du même garage ne doivent pas porter le même.
        var next = (local.map(\.serial) + fresh.compactMap { validSerial($0.remote.serial) }).max() ?? 0
        let restored = fresh.map { entry -> Catch in
            let item = entry.remote
            let serial: Int
            if let stored = validSerial(item.serial) {
                serial = stored
            } else {
                next += 1
                serial = next
            }
            return Catch(id: entry.id,
                         vehicleID: item.vehicle_id,
                         serial: serial,
                         caughtAt: entry.date,
                         countryCode: item.country.uppercased(),
                         verified: item.location_verified ?? false,
                         paint: validPaint(item.paint) ?? fallbackPaint(for: entry.id),
                         hasShot: false,
                         sampleID: nil,
                         scanID: item.scan_id,
                         synced: true,
                         firstSpot: item.first_spot ?? false,
                         price: item.price.flatMap {
                             PriceBracket.from(low: $0.low, high: $0.high, currency: $0.currency)
                         })
        }
        return local + restored
    }

    /// Teinte d'une prise envoyée avant que le serveur la garde. Tirée de l'identifiant et
    /// non au hasard : la même carte doit garder la même couleur d'un appareil à l'autre et
    /// d'une restauration à la suivante. Pas `hashValue`, qui change à chaque lancement.
    static func fallbackPaint(for id: UUID) -> UInt32 {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        let sum = bytes.reduce(0) { ($0 &* 31 &+ Int($1)) & 0x7FFF_FFFF }
        return CarPaint.palette[sum % CarPaint.palette.count]
    }

    private static func validSerial(_ value: Int?) -> Int? {
        guard let value, value >= 1 else { return nil }
        return value
    }

    private static func validPaint(_ value: Int?) -> UInt32? {
        guard let value, (0...0xFFFFFF).contains(value) else { return nil }
        return UInt32(value)
    }
}
