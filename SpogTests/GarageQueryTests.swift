import Foundation
import Testing
@testable import Spog

/// La recherche, le filtre et le tri de l'écran d'accueil. Ils se trompent en silence :
/// une recherche qui rate « Citroën » tapé sans tréma, un tri par valeur qui fait passer
/// des bahts devant des euros, des emplacements vides qui laissent une rangée boiteuse.
struct GarageQueryTests {

    private let common = RarityTier(id: "common", rank: 0, points: 5, key: "rarity.common")
    private let rare = RarityTier(id: "rare", rank: 3, points: 60, key: "rarity.rare")

    private func card(_ make: String, _ model: String, tier: RarityTier,
                      daysAgo: Double, price: PriceBracket? = nil) -> CardData {
        CardData(id: UUID(),
                 vehicle: Vehicle(id: "\(make)-\(model)".lowercased(), make: make, model: model,
                                  body: "hatchback", rarity: [:], aliases: []),
                 tier: tier, serial: 1,
                 caughtAt: Date(timeIntervalSince1970: 1_000_000_000 - daysAgo * 86_400),
                 placeName: "France", verified: true, paint: 0xFFFFFF, price: price)
    }

    private var sample: [CardData] {
        [card("Citroën", "2CV", tier: rare, daysAgo: 3,
              price: PriceBracket(low: 8_000, high: 12_000, currency: "EUR")),
         card("Renault", "Clio", tier: common, daysAgo: 1,
              price: PriceBracket(low: 9_000, high: 13_000, currency: "EUR")),
         card("Toyota", "Yaris", tier: common, daysAgo: 2,
              price: PriceBracket(low: 400_000, high: 500_000, currency: "THB")),
         card("Peugeot", "208", tier: common, daysAgo: 0)]
    }

    @Test("Par défaut : tout, les plus récentes d'abord")
    func defaultIsRecent() {
        let shown = GarageQuery().apply(to: sample)
        #expect(shown.map(\.vehicle.model) == ["208", "Clio", "Yaris", "2CV"])
    }

    @Test("La recherche ignore la casse et les accents")
    func searchIgnoresDiacritics() {
        let shown = GarageQuery(text: "citroen").apply(to: sample)
        #expect(shown.map(\.vehicle.model) == ["2CV"])
    }

    @Test("Le filtre ne garde que le palier choisi")
    func tierFilter() {
        let shown = GarageQuery(tierID: "rare").apply(to: sample)
        #expect(shown.map(\.vehicle.model) == ["2CV"])
    }

    @Test("Tri par rareté : le palier d'abord, puis la date")
    func sortByRarity() {
        let shown = GarageQuery(sort: .rarity).apply(to: sample)
        #expect(shown.map(\.vehicle.model) == ["2CV", "208", "Clio", "Yaris"])
    }

    @Test("Tri par cote : la devise principale d'abord, les cartes sans cote à la fin")
    func sortByValueKeepsCurrenciesApart() {
        let shown = GarageQuery(sort: .value).apply(to: sample, mainCurrency: "EUR")
        // 500 000 bahts ne passent pas devant 11 000 € : ils ne sont pas comparables.
        #expect(shown.map(\.vehicle.model) == ["Clio", "2CV", "Yaris", "208"])
    }

    @Test("Un filtre actif se signale, une recherche faite d'espaces non")
    func isFiltering() {
        #expect(!GarageQuery().isFiltering)
        #expect(!GarageQuery(text: "   ").isFiltering)
        #expect(GarageQuery(tierID: "rare").isFiltering)
    }

    @Test("Les emplacements vides complètent la rangée, quatre cases au moins")
    func emptySlots() {
        #expect(GarageQuery.emptySlots(after: 0) == 4)
        #expect(GarageQuery.emptySlots(after: 1) == 3)
        #expect(GarageQuery.emptySlots(after: 3) == 1)
        #expect(GarageQuery.emptySlots(after: 4) == 0)
        #expect(GarageQuery.emptySlots(after: 7) == 1)
        #expect(GarageQuery.emptySlots(after: 8) == 0)
    }
}
