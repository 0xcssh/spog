import Foundation
import Testing
@testable import Spog

/// Le garage est un fichier JSON sur l'appareil, écrit par toutes les versions passées
/// de l'app. Une nouvelle propriété de `Catch` qui le rendrait illisible effacerait la
/// collection du joueur à la mise à jour, sans un mot.
struct GarageCompatibilityTests {

    /// Une prise telle que l'écrivait l'app avant l'identifiant de photo d'entraînement.
    private let legacy = """
    [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","vehicleID":"peugeot-3008","serial":1,
      "caughtAt":780000000,"countryCode":"FR","verified":true,"paint":11843774,"hasShot":true}]
    """

    @Test("Un garage d'avant l'entraînement se relit, sans photo d'entraînement")
    func legacyGarageDecodes() throws {
        let catches = try JSONDecoder().decode([Catch].self, from: Data(legacy.utf8))
        #expect(catches.count == 1)
        #expect(catches[0].vehicleID == "peugeot-3008")
        #expect(catches[0].sampleID == nil)
    }

    @Test("L'identifiant de photo d'entraînement survit à l'aller-retour sur le disque")
    func sampleIDRoundTrips() throws {
        var catches = try JSONDecoder().decode([Catch].self, from: Data(legacy.utf8))
        catches[0].sampleID = "11111111-2222-3333-4444-555555555555"
        let reread = try JSONDecoder().decode([Catch].self, from: JSONEncoder().encode(catches))
        #expect(reread[0].sampleID == "11111111-2222-3333-4444-555555555555")
    }

    @Test("Un garage d'avant la cote se relit, sans cote")
    func legacyGarageHasNoPrice() throws {
        let catches = try JSONDecoder().decode([Catch].self, from: Data(legacy.utf8))
        #expect(catches[0].price == nil)
    }

    @Test("La cote survit à l'aller-retour sur le disque, avec sa devise")
    func priceRoundTrips() throws {
        var catches = try JSONDecoder().decode([Catch].self, from: Data(legacy.utf8))
        catches[0].price = PriceBracket(low: 18_000, high: 24_000, currency: "EUR")
        let reread = try JSONDecoder().decode([Catch].self, from: JSONEncoder().encode(catches))
        #expect(reread[0].price == PriceBracket(low: 18_000, high: 24_000, currency: "EUR"))
    }

    /// Une prise telle que l'écrit cette version : la relire ne doit pas dépendre de
    /// l'ordre des clés ni de la présence des autres champs facultatifs.
    @Test("Une prise cotée écrite à la main se relit")
    func pricedCatchDecodes() throws {
        let json = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","vehicleID":"peugeot-3008","serial":1,
          "caughtAt":780000000,"countryCode":"TH","verified":true,"paint":11843774,"hasShot":false,
          "price":{"low":450000,"high":600000,"currency":"THB"}}]
        """
        let catches = try JSONDecoder().decode([Catch].self, from: Data(json.utf8))
        #expect(catches[0].price?.currency == "THB")
        #expect(catches[0].price?.midpoint == 525_000)
    }
}
