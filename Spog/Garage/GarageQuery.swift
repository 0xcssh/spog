import Foundation

/// Recherche, filtre et tri de la grille du garage. Sorti de la vue pour être testé : un
/// tri par valeur qui mélange les devises, ou une recherche qui rate « Citroën » tapé
/// « citroen », se trompe en silence.
struct GarageQuery: Equatable {

    enum Sort: String, CaseIterable, Identifiable {
        /// Les plus récentes d'abord : l'ordre d'origine du garage.
        case recent
        /// Les paliers les plus hauts d'abord, puis les plus récentes.
        case rarity
        /// Les cotes les plus hautes d'abord ; les cartes sans cote à la fin.
        case value

        var id: String { rawValue }

        /// Clé du libellé dans le catalogue de chaînes.
        var labelKey: String { "home.sort.\(rawValue)" }
    }

    var text: String = ""
    /// Identifiant du palier retenu, nil pour tous.
    var tierID: String? = nil
    var sort: Sort = .recent

    /// Aucun critère qui retire des cartes : sert à distinguer « garage vide » de
    /// « aucune carte ne correspond ».
    var isFiltering: Bool {
        tierID != nil || !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Les cartes à afficher, dans l'ordre choisi.
    /// - Parameter mainCurrency: devise de la valeur du garage. Le tri par valeur classe
    ///   d'abord les cartes cotées dans cette devise : comparer 500 000 bahts à 20 000 €
    ///   ferait passer une citadine thaïlandaise devant une sportive française.
    func apply(to cards: [CardData], mainCurrency: String? = nil) -> [CardData] {
        let needle = text.trimmingCharacters(in: .whitespaces)
        let kept = cards.filter { card in
            if let tierID, card.tier.id != tierID { return false }
            guard !needle.isEmpty else { return true }
            // Insensible à la casse et aux accents : « citroen » trouve « Citroën ».
            return card.vehicle.fullName.localizedStandardContains(needle)
        }
        switch sort {
        case .recent:
            return kept.sorted { $0.caughtAt > $1.caughtAt }
        case .rarity:
            return kept.sorted { a, b in
                if a.tier.rank != b.tier.rank { return a.tier.rank > b.tier.rank }
                return a.caughtAt > b.caughtAt
            }
        case .value:
            return kept.sorted { a, b in
                let ra = Self.valueRank(a, mainCurrency), rb = Self.valueRank(b, mainCurrency)
                if ra != rb { return ra < rb }
                let ma = a.price?.midpoint ?? 0, mb = b.price?.midpoint ?? 0
                if ma != mb { return ma > mb }
                return a.caughtAt > b.caughtAt
            }
        }
    }

    /// Emplacements vides à poser après les cartes : ils complètent la dernière rangée de
    /// la grille à deux colonnes, et montrent au moins quatre cases au total — avec une
    /// seule carte, la grille doit déjà ressembler à un garage qui attend d'être rempli.
    static func emptySlots(after count: Int) -> Int {
        max(4 - count, count % 2)
    }

    /// 0 : cotée dans la devise principale ; 1 : cotée dans une autre ; 2 : sans cote.
    private static func valueRank(_ card: CardData, _ mainCurrency: String?) -> Int {
        guard let price = card.price else { return 2 }
        return price.currency == mainCurrency || mainCurrency == nil ? 0 : 1
    }
}
