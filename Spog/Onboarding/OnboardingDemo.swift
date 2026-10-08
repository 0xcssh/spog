import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Règles du jeu telles que l'onboarding les annonce.
///
/// Le serveur les applique et l'app ne s'en sert nulle part ailleurs : les ligues arrivent
/// du serveur avec leurs propres seuils (`AccountStore.League.promote`). Mais l'onboarding
/// parle avant tout appel réseau, et le joueur doit lire des chiffres justes. À tenir
/// alignés sur `join_league` (004_players_leagues.sql), `LEAGUE_PROMOTE` (social.ts) et
/// `BOUNTY_SLOTS` (bounty.ts).
enum OnboardingRules {
    static let leagueSize = 30
    static let leaguePromote = 7
    static let bountyTargets = 3
}

/// La prise de démonstration : une voiture « déjà dans le viseur », la carte qu'elle donne,
/// et un exemple de rareté qui change avec le pays.
///
/// **Tout vient des données, rien n'est choisi par son nom.** Une voiture écrite en dur
/// serait la bonne pour un pays et absurde pour un autre ; la Clio qui illustre la rareté
/// en France ne dit rien à un joueur de Hanoï. Les deux images sont des rendus de `CarArt`,
/// qui appartiennent au projet — jamais une photo d'annonce.
struct OnboardingDemo {
    let vehicle: Vehicle
    let tier: RarityTier
    let paint: UInt32
    /// Le cliché « brut » : le rendu studio terni, assombri et recadré au carré comme une
    /// photo prise dans la rue. Nil si le traitement échoue : la carte montre alors
    /// directement le rendu, ce qui vaut mieux qu'une carte vide.
    let raw: UIImage?
    let contrast: RarityContrast?

    private let cardID = UUID()
    private let caughtAt = Date()

    /// Une voiture banale ici et remarquable ailleurs : la différence de Spog, montrée
    /// plutôt qu'affirmée.
    struct RarityContrast {
        let vehicle: Vehicle
        let here: RarityTier
        let elsewhere: RarityTier
        let elsewhereCountry: String
    }

    /// La carte de démonstration. Avant développement, elle porte le cliché brut ; après,
    /// plus de cliché, et la carte retombe sur le rendu studio du modèle, à la teinte de
    /// la voiture — exactement ce que le joueur verra dans son Spogdex.
    func card(developed: Bool, place: String) -> CardData {
        var card = CardData(id: cardID, vehicle: vehicle, tier: tier, serial: 1,
                            caughtAt: caughtAt, placeName: place,
                            // Une démonstration n'est vérifiée par rien : pas de sceau.
                            verified: false, paint: paint)
        if !developed, let raw {
            card.shot = StyledShot(stylized: raw, original: raw)
        }
        return card
    }

    // MARK: Fabrication

    static func make(country: String, store: CatalogStore = .shared) -> OnboardingDemo? {
        // Seuls les modèles qui ont un rendu embarqué peuvent servir : sans image, il n'y
        // a ni viseur ni rendu studio à montrer.
        let illustrated = store.vehicles.filter { hasArt($0.id) }
        let ranked = illustrated.map { (vehicle: $0, tier: store.resolve($0, in: country).tier) }

        // Le premier palier qui porte un cadre, pas le plus haut : assez pour que la carte
        // brille, pas assez pour promettre une légendaire à la première photo.
        let trophies = ranked.filter { $0.tier.isTrophy }
        let pick = trophies.min { $0.tier.rank < $1.tier.rank }
            ?? ranked.max { $0.tier.rank < $1.tier.rank }
        guard let pick else { return nil }

        let paint = CarPaint.fromServer("purple") ?? CarPaint.random()
        let raw = CarArt.image(for: pick.vehicle.id, paint: paint).flatMap(weathered)

        return OnboardingDemo(vehicle: pick.vehicle, tier: pick.tier, paint: paint, raw: raw,
                              contrast: widestContrast(among: illustrated, from: country,
                                                       store: store))
    }

    /// Le modèle dont la rareté varie le plus entre le pays du joueur et un autre.
    private static func widestContrast(among vehicles: [Vehicle], from country: String,
                                       store: CatalogStore) -> RarityContrast? {
        let others = store.knownCountries.filter { $0 != country }
        var best: RarityContrast?
        var bestGap = 0
        for vehicle in vehicles {
            let here = store.resolve(vehicle, in: country).tier
            for other in others {
                let there = store.resolve(vehicle, in: other).tier
                let gap = there.rank - here.rank
                if gap > bestGap {
                    bestGap = gap
                    best = RarityContrast(vehicle: vehicle, here: here, elsewhere: there,
                                          elsewhereCountry: other)
                }
            }
        }
        return best
    }

    private static func hasArt(_ vehicleID: String) -> Bool {
        Bundle.main.url(forResource: vehicleID, withExtension: "jpg") != nil
    }

    // MARK: Cliché brut

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Fait passer un rendu studio pour une photo de rue : couleurs éteintes, lumière
    /// basse, vignettage, léger flou. Le contraste avec le rendu net est tout l'intérêt
    /// du développement ; sans lui, l'étape suivante ne montrerait rien.
    ///
    /// Le résultat est **carré** : la carte remplit sa zone d'image, et un rendu en
    /// bandeau y perdrait l'avant et l'arrière de la voiture. Le fond est prolongé par
    /// un flou du rendu lui-même plutôt que par une couleur, qu'il faudrait inventer.
    private static func weathered(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let source = CIImage(cgImage: cgImage)
        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let side = max(extent.width, extent.height)
        let square = CGRect(x: extent.midX - side / 2, y: extent.midY - side / 2,
                            width: side, height: side)
        let backdrop = source.clampedToExtent()
            .applyingGaussianBlur(sigma: 24)
            .cropped(to: square)
        let framed = source.composited(over: backdrop).cropped(to: square)

        let controls = CIFilter.colorControls()
        controls.inputImage = framed
        controls.saturation = 0.3
        controls.brightness = -0.12
        controls.contrast = 0.85

        let vignette = CIFilter.vignette()
        vignette.inputImage = controls.outputImage
        vignette.intensity = 1.2
        vignette.radius = 1.8

        guard let darkened = vignette.outputImage else { return nil }
        let soft = darkened.clampedToExtent().applyingGaussianBlur(sigma: 1.2).cropped(to: square)
        guard let rendered = context.createCGImage(soft, from: square) else { return nil }
        return UIImage(cgImage: rendered)
    }
}
