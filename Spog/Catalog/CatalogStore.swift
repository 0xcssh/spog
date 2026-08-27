import Foundation

/// Charge le catalogue embarque et resout rarete et rapprochement de texte.
/// Aucun appel reseau : tout vit dans le bundle.
@Observable
final class CatalogStore {

    /// Le catalogue complet : les vehicules embarques **et** ceux appris de l'IA.
    private(set) var vehicles: [Vehicle] = []
    /// Nombre de vehicules livres avec l'app. Sert a distinguer l'acquis de l'appris.
    private(set) var embeddedCount = 0
    /// Identifiants des vehicules appris, pour les signaler dans le Spogdex.
    private(set) var learnedIDs: Set<String> = []
    private(set) var tiers: [RarityTier] = []
    private(set) var unknownTier: RarityTier = RarityTier(id: "unknown", rank: -1, points: 10, key: "rarity.unknown")
    private(set) var confidenceThreshold: Double = 0.8

    /// code pays -> code region
    private(set) var regionOfCountry: [String: String] = [:]
    /// Pays connus, tries par nom traduit dans la langue de l'utilisateur.
    private(set) var knownCountries: [String] = []

    private var tierByID: [String: RarityTier] = [:]
    private var matchIndex: [String: Vehicle] = [:]

    static let shared = CatalogStore()

    private init() { load() }

    // MARK: Chargement

    private func load() {
        let rarity: RarityFileBox = decode("rarity")
        tiers = rarity.tiers.sorted { $0.rank < $1.rank }
        tierByID = Dictionary(uniqueKeysWithValues: tiers.map { ($0.id, $0) })
        unknownTier = RarityTier(id: rarity.unknownID, rank: -1, points: rarity.unknownPoints, key: rarity.unknownKey)
        confidenceThreshold = rarity.threshold

        let markets: MarketFileBox = decode("markets")
        for (region, countries) in markets.regions {
            for country in countries { regionOfCountry[country] = region }
        }

        let catalog: VehicleFileBox = decode("vehicles")
        vehicles = catalog.vehicles
        embeddedCount = vehicles.count

        // Les vehicules appris rejoignent le catalogue au chargement : a partir de la,
        // rien ne les distingue des autres pour le rapprochement ou l'affichage.
        let learned = Self.loadLearned()
        learnedIDs = Set(learned.map(\.id))
        vehicles.append(contentsOf: learned)

        knownCountries = regionOfCountry.keys.sorted {
            countryName($0).localizedCaseInsensitiveCompare(countryName($1)) == .orderedAscending
        }

        buildMatchIndex()
    }

