import Testing
import Foundation
@testable import Spog

/// La quête du jour.
///
/// Elle promet une chose : **rouvrir l'app ne change pas l'objectif**. Sans cette
/// garantie, un joueur qui tombe sur « une voiture exotique » ferme et rouvre jusqu'à
/// obtenir « trois prises », et la quête ne vaut plus rien.
///
/// La faute d'origine était `hashValue`, resalé à chaque lancement du processus. Elle
/// ne se voyait pas en une seule exécution : c'est pour ça que les tests ci-dessous
/// épinglent l'empreinte elle-même sur des valeurs connues, et pas seulement sa
/// constance à l'intérieur d'un test.
struct QuestTests {

    private let day = Date(timeIntervalSince1970: 1_756_512_000)  // 30 août 2025

    // MARK: L'empreinte

    @Test("L'empreinte est bien FNV-1a, épinglée sur ses vecteurs connus")
    func hashMatchesKnownVectors() {
        // Vecteurs publics de FNV-1a 64 bits. Une empreinte tirée du processus ne peut
        // pas les satisfaire : c'est la vérification qui aurait attrapé la faute.
        #expect(stableHash("") == 0xCBF2_9CE4_8422_2325)
        #expect(stableHash("a") == 0xAF63_DC4C_8601_EC8C)
        #expect(stableHash("foobar") == 0x8594_4171_F739_67E8)
        #expect(stableHash("hello") == 0xA430_D846_80AA_BD0B)
    }

    @Test("Deux entrées différentes donnent deux empreintes différentes")
    func hashSeparatesInputs() {
        #expect(stableHash("suv") != stableHash("sedan"))
        #expect(stableHash("suv,sedan") != stableHash("sedan,suv"))
    }

    // MARK: La quête

    @Test("Le même jour, le même pays et les mêmes goûts donnent la même quête")
    func questIsStableForTheDay() {
        let a = QuestFactory.quest(for: day, country: "FR", favourites: ["suv"])
        let b = QuestFactory.quest(for: day, country: "FR", favourites: ["suv"])
        #expect(a.id == b.id)
        #expect(a.title == b.title)
        #expect(a.reward == b.reward)
    }

