import Foundation
import Testing
@testable import Spog

/// Restauration des cartes par le compte Apple : la fusion décide de ce qui apparaît dans le
/// garage d'un nouvel iPhone. Une erreur ici duplique des cartes ou écrase celles qui ont
/// une photo, sans que rien ne le signale.
struct GarageRestoreTests {

    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func local(_ id: UUID = UUID(), serial: Int, vehicle: String = "peugeot-3008",
                       paint: UInt32 = 0xB4231F, hasShot: Bool = true) -> Catch {
        Catch(id: id, vehicleID: vehicle, serial: serial, caughtAt: base, countryCode: "FR",
              verified: true, paint: paint, hasShot: hasShot)
    }

    private func remote(_ id: UUID = UUID(), vehicle: String = "renault-clio", minutes: Double = 0,
                        serial: Int? = nil, paint: Int? = nil, price: RemoteCatch.Price? = nil,
                        located: Bool? = true, firstSpot: Bool? = false, scan: String? = nil) -> RemoteCatch {
        let date = ISO8601DateFormatter.withFractions.string(from: base.addingTimeInterval(minutes * 60))
        return RemoteCatch(id: id.uuidString.lowercased(), vehicle_id: vehicle, country: "FR", caught_at: date,
                           first_spot: firstSpot, location_verified: located, scan_id: scan,
                           serial: serial, paint: paint, price: price)
    }

    @Test("Une carte déjà présente n'est pas dupliquée, et la version locale gagne")
    func localWins() {
        let id = UUID()
        let mine = local(id, serial: 3, vehicle: "peugeot-3008", paint: 0x1E4FA3)
        let merged = GarageRestore.merged(local: [mine],
                                          remote: [remote(id, vehicle: "renault-clio", serial: 9, paint: 0x17171B)])
        #expect(merged.count == 1)
        #expect(merged[0].vehicleID == "peugeot-3008")
        #expect(merged[0].serial == 3)
        #expect(merged[0].paint == 0x1E4FA3)
        #expect(merged[0].hasShot)
    }

    @Test("Une carte en double dans la réponse n'est ajoutée qu'une fois")
    func remoteDuplicatesCollapse() {
        let id = UUID()
        let merged = GarageRestore.merged(local: [], remote: [remote(id, serial: 1), remote(id, serial: 2)])
        #expect(merged.count == 1)
    }

    @Test("Une carte restaurée : synchronisée, sans photo, avec ce que le serveur sait d'elle")
    func restoredFields() {
        let scan = UUID().uuidString.lowercased()
        let merged = GarageRestore.merged(local: [], remote: [
            remote(serial: 4, paint: 0x1F5F45, price: RemoteCatch.Price(low: 18_000, high: 24_000, currency: "EUR"),
                   located: true, firstSpot: true, scan: scan)
        ])
        let item = merged[0]
        #expect(item.synced == true)
        #expect(item.hasShot == false)
        #expect(item.shot == nil)
        #expect(item.firstSpot == true)
        #expect(item.verified)
        #expect(item.scanID == scan)
        #expect(item.serial == 4)
        #expect(item.paint == 0x1F5F45)
        #expect(item.price == PriceBracket(low: 18_000, high: 24_000, currency: "EUR"))
    }

    @Test("Sans numéro du serveur : à la suite des numéros connus, dans l'ordre des prises")
    func serialsContinue() {
        let early = UUID(), late = UUID()
        let merged = GarageRestore.merged(local: [local(serial: 1), local(serial: 5)], remote: [
            remote(late, minutes: 30),
            remote(minutes: 10, serial: 7),
            remote(early, minutes: 0),
        ])
        let serial = { (id: UUID) in merged.first { $0.id == id }?.serial }
        #expect(merged.count == 5)
        #expect(serial(early) == 8)
        #expect(serial(late) == 9)
        #expect(Set(merged.map(\.serial)).count == merged.count)
    }

    @Test("Sans teinte du serveur : une teinte de la palette, la même à chaque restauration")
    func fallbackPaintIsStable() {
        let id = UUID()
        let first = GarageRestore.merged(local: [], remote: [remote(id)])[0].paint
        let again = GarageRestore.merged(local: [], remote: [remote(id, paint: -1)])[0].paint
        #expect(CarPaint.palette.contains(first))
        #expect(first == again)
        #expect(first == GarageRestore.fallbackPaint(for: id))
    }

