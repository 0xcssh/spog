import Testing
@testable import Spog

/// Ce que l'IA a réellement répondu sur des photos d'annonces, le 28 septembre 2026.
///
/// Ces chaînes ne sont pas inventées : elles sortent d'une mesure sur treize photos
/// de petites annonces françaises. Elles valent mieux que des exemples imaginés,
/// parce qu'elles contiennent les formes que le modèle produit vraiment et non
/// celles qu'on suppose qu'il produit.
///
/// Trois d'entre elles sont des réponses **plus précises** que la fiche du catalogue :
/// « Peugeot 307 CC » pour une 307, « Porsche Panamera Sport Turismo » pour une
/// Panamera. Une identification plus fine que le catalogue ne doit jamais devenir un
/// échec de rapprochement — sinon l'app apprendrait un doublon à chaque finition.
struct RealWorldMatchingTests {

    private let catalog = CatalogStore.shared

    @Test("Les réponses réelles de l'IA retrouvent la bonne fiche", arguments: [
        ("Toyota Aygo",                            "toyota-aygo"),
        ("BMW 1 Series",                           "bmw-serie-1"),
        ("Citroën C3",                             "citroen-c3"),
        ("Ford Fiesta",                            "ford-fiesta"),
        ("Porsche Macan",                          "porsche-macan"),
        ("Porsche Panamera Sport Turismo",         "porsche-panamera"),
        ("Opel Meriva",                            "opel-meriva"),
        ("Peugeot 307 CC",                         "peugeot-307"),
        ("Lamborghini Urus",                       "lamborghini-urus"),
        ("Lamborghini Huracán Performante Spyder", "lamborghini-huracan"),
        ("Bentley Continental GT",                 "bentley-continental-gt"),
        ("Peugeot 3008",                           "peugeot-3008"),
        ("Mazda CX-3",                             "mazda-cx-3"),
    ])
    func realAnswersMatch(text: String, expected: String) {
        #expect(catalog.match(text)?.id == expected,
                "« \(text) » devrait donner \(expected), a donné \(catalog.match(text)?.id ?? "rien")")
    }

    @Test("L'accent de « Citroën » ne fait pas échouer le rapprochement")
    func accentsAreFolded() {
        // Le modèle écrit la marque correctement accentuée, le catalogue non.
        #expect(catalog.match("Citroën C3")?.id == catalog.match("Citroen C3")?.id)
    }

    @Test("Les modèles voisins ne se confondent pas")
    func neighbouringModelsStayDistinct() {
        // Chacun de ces couples existe au catalogue et se ressemble assez pour
        // qu'une erreur de rapprochement passe inaperçue.
        #expect(catalog.match("Mazda CX-3")?.id != catalog.match("Mazda CX-30")?.id)
        #expect(catalog.match("Toyota Aygo")?.id != catalog.match("Toyota Aygo X")?.id)
        #expect(catalog.match("Porsche Macan")?.id != catalog.match("Porsche Macan Electric")?.id)
        // « C3 » ne doit pas attraper la Corvette C3, qui contient la même chaîne.
        #expect(catalog.match("Citroen C3")?.id == "citroen-c3")
    }
}
