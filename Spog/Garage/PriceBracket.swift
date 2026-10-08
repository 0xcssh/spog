import Foundation

/// Cote d'occasion d'une prise. **Jamais un chiffre unique** : la photo ne contient ni le
/// kilométrage, ni le carnet d'entretien, ni l'état mécanique, et un montant exact serait
/// cru sur parole puis démenti par le premier joueur qui connaît sa voiture.
///
/// Elle est **figée à la capture**, comme le pays et la date : la recalculer coûterait un
/// appel à chaque ouverture de fiche, pour un chiffre qui changerait sans raison visible.
struct PriceBracket: Equatable, Codable {
    let low: Int
    let high: Int
    /// Code ISO 4217, celui du pays de la prise, décidé par le serveur. L'app ne convertit
    /// rien : une somme convertie à un taux inconnu serait une invention de plus.
    let currency: String

    /// Ce que la valeur du garage additionne : le milieu, faute de mieux savoir.
    var midpoint: Double { (Double(low) + Double(high)) / 2 }

    /// Fourchette lue du serveur, ou nil. Le serveur écarte déjà les fourchettes absurdes ;
    /// on revérifie parce qu'une app reste en service longtemps après qu'un serveur a
    /// changé, et qu'afficher « 0 € » serait pire que ne rien afficher du tout.
    static func from(low: Double?, high: Double?, currency: String?) -> PriceBracket? {
        guard let low, let high, let currency,
              low >= 1, high >= low, high < 1e15,
              currency.count == 3, currency.allSatisfy({ $0.isASCII && $0.isLetter })
        else { return nil }
        return PriceBracket(low: Int(low.rounded()), high: Int(high.rounded()),
                            currency: currency.uppercased())
    }
}

/// Valeur estimée d'un garage : la somme des milieux de fourchette, dans une seule devise.
struct GarageValue: Equatable {
    let currency: String
    let total: Double
    /// Cartes cotées comptées dans le total.
    let counted: Int
    /// Autres devises présentes, jamais additionnées : un joueur qui voyage a des cartes
    /// en bahts et en euros, et les sommer demanderait un taux de change que l'app n'a pas.
    let otherCurrencies: [String]

    /// Nil quand aucune carte n'est cotée : mieux vaut ne rien montrer qu'un « 0 € ».
    ///
    /// La devise retenue est celle qui compte **le plus de cartes** (à égalité, le total le
    /// plus élevé, puis l'ordre alphabétique pour que l'affichage ne saute pas d'un
    /// lancement à l'autre). C'est le garage « de chez soi », le reste est du voyage.
    static func compute(_ prices: [PriceBracket]) -> GarageValue? {
        let groups = Dictionary(grouping: prices, by: \.currency)
        let ranked: [(code: String, count: Int, total: Double)] = groups.map { code, items in
            (code: code, count: items.count, total: items.reduce(0.0) { $0 + $1.midpoint })
        }
        let sorted = ranked.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            if a.total != b.total { return a.total > b.total }
            return a.code < b.code
        }
        guard let main = sorted.first else { return nil }
        return GarageValue(currency: main.code, total: main.total, counted: main.count,
                           otherCurrencies: sorted.dropFirst().map { $0.code })
    }
}

/// Mise en forme des montants : dans la devise de la prise, sans décimales, abrégée
/// (« 18–24 k€ ») parce qu'une cote à l'euro près afficherait une précision qu'elle n'a pas.
enum PriceFormat {

    /// Un montant abrégé dans sa devise : « 18 k€ », « $24K », « ¥3.5M ».
    static func amount(_ value: Double, currency: String, locale: Locale = .autoupdatingCurrent) -> String {
        let style = FloatingPointFormatStyle<Double>.Currency(code: currency, locale: locale)
            .notation(.compactName)
            .precision(.significantDigits(1...3))
        return value.formatted(style)
    }

    /// La fourchette d'une prise : « 18–24 k€ ».
    static func range(_ price: PriceBracket, locale: Locale = .autoupdatingCurrent) -> String {
        merge(amount(Double(price.low), currency: price.currency, locale: locale),
              amount(Double(price.high), currency: price.currency, locale: locale))
    }

    /// Le total du garage, précédé de « ≈ » : c'est une somme d'estimations.
    static func total(_ value: GarageValue, locale: Locale = .autoupdatingCurrent) -> String {
        "≈ " + amount(value.total, currency: value.currency, locale: locale)
    }

    /// Réunit deux montants formatés en une fourchette, sans répéter l'unité quand les deux
    /// la partagent : « 18 k€ » et « 24 k€ » donnent « 18–24 k€ », « $18K » et « $24K »
    /// donnent « $18–24K ».
    ///
    /// On ne fusionne la fin que si elle est **identique des deux côtés** : « 950 € » et
    /// « 1,2 k€ » donneraient sinon « 950–1,2 k€ », qui se lit 950 k€. Le format exact
    /// dépend de la langue de l'iPhone (espace insécable, symbole avant ou après), d'où une
    /// règle sur les caractères plutôt qu'un gabarit par langue.
    static func merge(_ low: String, _ high: String) -> String {
        let lowHead = head(low), highHead = head(high)
        let lowTail = tail(low), highTail = tail(high)
        let sharedTail = lowTail == highTail && !lowTail.isEmpty
        let sharedHead = lowHead == highHead && !lowHead.isEmpty
        guard sharedTail || sharedHead else { return "\(low) – \(high)" }
        let left = sharedTail ? String(low.dropLast(lowTail.count)) : low
        let right = sharedHead ? String(high.dropFirst(highHead.count)) : high
        return "\(left)–\(right)"
    }

    /// Ce qui précède le premier chiffre (« $ », « CHF » et son espace).
    private static func head(_ text: String) -> String {
        String(text.prefix { !$0.isNumber })
    }

    /// Ce qui suit le dernier chiffre (« k€ » et son espace, « K »).
    private static func tail(_ text: String) -> String {
        String(text.reversed().prefix { !$0.isNumber }.reversed())
    }
}