    private func decode<T: Decodable>(_ name: String) -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(T.self, from: data)
        else { fatalError("Catalogue introuvable ou illisible: \(name).json") }
        return value
    }

    // MARK: Apprentissage

    /// Fichier des vehicules appris. Il vit a cote du garage, dans les documents de
    /// l'utilisateur : c'est **sa** collection de decouvertes, pas une ressource de l'app.
    private static var learnedURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("learned_vehicles.json")
    }

    private static func loadLearned() -> [Vehicle] {
        guard let data = try? Data(contentsOf: learnedURL),
              let stored = try? JSONDecoder().decode([Vehicle].self, from: data)
        else { return [] }
        return stored
    }

    private func saveLearned() {
        let learned = vehicles.filter { learnedIDs.contains($0.id) }
        guard let data = try? JSONEncoder().encode(learned) else { return }
        try? data.write(to: Self.learnedURL, options: .atomic)
    }

    /// Enregistre une voiture que l'IA a su nommer et que le catalogue ignorait.
    ///
    /// C'est ce qui permet a l'app de **grandir avec son joueur** : la premiere Vios
    /// croisee a Hanoi entre au catalogue, et toutes les suivantes sont reconnues d'emblee,
    /// sans ecran de confirmation. Le catalogue embarque ne pourra jamais contenir toutes
    /// les voitures de tous les marches — celui-la si, un scan a la fois.
    ///
    /// La rarete reste **inconnue** : personne n'a calibre ce modele, et inventer un palier
    /// fausserait les points. Le palier `unknown` existe pour ca depuis le premier jour.
    @discardableResult
    func learn(make: String, model: String, body: String) -> Vehicle? {
        let make = make.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !make.isEmpty, !model.isEmpty else { return nil }

        // Deja connu sous un nom ou un autre : on ne cree pas de doublon.
        if let existing = match("\(make) \(model)") { return existing }

        let id = Self.slug("\(make) \(model)")
        guard !id.isEmpty, !vehicles.contains(where: { $0.id == id }) else {
            return vehicles.first { $0.id == id }
        }

        let vehicle = Vehicle(id: id, make: make, model: model,
                              body: CarBody(body).rawValue,
                              rarity: ["default": unknownTier.id],
                              aliases: [])
        vehicles.append(vehicle)
        learnedIDs.insert(id)
        addToIndex(vehicle)
        saveLearned()
        return vehicle
    }

    func isLearned(_ vehicleID: String) -> Bool { learnedIDs.contains(vehicleID) }

    /// Identifiant technique tire du nom : minuscules, tirets, sans accent.
    /// Meme forme que les identifiants ecrits a la main dans le catalogue.
    private static func slug(_ text: String) -> String {
        let normalized = normalize(text)
        return normalized.split(separator: " ").joined(separator: "-")
    }

    // MARK: Rarete

    func tier(_ id: String) -> RarityTier { tierByID[id] ?? unknownTier }

    /// Cascade : pays exact -> region -> repli mondial.
    func resolve(_ vehicle: Vehicle, in country: String) -> RarityResolution {
        if let id = vehicle.rarity[country] {
            return RarityResolution(tier: tier(id), source: .country(country))
        }
        if let region = regionOfCountry[country], let id = vehicle.rarity[region] {
            return RarityResolution(tier: tier(id), source: .region(region))
        }
        return RarityResolution(tier: tier(vehicle.rarity["default"] ?? "unknown"), source: .fallback)
    }

    // MARK: Rapprochement du texte libre renvoye par l'IA

    private func addToIndex(_ vehicle: Vehicle) {
        var keys = [Self.normalize(vehicle.fullName), Self.normalize(vehicle.model)]
        for alias in vehicle.aliases {
            keys.append(Self.normalize("\(vehicle.make) \(alias)"))
            keys.append(Self.normalize(alias))
        }
        keys.append(Self.stripNoise(Self.normalize(vehicle.fullName)))
        for key in keys where !key.isEmpty {
            if matchIndex[key] == nil { matchIndex[key] = vehicle }
        }
    }

    private func buildMatchIndex() {
        for vehicle in vehicles {
            var keys = [Self.normalize(vehicle.fullName), Self.normalize(vehicle.model)]
            for alias in vehicle.aliases {
                keys.append(Self.normalize("\(vehicle.make) \(alias)"))
                keys.append(Self.normalize(alias))
            }
            keys.append(Self.stripNoise(Self.normalize(vehicle.fullName)))
            for key in keys where !key.isEmpty {
                if matchIndex[key] == nil { matchIndex[key] = vehicle }
            }
        }
    }

    func match(_ text: String) -> Vehicle? {
        let target = Self.normalize(text)
        if let hit = matchIndex[target] { return hit }
        let loose = Self.stripNoise(target)
        if let hit = matchIndex[loose] { return hit }
        // Repli : la cle la plus longue presente comme mots entiers dans le texte.
        var best: (Int, Vehicle)?
        for (key, vehicle) in matchIndex where key.count >= 3 {
            guard Self.containsWord(key, in: target) else { continue }
            if best == nil || key.count > best!.0 { best = (key.count, vehicle) }
        }
        return best?.1
    }

    /// Propositions classees pour un texte libre, quand la confiance est trop faible
    /// pour creer la carte toute seule. Le rapprochement exact vient en tete, puis
    /// les vehicules qui partagent le plus de mots avec ce qu'a lu l'IA.
    func candidates(for text: String, limit: Int = 5) -> [Vehicle] {
        let words = Set(Self.normalize(text).split(separator: " ").map(String.init))
        guard !words.isEmpty else { return [] }

        var scored: [(Double, Vehicle)] = []
        for vehicle in vehicles {
            var keys = [vehicle.fullName] + vehicle.aliases.map { "\(vehicle.make) \($0)" }
            keys.append(vehicle.model)
            var best = 0.0
            for key in keys {
                let tokens = Set(Self.normalize(key).split(separator: " ").map(String.init))
                guard !tokens.isEmpty else { continue }
                let shared = Double(tokens.intersection(words).count)
                guard shared > 0 else { continue }
                // Rapport aux deux ensembles : "Clio" ne doit pas battre "Renault Clio"
                // sur la requete "Renault Clio IV".
                best = max(best, shared / Double(tokens.count) + shared / Double(words.count))
            }
            if best > 0 { scored.append((best, vehicle)) }
        }

        var ordered = scored.sorted { $0.0 > $1.0 }.map(\.1)
        if let exact = match(text), let index = ordered.firstIndex(of: exact) {
            ordered.remove(at: index)
            ordered.insert(exact, at: 0)
        } else if let exact = match(text) {
            ordered.insert(exact, at: 0)
        }
        return Array(ordered.prefix(limit))
    }

    /// Recherche manuelle, sur le nom affiche comme sur les alias de marche :
    /// un joueur qui tape "Golf GTI" ou un nom local doit tomber dessus.
    func search(_ query: String) -> [Vehicle] {
        let needle = Self.normalize(query)
        guard !needle.isEmpty else { return vehicles }
        return vehicles.filter { vehicle in
            let haystack = ([vehicle.fullName] + vehicle.aliases).map(Self.normalize).joined(separator: " ")
            return haystack.contains(needle)
        }
    }

    // MARK: Normalisation

    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
        let cleaned = folded.map { ch -> Character in
            (ch.isLetter && ch.isASCII) || ch.isNumber ? ch : " "
        }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    /// Retire les jetons de generation : chiffres romains, mk4, annees, codes chassis.
    static func stripNoise(_ normalized: String) -> String {
        let kept = normalized.split(separator: " ").filter { token -> Bool in
            let t = String(token)
            if t.range(of: "^mk\\d+$", options: .regularExpression) != nil { return false }
            if t.range(of: "^[ivx]{1,4}$", options: .regularExpression) != nil { return false }
            if t.range(of: "^(19|20)\\d{2}$", options: .regularExpression) != nil { return false }
            if t.range(of: "^[a-z]\\d{2,3}$", options: .regularExpression) != nil { return false }
            return true
        }
        return kept.joined(separator: " ")
    }

    static func containsWord(_ needle: String, in haystack: String) -> Bool {
        guard let range = haystack.range(of: needle) else { return false }
        let before = range.lowerBound == haystack.startIndex
            ? " " : haystack[haystack.index(before: range.lowerBound)]
        let after = range.upperBound == haystack.endIndex
            ? " " : haystack[range.upperBound]
        return before == " " && after == " "
    }

    /// Nom du pays traduit dans la langue de l'utilisateur. Jamais de liste ecrite a la main.
    func countryName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}

// MARK: - Boites de decodage (le JSON contient des cles de commentaire a ignorer)

private struct RarityFileBox: Decodable {
    let tiers: [RarityTier]
    let unknownID: String, unknownKey: String
    let unknownPoints: Int
    let threshold: Double

    private struct Unknown: Decodable { let id: String; let points: Int; let key: String }
    enum CodingKeys: String, CodingKey { case tiers, unknown, confidence_threshold }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tiers = try c.decode([RarityTier].self, forKey: .tiers)
        let u = try c.decode(Unknown.self, forKey: .unknown)
        unknownID = u.id; unknownPoints = u.points; unknownKey = u.key
        threshold = try c.decode(Double.self, forKey: .confidence_threshold)
    }
}

private struct MarketFileBox: Decodable {
    let regions: [String: [String]]
    let populated: [String]
}

private struct VehicleFileBox: Decodable {
    let version: Int
    let vehicles: [Vehicle]
}
