import Testing
@testable import Spog

/// Le contrat entre l'app et la fonction `identify`.
///
/// Le serveur ne renvoie que des valeurs tirées de listes fermées, et l'app les traduit
/// en couleur de carrosserie et en géométrie 3D. Les deux listes vivent dans deux fichiers
/// que rien ne relie : `supabase/functions/identify/index.ts` d'un côté, Swift de l'autre.
/// Ajouter « gold » côté serveur sans y penser ici ne casse rien visiblement — les voitures
/// dorées prennent simplement une couleur au hasard, et personne ne comprend pourquoi.
struct ServerContractTests {

    /// Copie littérale de `COLORS` dans `supabase/functions/identify/index.ts`.
    /// À modifier ici **et là-bas**, jamais dans un seul des deux.
    private static let serverColors = [
        "white", "black", "silver", "grey", "red", "blue", "dark blue",
        "green", "yellow", "orange", "purple", "teal", "brown", "beige",
    ]

    /// Copie littérale de `BODIES` dans le même fichier.
    private static let serverBodies = ["hatch", "sedan", "suv", "sport", "pickup", "van"]

    @Test("Chaque couleur que le serveur peut renvoyer donne une peinture")
    func everyServerColorMapsToPaint() {
        for name in Self.serverColors {
            #expect(CarPaint.fromServer(name) != nil,
                    "« \(name) » sort du serveur et l'app ne sait pas le peindre")
        }
    }

    @Test("Chaque peinture obtenue est dans la palette des cartes")
    func mappedPaintsBelongToPalette() {
        // Sinon la carte porte une teinte que le repeignage n'a jamais éprouvée.
        for name in Self.serverColors {
            guard let paint = CarPaint.fromServer(name) else { continue }
            #expect(CarPaint.palette.contains(paint), "« \(name) » sort de la palette")
        }
    }

    @Test("Deux couleurs du serveur ne se peignent pas pareil")
    func serverColorsAreDistinct() {
        // Scanner une voiture bleue et une bleu nuit doit donner deux cartes différentes,
        // c'est toute la promesse faite au joueur.
        let paints = Self.serverColors.compactMap(CarPaint.fromServer)
        #expect(Set(paints).count == paints.count, "deux couleurs se confondent")
    }

    @Test("Une couleur que le serveur n'émet pas ne se peint pas au hasard")
    func unknownColorYieldsNil() {
        // Nil est la bonne réponse : la carte tire alors une teinte, au lieu d'afficher
        // avec aplomb une couleur fausse.
        #expect(CarPaint.fromServer("") == nil)
        #expect(CarPaint.fromServer("chartreuse") == nil)
    }

    @Test("Le nom d'une peinture et sa peinture font l'aller-retour")
    func paintNamesRoundTrip() {
        // `slug` sert à nommer les fichiers d'illustration : une collision renverrait
        // l'image d'une autre couleur.
        for paint in CarPaint.palette {
            #expect(CarPaint.name(paint) != "metallic silver" || paint == 0xB4B8BE,
                    "la teinte \(String(paint, radix: 16)) retombe sur le repli argent")
        }
        let slugs = CarPaint.palette.map(CarPaint.slug)
        #expect(Set(slugs).count == slugs.count, "deux teintes portent le même nom de fichier")
    }

    @Test("Chaque carrosserie que le serveur peut renvoyer a une géométrie")
    func everyServerBodyHasGeometry() {
        for body in Self.serverBodies {
            #expect(CarBody(body).rawValue == body,
                    "« \(body) » sort du serveur et retombe sur la berline par défaut")
        }
    }

    @Test("Une carrosserie inconnue retombe sur la berline plutôt que de planter")
    func unknownBodyFallsBack() {
        #expect(CarBody("hovercraft") == .sedan)
        #expect(CarBody("") == .sedan)
    }
}
