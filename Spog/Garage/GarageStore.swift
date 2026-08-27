import SwiftUI

/// Une capture : ce qui est reellement stocke. La rarete n'est pas figee dedans,
/// elle est resolue a l'affichage a partir du pays ou la voiture a ete attrapee.
struct Catch: Identifiable, Codable {
    let id: UUID
    let vehicleID: String
    let serial: Int
    let caughtAt: Date
    /// Pays de reperage au moment de la capture. Une carte garde son contexte.
    let countryCode: String
    /// Capturee avec la localisation active : verifiable.
    let verified: Bool
    /// Teinte de carrosserie. Viendra de l'IA au moment du scan.
    let paint: UInt32
    /// Vrai si des photos sont rangees sur le disque pour cette capture.
    var hasShot: Bool = false

    /// Photos relues depuis le disque, jamais gardees en memoire dans la capture.
    var shot: StyledShot? { hasShot ? ShotStore.load(id) : nil }
}

@Observable
final class GarageStore {

    private(set) var catches: [Catch] = []
    private let catalog = CatalogStore.shared

    init(demoCountry: String) {
        load()
#if DEBUG
        // Garage de demonstration, **en build de developpement seulement**.
        // Il servait a montrer l'app avant que le scanner existe ; maintenant qu'il
        // existe, de fausses prises dans les points, le niveau et le Spogdex d'un
        // vrai joueur seraient un mensonge. Il reste ici pour les captures d'ecran
        // et les essais, et ne peut pas partir sur l'App Store.
        if catches.isEmpty && !UserDefaults.standard.bool(forKey: Self.seededKey) {
            seedDemo(in: demoCountry)
            UserDefaults.standard.set(true, forKey: Self.seededKey)
            save()
        }
#endif
    }

    // MARK: Persistance

    private static let seededKey = "garage.seeded"

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("garage.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let stored = try? JSONDecoder().decode([Catch].self, from: data)
        else { return }
        catches = stored
    }

    /// Ecriture immediate : une prise perdue est une prise que le joueur ne refera pas.
    private func save() {
        guard let data = try? JSONEncoder().encode(catches) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    func remove(_ item: Catch) {
        catches.removeAll { $0.id == item.id }
        ShotStore.delete(item.id)
        save()
    }

    // MARK: Lecture

    /// Vue prete a afficher d'une capture.
    func card(_ item: Catch) -> CardData? {
        guard let vehicle = catalog.vehicles.first(where: { $0.id == item.vehicleID }) else { return nil }
        let resolution = catalog.resolve(vehicle, in: item.countryCode)
        return CardData(id: item.id,
                        vehicle: vehicle,
                        tier: resolution.tier,
                        serial: item.serial,
                        caughtAt: item.caughtAt,
                        placeName: catalog.countryName(item.countryCode),
                        verified: item.verified,
                        paint: item.paint,
                        shot: item.shot)
    }

    var cards: [CardData] {
        catches.sorted { $0.caughtAt > $1.caughtAt }.compactMap(card)
    }

    var totalPoints: Int { cards.reduce(0) { $0 + $1.tier.points } }
    var uniqueModels: Int { Set(catches.map(\.vehicleID)).count }

    /// Marques distinctes representees dans le garage.
    var uniqueBrands: Int {
        Set(cards.map(\.vehicle.make)).count
    }
    var verifiedCount: Int { catches.filter(\.verified).count }

    /// Nombre de captures par palier, dans l'ordre du catalogue.
    func countByTier() -> [(RarityTier, Int)] {
        let cards = self.cards
        return catalog.tiers.map { tier in
            (tier, cards.filter { $0.tier.id == tier.id }.count)
        }
    }

    var bestCard: CardData? {
        cards.max { $0.tier.rank < $1.tier.rank }
    }

    // MARK: Progression

    /// Nombre de modeles distincts du catalogue deja attrapes, et total possible.
    /// Le total inclut les vehicules appris de l'IA : ils font partie du monde du
    /// joueur au meme titre que les autres, et le denominateur grandit avec ses
    /// decouvertes — ce qui raconte quelque chose plutot que de le cacher.
    var dexCaught: Int { uniqueModels }
    var dexTotal: Int { catalog.vehicles.count }

    /// Prises faites aujourd'hui : sert aux quetes de volume.
    var todayCount: Int {
        catches.filter { Calendar.current.isDateInToday($0.caughtAt) }.count
    }

    func hasModel(_ vehicleID: String) -> Bool {
        catches.contains { $0.vehicleID == vehicleID }
    }

    // MARK: Badges

    struct Badge: Identifiable {
        let id: String
        let icon: String
        let unlocked: Bool
    }

    var badges: [Badge] {
        let cards = self.cards
        let has: (String) -> Bool = { id in cards.contains { $0.tier.id == id } }
        return [
            Badge(id: "first",     icon: "car.fill",            unlocked: !cards.isEmpty),
            Badge(id: "ten",       icon: "square.stack.3d.up.fill", unlocked: cards.count >= 10),
            Badge(id: "rare",      icon: "diamond.fill",        unlocked: has("rare")),
            Badge(id: "exotic",    icon: "flame.fill",          unlocked: has("exotic")),
            Badge(id: "legendary", icon: "crown.fill",          unlocked: has("legendary")),
            Badge(id: "verified",  icon: "checkmark.seal.fill", unlocked: verifiedCount >= 5)
        ]
    }

    // MARK: Ecriture

    @discardableResult
    func add(vehicleID: String, country: String, verified: Bool,
             paint: UInt32? = nil, shot: StyledShot? = nil) -> Catch {
        let id = UUID()
        if let shot { ShotStore.save(shot, for: id) }
        let item = Catch(id: id,
                         vehicleID: vehicleID,
                         serial: catches.count + 1,
                         caughtAt: Date(),
                         countryCode: country,
                         verified: verified,
                         paint: paint ?? CarPaint.random(),
                         hasShot: shot != nil)
        catches.append(item)
        save()
        return item
    }

    /// Couleur du palier pour un vehicule, dans un pays donne. Sert a teinter
    /// la mise en scene de la photo avant meme que la carte existe.
    func glowColor(vehicleID: String, country: String) -> UIColor {
        guard let vehicle = catalog.vehicles.first(where: { $0.id == vehicleID }) else {
            return UIColor(Theme.accent)
        }
        return UIColor(catalog.resolve(vehicle, in: country).tier.color)
    }

#if DEBUG
    /// Garage de demonstration. Reserve au developpement : voir `init`.
    private func seedDemo(in country: String) {
        // En tete, les modeles qui ont deja leur rendu : le garage de demonstration
        // doit montrer l'app telle qu'elle sera, pas des silhouettes de repli.
        let wanted = ["hyundai-i30-n", "audi-a6", "porsche-taycan", "renault-clio",
                      "peugeot-208", "bmw-m4", "mercedes-amg-gt", "vw-golf-gti",
                      "alpine-a110", "citroen-2cv", "ferrari-488-gtb", "dacia-sandero",
                      "toyota-yaris", "mini-cooper"]
        let known = Set(catalog.vehicles.map(\.id))
        for (index, id) in wanted.enumerated() where known.contains(id) {
            catches.append(Catch(id: UUID(),
                                 vehicleID: id,
                                 serial: index + 1,
                                 caughtAt: Date().addingTimeInterval(-Double(index) * 61_000),
                                 countryCode: country,
                                 verified: index % 3 != 0,
                                 paint: CarPaint.palette[index % CarPaint.palette.count]))
        }
    }
#endif
}
