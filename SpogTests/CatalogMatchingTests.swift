import Testing
@testable import Spog

/// Le rapprochement du texte libre renvoyé par l'IA avec le catalogue.
///
/// L'IA écrit « Renault Clio IV », « VW Golf mk7 », « Peugeot 208 2019 ». Chacune de
/// ces formes doit retrouver la bonne fiche, sinon l'app crée un doublon appris à côté
/// d'un modèle qu'elle connaissait déjà — et le Spogdex se remplit de faux jumeaux.
struct CatalogMatchingTests {

    private let catalog = CatalogStore.shared

    // MARK: Normalisation

    @Test("Les accents, la casse et la ponctuation ne comptent pas")
    func normalizeFolds() {
        #expect(CatalogStore.normalize("Citroën C3") == "citroen c3")
        #expect(CatalogStore.normalize("MERCEDES-BENZ  Classe A") == "mercedes benz classe a")
        #expect(CatalogStore.normalize("  Renault   Clio  ") == "renault clio")
    }

    @Test("Les jetons de génération disparaissent")
    func stripsGenerationNoise() {
        // Ce que l'IA ajoute spontanément et qui ne distingue pas un modèle d'un autre.
        #expect(CatalogStore.stripNoise("volkswagen golf mk7") == "volkswagen golf")
        #expect(CatalogStore.stripNoise("renault clio iv") == "renault clio")
        #expect(CatalogStore.stripNoise("peugeot 208 2019") == "peugeot 208")
        #expect(CatalogStore.stripNoise("bmw serie 3 e90") == "bmw serie 3")
    }

    @Test("Le nettoyage ne mange pas un nom de modèle qui ressemble à du bruit")
    func stripNoiseKeepsRealNames() {
        // « 208 » est un modèle, pas une année. « c3 » est un modèle, pas un code châssis
        // — mais il a la forme d'un code châssis, donc il tombe. C'est assumé : le
        // rapprochement exact passe avant le nettoyage, qui n'est qu'un repli.
        #expect(CatalogStore.stripNoise("peugeot 208").contains("208"))
        #expect(catalog.match("Citroën C3")?.id == "citroen-c3")
    }

    // MARK: Rapprochement

    @Test("Un nom complet exact trouve sa fiche")
    func exactNameMatches() {
        #expect(catalog.match("Renault Clio")?.id == "renault-clio")
        #expect(catalog.match("renault clio")?.id == "renault-clio")
    }

    @Test("Les formes que l'IA produit vraiment retrouvent la bonne fiche")
    func realWorldFormsMatch() {
        for text in ["Renault Clio IV", "renault clio 2019", "RENAULT CLIO"] {
            #expect(catalog.match(text)?.id == "renault-clio", "échec sur « \(text) »")
        }
    }

    @Test("Un alias de marché retrouve la fiche du modèle")
    func aliasMatches() {
        // Le catalogue porte des alias parce qu'un même modèle change de nom
        // d'un pays à l'autre. Si les alias cassent, l'app apprend un doublon.
        let withAlias = catalog.vehicles.first { !$0.aliases.isEmpty }
        guard let car = withAlias, let alias = car.aliases.first else {
            Issue.record("aucun véhicule du catalogue ne porte d'alias")
            return
        }
        #expect(catalog.match("\(car.make) \(alias)")?.id == car.id)
    }

    @Test("Un texte qui ne ressemble à rien ne trouve rien")
    func nonsenseMatchesNothing() {
        #expect(catalog.match("") == nil)
        #expect(catalog.match("xyzzy plover") == nil)
    }

    // MARK: Propositions et recherche

    @Test("Le rapprochement exact arrive en tête des propositions")
    func exactCandidateComesFirst() {
        let candidates = catalog.candidates(for: "Renault Clio", limit: 5)
        #expect(candidates.first?.id == "renault-clio")
        #expect(candidates.count <= 5)
    }

    @Test("Le modèle complet bat le modèle seul")
    func fullNameBeatsBareModel() {
        // « Clio » seule ne doit pas passer devant « Renault Clio » sur cette requête :
        // c'est l'écran de confirmation qui s'en sert, et la première ligne est celle
        // que le joueur valide sans réfléchir.
        let candidates = catalog.candidates(for: "Renault Clio IV", limit: 3)
        #expect(candidates.first?.make == "Renault")
    }

    @Test("La recherche manuelle trouve par le nom comme par l'alias")
    func searchFindsByNameAndAlias() {
        #expect(catalog.search("clio").contains { $0.id == "renault-clio" })
        #expect(catalog.search("CLIO").contains { $0.id == "renault-clio" })
        // Une recherche vide rend tout le catalogue plutôt que rien : c'est ce que
        // la feuille de choix affiche à l'ouverture.
        #expect(catalog.search("").count == catalog.vehicles.count)
    }

    // MARK: Intégrité du catalogue embarqué

    @Test("Aucun identifiant en double")
    func idsAreUnique() {
        // Un doublon d'identifiant fait que deux fiches se disputent la même carte :
        // le garage en montre une, le Spogdex l'autre.
        var seen = Set<String>()
        for car in catalog.vehicles {
            #expect(seen.insert(car.id).inserted, "identifiant en double : \(car.id)")
        }
    }

    @Test("Chaque véhicule embarqué se retrouve par son propre nom")
    func everyVehicleFindsItself() {
        // Le test le plus bête et le plus utile : si une fiche ne se retrouve pas
        // elle-même, l'app apprendra un doublon la première fois qu'on la croise.
        for car in catalog.vehicles.prefix(catalog.embeddedCount) {
            #expect(catalog.match(car.fullName) != nil, "introuvable : \(car.fullName)")
        }
    }

    @Test("Chaque carrosserie déclarée est une carrosserie connue")
    func everyBodyIsKnown() {
        // La carrosserie pilote la géométrie 3D : une valeur inconnue donne
        // une carte sans voiture dessus.
        for car in catalog.vehicles {
            #expect(CarBody(car.body).rawValue == car.body,
                    "carrosserie inconnue « \(car.body) » pour \(car.id)")
        }
    }
}
