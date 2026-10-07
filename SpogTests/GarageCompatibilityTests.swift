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
}
