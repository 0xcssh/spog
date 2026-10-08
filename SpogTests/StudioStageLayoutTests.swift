import Testing
import CoreGraphics
@testable import Spog

/// Le cadrage commun du studio des modèles.
///
/// C'est lui qui promet que trois cibles côte à côte ont la même présence : même sol,
/// même marge, même échelle à proportions égales. Une erreur ici ne casse rien, elle se
/// voit seulement à l'écran — qu'on n'a pas sous Windows.
struct StudioStageLayoutTests {

    private let card = CGSize(width: 110, height: 100)

    @Test("La voiture est centrée, posée sur la ligne de sol")
    func centredOnGround() {
        let car = StudioStageLayout.carRect(subject: CGSize(width: 800, height: 360), in: card)
        #expect(abs(car.midX - card.width / 2) < 0.001)
        #expect(abs(car.maxY - card.height * StudioStageLayout.groundLine) < 0.001)
    }

    @Test("Les proportions de la découpe sont gardées")
    func keepsAspect() {
        let subject = CGSize(width: 820, height: 390)
        let car = StudioStageLayout.carRect(subject: subject, in: card)
        #expect(abs(car.width / car.height - subject.width / subject.height) < 0.001)
    }

    @Test("La présence ne dépend pas de la résolution de la source")
    func resolutionIndependent() {
        // Le bandeau embarqué et le rendu HD du même modèle, aux mêmes proportions : la
        // voiture ne doit pas changer de taille quand le rendu HD remplace le bandeau.
        let embedded = StudioStageLayout.carRect(subject: CGSize(width: 600, height: 260), in: card)
        let hd = StudioStageLayout.carRect(subject: CGSize(width: 900, height: 390), in: card)
        #expect(abs(embedded.width - hd.width) < 0.001)
        #expect(abs(embedded.minY - hd.minY) < 0.001)
    }

    @Test("Une voiture basse et longue est bornée par la largeur")
    func wideCarLimitedByWidth() {
        let car = StudioStageLayout.carRect(subject: CGSize(width: 1000, height: 300), in: card)
        #expect(abs(car.width - card.width * StudioStageLayout.maxWidth) < 0.001)
        #expect(car.height <= card.height * StudioStageLayout.maxHeight + 0.001)
    }

    @Test("Un utilitaire haut dans un cadre large est borné par la hauteur")
    func tallCarLimitedByHeight() {
        let wide = CGSize(width: 300, height: 100)
        let car = StudioStageLayout.carRect(subject: CGSize(width: 600, height: 460), in: wide)
        #expect(abs(car.height - wide.height * StudioStageLayout.maxHeight) < 0.001)
        #expect(car.width <= wide.width * StudioStageLayout.maxWidth + 0.001)
        #expect(car.minY >= 0)
    }

    @Test("Le reflet part du bas de la voiture, sur une part de sa hauteur")
    func reflectionBelowCar() {
        let car = CGRect(x: 10, y: 20, width: 80, height: 40)
        let reflection = StudioStageLayout.reflectionRect(for: car)
        #expect(reflection.minY == car.maxY)
        #expect(reflection.minX == car.minX && reflection.width == car.width)
        #expect(abs(reflection.height - 40 * StudioStageLayout.reflectionDepth) < 0.001)
    }

    @Test("Des tailles vides ne donnent rien, sans division par zéro")
    func emptySizes() {
        #expect(StudioStageLayout.carRect(subject: .zero, in: card) == .zero)
        #expect(StudioStageLayout.carRect(subject: CGSize(width: 10, height: 5), in: .zero) == .zero)
    }

    @Test("Une découpe de voiture de trois quarts est acceptée")
    func plausibleCutout() {
        #expect(StudioStageLayout.isPlausibleCutout(size: CGSize(width: 820, height: 380),
                                                    fill: 0.72, relativeWidth: 0.8))
    }

    @Test("Une découpe qui a pris le reflet, un néon ou un trou est refusée")
    func implausibleCutouts() {
        // Voiture et reflet du sol miroir : la boîte double de hauteur.
        #expect(!StudioStageLayout.isPlausibleCutout(size: CGSize(width: 820, height: 760),
                                                     fill: 0.6, relativeWidth: 0.8))
        // Un néon seul : très long, très fin.
        #expect(!StudioStageLayout.isPlausibleCutout(size: CGSize(width: 900, height: 40),
                                                     fill: 0.9, relativeWidth: 0.88))
        // Un masque troué.
        #expect(!StudioStageLayout.isPlausibleCutout(size: CGSize(width: 820, height: 380),
                                                     fill: 0.2, relativeWidth: 0.8))
        // Un détail minuscule du décor.
        #expect(!StudioStageLayout.isPlausibleCutout(size: CGSize(width: 200, height: 90),
                                                     fill: 0.7, relativeWidth: 0.2))
        #expect(!StudioStageLayout.isPlausibleCutout(size: .zero, fill: 1, relativeWidth: 1))
    }

    @Test("Le voile sous les pneus est retiré, la carrosserie jamais")
    func groundRowTrimsShadowVeil() {
        // 100 rangées : caisse pleine jusqu'à 79, deux pneus (10 % de la largeur) jusqu'à
        // 89, puis un voile d'ombre semi-transparent, sans pixel franchement opaque.
        let width = 400
        let rows = (0..<100).map { y in y < 80 ? 380 : (y < 90 ? 40 : 2) }
        #expect(StudioStageLayout.groundRow(solidPerRow: rows, width: width) == 89)
        // Rien à retirer : la dernière rangée est déjà sur les roues.
        #expect(StudioStageLayout.groundRow(solidPerRow: Array(repeating: 300, count: 50), width: width) == 49)
        // Jamais plus d'un quart de la hauteur, même si tout le bas paraît vide.
        let sparse = (0..<100).map { y in y < 20 ? 300 : 0 }
        #expect(StudioStageLayout.groundRow(solidPerRow: sparse, width: width) == 74)
    }
}