    @Test("L'heure de la journée ne change pas la quête")
    func questIgnoresTimeOfDay() {
        // Le calcul passe par un numéro de jour : jouer le matin ou le soir doit
        // donner le même objectif, sinon la quête change en cours de journée.
        let morning = Date(timeIntervalSince1970: 1_756_512_000 + 3_600)
        let evening = Date(timeIntervalSince1970: 1_756_512_000 + 20 * 3_600)
        #expect(QuestFactory.quest(for: morning, country: "FR").id
                == QuestFactory.quest(for: evening, country: "FR").id)
    }

    @Test("L'ordre des goûts déclarés ne change pas la quête")
    func questIgnoresFavouriteOrder() {
        // Les goûts viennent d'un ensemble : leur ordre d'itération n'est pas garanti,
        // et la quête ne doit pas en dépendre.
        let a = QuestFactory.quest(for: day, country: "FR", favourites: ["suv", "hatch"])
        let b = QuestFactory.quest(for: day, country: "FR", favourites: ["hatch", "suv"])
        #expect(a.id == b.id)
        #expect(a.title == b.title)
    }

    @Test("L'identifiant de quête change d'un jour à l'autre")
    func questIdentifierAdvancesDaily() {
        let tomorrow = day.addingTimeInterval(86_400)
        #expect(QuestFactory.quest(for: day, country: "FR").id
                != QuestFactory.quest(for: tomorrow, country: "FR").id)
    }

    @Test("La quête reste jouable dans le pays du joueur")
    func questIsPlayableLocally() {
        // Une marque tirée doit se croiser en France : demander une Bugatti serait
        // une quête que personne ne remplit.
        let catalog = CatalogStore.shared
        for offset in 0..<30 {
            let date = day.addingTimeInterval(Double(offset) * 86_400)
            let quest = QuestFactory.quest(for: date, country: "FR")
            guard case .brand(let make) = quest.kind else { continue }
            let plausible = catalog.vehicles.contains { car in
                car.make.caseInsensitiveCompare(make) == .orderedSame
                    && catalog.resolve(car, in: "FR").tier.rank <= 2
            }
            #expect(plausible, "marque hors de portée en France : \(make)")
        }
    }

    @Test("Une quête rapporte toujours quelque chose")
    func questAlwaysRewards() {
        for offset in 0..<30 {
            let quest = QuestFactory.quest(for: day.addingTimeInterval(Double(offset) * 86_400),
                                           country: "FR")
            #expect(quest.reward > 0)
            #expect(!quest.title.isEmpty)
        }
    }

    @Test("Trente jours ne donnent pas trente fois le même objectif")
    func questVariesAcrossTheMonth() {
        // L'inverse du risque précédent : une graine mal mélangée donnerait la même
        // quête tous les jours, ce qui est stable mais inutile.
        let titles = Set((0..<30).map {
            QuestFactory.quest(for: day.addingTimeInterval(Double($0) * 86_400),
                               country: "FR").title
        })
        #expect(titles.count > 5, "seulement \(titles.count) objectifs distincts en un mois")
    }

    // MARK: Validation

    @Test("Une quête de marque n'accepte que cette marque")
    func brandQuestChecksMake() {
        let quest = DailyQuest(id: "t", kind: .brand("Renault"), reward: 150)
        let clio = Vehicle(id: "renault-clio", make: "Renault", model: "Clio",
                           body: "hatch", rarity: [:], aliases: [])
        let golf = Vehicle(id: "vw-golf", make: "Volkswagen", model: "Golf",
                           body: "hatch", rarity: [:], aliases: [])
        let tier = CatalogStore.shared.unknownTier
        #expect(quest.isSatisfied(vehicle: clio, tier: tier, isNewModel: false, todayCount: 1))
        #expect(!quest.isSatisfied(vehicle: golf, tier: tier, isNewModel: false, todayCount: 1))
    }

    @Test("Une quête de rareté accepte tout ce qui dépasse le palier demandé")
    func rarityQuestAcceptsBetter() {
        let catalog = CatalogStore.shared
        guard let asked = catalog.tiers.first(where: { $0.rank == 2 }),
              let better = catalog.tiers.first(where: { $0.rank > 2 }),
              let worse = catalog.tiers.first(where: { $0.rank < 2 })
        else { Issue.record("paliers insuffisants dans rarity.json"); return }

        let quest = DailyQuest(id: "t", kind: .rarity(asked), reward: 250)
        let car = Vehicle(id: "x", make: "X", model: "Y", body: "sedan", rarity: [:], aliases: [])
        #expect(quest.isSatisfied(vehicle: car, tier: better, isNewModel: false, todayCount: 1))
        #expect(quest.isSatisfied(vehicle: car, tier: asked, isNewModel: false, todayCount: 1))
        #expect(!quest.isSatisfied(vehicle: car, tier: worse, isNewModel: false, todayCount: 1))
    }

    @Test("Une quête de comptage se satisfait au bon nombre, pas avant")
    func countQuestChecksThreshold() {
        let quest = DailyQuest(id: "t", kind: .count(3), reward: 200)
        let car = Vehicle(id: "x", make: "X", model: "Y", body: "sedan", rarity: [:], aliases: [])
        let tier = CatalogStore.shared.unknownTier
        #expect(!quest.isSatisfied(vehicle: car, tier: tier, isNewModel: false, todayCount: 2))
        #expect(quest.isSatisfied(vehicle: car, tier: tier, isNewModel: false, todayCount: 3))
        #expect(quest.isSatisfied(vehicle: car, tier: tier, isNewModel: false, todayCount: 9))
    }
}