    @Test("Les teintes de repli se répartissent sur la palette")
    func fallbackPaintSpreads() {
        let paints = Set((0..<200).map { _ in GarageRestore.fallbackPaint(for: UUID()) })
        #expect(paints.count > CarPaint.palette.count / 2)
    }

    @Test("Une prise supprimée sur l'appareil ne revient pas")
    func removedStayRemoved() {
        let gone = UUID()
        let merged = GarageRestore.merged(local: [], remote: [remote(gone), remote()], excluding: [gone])
        #expect(merged.count == 1)
        #expect(merged[0].id != gone)
    }

    @Test("Identifiant ou date illisible : la carte est ignorée, pas tout le garage")
    func malformedSkipped() {
        let bad = RemoteCatch(id: "pas-un-uuid", vehicle_id: "renault-clio", country: "FR",
                              caught_at: "2026-10-01T09:30:00.000Z", first_spot: nil, location_verified: nil,
                              scan_id: nil, serial: nil, paint: nil, price: nil)
        let noDate = RemoteCatch(id: UUID().uuidString, vehicle_id: "renault-clio", country: "FR",
                                 caught_at: "hier", first_spot: nil, location_verified: nil,
                                 scan_id: nil, serial: nil, paint: nil, price: nil)
        #expect(GarageRestore.merged(local: [], remote: [bad, noDate, remote()]).count == 1)
    }

    @Test("Un modèle inconnu du catalogue est gardé, sans carte affichable")
    func unknownVehicleKept() {
        let merged = GarageRestore.merged(local: [], remote: [remote(vehicle: "modele-pas-encore-au-catalogue")])
        #expect(merged.count == 1)
    }

    @Test("Réponse garage d'aujourd'hui : tous les champs se décodent")
    func decodesFullResponse() throws {
        let json = """
        {"catches":[{"id":"6f9619ff-8b86-d011-b42d-00c04fc964ff","vehicle_id":"porsche-macan","country":"FR",
          "caught_at":"2026-10-01T09:30:00.000Z","tier":"rare","points":150,"first_spot":true,
          "location_verified":true,"vehicle_verified":true,"scan_id":"0b6e1b8e-3f7a-4c55-9d2c-1a2b3c4d5e6f",
          "serial":7,"paint":1985418,"price":{"low":21000,"high":26000,"currency":"EUR"}}]}
        """
        let garage = try JSONDecoder().decode(RemoteGarage.self, from: Data(json.utf8))
        let item = try #require(garage.catches.first)
        #expect(item.serial == 7)
        #expect(item.paint == 0x1E4B8A)
        #expect(item.caughtAt != nil)
        let restored = GarageRestore.merged(local: [], remote: garage.catches)[0]
        #expect(restored.id == UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        #expect(restored.price?.currency == "EUR")
    }

    @Test("Réponse garage d'une prise d'avant la migration : champs nuls ou absents")
    func decodesLegacyResponse() throws {
        let json = """
        {"catches":[
          {"id":"6f9619ff-8b86-d011-b42d-00c04fc964ff","vehicle_id":"renault-clio","country":"FR",
           "caught_at":"2026-10-01T09:30:00.000Z","tier":"common","points":10,"first_spot":false,
           "location_verified":false,"vehicle_verified":false,"scan_id":null,"serial":null,"paint":null,"price":null},
          {"id":"7f9619ff-8b86-d011-b42d-00c04fc964ff","vehicle_id":"renault-clio","country":"FR",
           "caught_at":"2026-10-02T09:30:00Z","tier":"common","points":10,"first_spot":false,
           "location_verified":true,"vehicle_verified":false}
        ]}
        """
        let garage = try JSONDecoder().decode(RemoteGarage.self, from: Data(json.utf8))
        #expect(garage.catches.count == 2)
        let restored = GarageRestore.merged(local: [], remote: garage.catches)
        #expect(restored.map(\.serial) == [1, 2])
        #expect(restored.allSatisfy { $0.price == nil && CarPaint.palette.contains($0.paint) })
    }
}
