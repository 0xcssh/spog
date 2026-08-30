import Testing
@testable import Spog

/// La cascade de rareté : pays exact, puis région, puis repli mondial.
///
/// C'est elle qui décide des points d'une prise, donc du classement. Elle se trompe
/// en silence : une Clio annoncée « légendaire » en France ne fait planter personne,
/// elle fausse simplement tout le jeu.
struct RarityTests {

    private let catalog = CatalogStore.shared

    private func vehicle(rarity: [String: String]) -> Vehicle {
        Vehicle(id: "test-vehicle", make: "Test", model: "Vehicle",
                body: "sedan", rarity: rarity, aliases: [])
    }

    @Test("Le pays exact l'emporte sur la région")
    func countryBeatsRegion() {
        // La France appartient à EU_WEST : les deux clés répondent, une seule doit gagner.
        let car = vehicle(rarity: ["FR": "common", "EU_WEST": "rare", "default": "exotic"])
        let resolved = catalog.resolve(car, in: "FR")
        #expect(resolved.tier.id == "common")
        if case .country(let code) = resolved.source { #expect(code == "FR") }
        else { Issue.record("la source devrait être le pays, pas \(resolved.source)") }
    }

    @Test("La région prend le relais quand le pays est muet")
    func regionBeatsDefault() {
        let car = vehicle(rarity: ["EU_WEST": "rare", "default": "exotic"])
        let resolved = catalog.resolve(car, in: "FR")
        #expect(resolved.tier.id == "rare")
        if case .region(let code) = resolved.source { #expect(code == "EU_WEST") }
        else { Issue.record("la source devrait être la région, pas \(resolved.source)") }
    }

    @Test("Le repli mondial sert quand rien d'autre ne répond")
    func fallsBackToDefault() {
        let car = vehicle(rarity: ["default": "exotic"])
        let resolved = catalog.resolve(car, in: "FR")
        #expect(resolved.tier.id == "exotic")
        if case .fallback = resolved.source {} else {
            Issue.record("la source devrait être le repli, pas \(resolved.source)")
        }
    }

    @Test("Un pays inconnu du découpage retombe sur le repli, pas sur une région voisine")
    func unknownCountryFallsBack() {
        let car = vehicle(rarity: ["EU_WEST": "rare", "default": "exotic"])
        // ZZ n'existe dans aucune région : la clé EU_WEST ne doit pas s'appliquer.
        #expect(catalog.resolve(car, in: "ZZ").tier.id == "exotic")
    }

    @Test("Une rareté vide donne le palier inconnu, jamais un palier inventé")
    func emptyRarityIsUnknown() {
        // C'est le cas des véhicules appris de l'IA : personne ne les a calibrés,
        // et leur attribuer un palier au hasard fausserait les points.
        let resolved = catalog.resolve(vehicle(rarity: [:]), in: "FR")
        #expect(resolved.tier.id == catalog.unknownTier.id)
    }

    @Test("La France est bien rattachée à l'Europe de l'Ouest")
    func franceIsInWesternEurope() {
        // Le marché de départ : si ce rattachement saute, toutes les raretés
        // françaises calibrées par région basculent d'un coup sur le repli mondial.
        #expect(catalog.regionOfCountry["FR"] == "EU_WEST")
        #expect(catalog.regionOfCountry["US"] == "NA")
    }

    @Test("Chaque véhicule du catalogue tombe sur un palier déclaré")
    func everyVehicleResolvesToADeclaredTier() {
        // Une rareté qui pointe vers un palier absent de rarity.json retombe
        // silencieusement sur « inconnu » : la carte vaut alors 10 points au lieu
        // des 900 annoncés, et rien dans l'app ne le signale. Ici, si.
        let declared = Set(catalog.tiers.map(\.id))
        for car in catalog.vehicles {
            let tier = catalog.resolve(car, in: "FR").tier
            #expect(declared.contains(tier.id) || tier.id == catalog.unknownTier.id,
                    "palier inconnu « \(tier.id) » pour \(car.id)")
            #expect(tier.points > 0, "palier sans points pour \(car.id)")
        }
    }
}
