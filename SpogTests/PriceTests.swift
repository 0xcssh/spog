import Foundation
import Testing
@testable import Spog

/// La cote se trompe en silence de trois façons : un total qui additionne des devises
/// différentes, une fourchette fusionnée qui change d'ordre de grandeur à la lecture
/// (« 950–1,2 k€ »), et une réponse serveur absurde affichée telle quelle.
struct PriceTests {

    private func bracket(_ low: Int, _ high: Int, _ currency: String) -> PriceBracket {
        PriceBracket(low: low, high: high, currency: currency)
    }

    // MARK: Lecture de la réponse serveur

    @Test("Une fourchette valide est lue, arrondie, devise en majuscules")
    func validBracket() {
        let price = PriceBracket.from(low: 17_999.6, high: 24_000, currency: "eur")
        #expect(price == bracket(18_000, 24_000, "EUR"))
    }

    @Test("0/0, bornes inversées, devise absente ou mal formée : rien")
    func invalidBrackets() {
        #expect(PriceBracket.from(low: 0, high: 0, currency: "EUR") == nil)
        #expect(PriceBracket.from(low: 24_000, high: 18_000, currency: "EUR") == nil)
        #expect(PriceBracket.from(low: 18_000, high: 24_000, currency: "") == nil)
        #expect(PriceBracket.from(low: 18_000, high: 24_000, currency: nil) == nil)
        #expect(PriceBracket.from(low: 18_000, high: 24_000, currency: "EURO") == nil)
        #expect(PriceBracket.from(low: nil, high: 24_000, currency: "EUR") == nil)
    }

    // MARK: Valeur du garage

    @Test("Aucune carte cotée : pas de valeur, plutôt qu'un zéro")
    func noPricedCards() {
        #expect(GarageValue.compute([]) == nil)
    }

    @Test("La valeur est la somme des milieux de fourchette")
    func sumOfMidpoints() throws {
        let value = try #require(GarageValue.compute([bracket(18_000, 24_000, "EUR"),
                                                       bracket(8_000, 12_000, "EUR")]))
        #expect(value.currency == "EUR")
        #expect(value.total == 31_000)
        #expect(value.counted == 2)
        #expect(value.otherCurrencies.isEmpty)
    }

    @Test("Plusieurs devises : la majoritaire est sommée, les autres nommées, jamais converties")
    func majorityCurrency() throws {
        let value = try #require(GarageValue.compute([bracket(18_000, 24_000, "EUR"),
                                                       bracket(450_000, 600_000, "THB"),
                                                       bracket(500_000, 700_000, "THB"),
                                                       bracket(20_000, 30_000, "USD")]))
        #expect(value.currency == "THB")
        #expect(value.total == 1_125_000)
        #expect(value.counted == 2)
        #expect(Set(value.otherCurrencies) == ["EUR", "USD"])
    }

    @Test("À égalité de cartes, le choix ne dépend pas de l'ordre des prises")
    func tieIsStable() throws {
        let a = [bracket(10_000, 14_000, "EUR"), bracket(10_000, 14_000, "GBP")]
        let first = try #require(GarageValue.compute(a))
        let second = try #require(GarageValue.compute(a.reversed()))
        #expect(first == second)
    }

    // MARK: Fusion des fourchettes

    @Test("Même unité des deux côtés : elle n'est écrite qu'une fois")
    func mergeSharedTail() {
        #expect(PriceFormat.merge("18\u{202F}k€", "24\u{202F}k€") == "18–24\u{202F}k€")
        #expect(PriceFormat.merge("$18K", "$24K") == "$18–24K")
    }

    @Test("Ordres de grandeur différents : rien n'est retiré qui changerait la lecture")
    func mergeDifferentMagnitudes() {
        #expect(PriceFormat.merge("950\u{00A0}€", "1,2\u{00A0}k€") == "950\u{00A0}€ – 1,2\u{00A0}k€")
    }

    @Test("Une fourchette formatée contient ses deux bornes et une seule fois la devise")
    func formattedRange() {
        let text = PriceFormat.range(bracket(18_000, 24_000, "EUR"), locale: Locale(identifier: "fr_FR"))
        #expect(text.contains("18"))
        #expect(text.contains("24"))
        #expect(text.filter { $0 == "€" }.count == 1)
    }
}
