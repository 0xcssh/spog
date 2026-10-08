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
/// en France ne dit rien à un joueur de Hanoï. Les images sont des rendus du projet
/// (`CarArt`, ou le rendu haute définition de `VehicleArtService` quand il est là) —
/// jamais une photo d'annonce.
struct OnboardingDemo {
    let vehicle: Vehicle
    let tier: RarityTier
    let paint: UInt32
    /// Le rendu studio, déjà cadré pour la zone image d'une carte.
    let studio: UIImage?
    /// Le cliché « brut » : le même cadrage, un peu éteint, comme pris sur le vif. Nil si le
    /// traitement échoue : la carte montre alors directement le rendu studio, ce qui vaut
    /// mieux qu'une carte vide.
    let raw: UIImage?
    let contrast: RarityContrast?

    /// Surface en pixels de l'image d'origine : sert à n'accepter qu'un rendu plus fin.
    private let sourceArea: CGFloat
    /// Identité et date gardées d'une version à l'autre de la démo : remplacer l'image par
    /// une plus nette ne doit pas faire « rejouer » la carte comme une nouvelle prise.
    private let cardID: UUID
    private let caughtAt: Date

    /// Une voiture banale ici et remarquable ailleurs : la différence de Spog, montrée
    /// plutôt qu'affirmée.
    struct RarityContrast {
        let vehicle: Vehicle
        let here: RarityTier
        let elsewhere: RarityTier
        let elsewhereCountry: String
    }

    private init(vehicle: Vehicle, tier: RarityTier, paint: UInt32, studio: UIImage?,
                 raw: UIImage?, contrast: RarityContrast?, sourceArea: CGFloat,
                 cardID: UUID = UUID(), caughtAt: Date = Date()) {
        self.vehicle = vehicle
        self.tier = tier
        self.paint = paint
        self.studio = studio
        self.raw = raw
        self.contrast = contrast
        self.sourceArea = sourceArea
        self.cardID = cardID
        self.caughtAt = caughtAt
    }

    /// La carte de démonstration. Avant le passage en studio elle porte le cliché brut,
    /// après le rendu net — toujours **cadré par nous** et rangé comme rendu « passé en
    /// studio » : la zone image de la carte est presque carrée, et le rendu du catalogue,
    /// un bandeau, n'y occupait qu'une bande étroite au milieu d'un grand vide.
    func card(developed: Bool, place: String) -> CardData {
        var card = CardData(id: cardID, vehicle: vehicle, tier: tier, serial: 1,
                            caughtAt: caughtAt, placeName: place,
                            // Une démonstration n'est vérifiée par rien : pas de sceau.
                            verified: false, paint: paint)
        if let face = developed ? (studio ?? raw) : (raw ?? studio) {
            card.shot = StyledShot(stylized: face, original: face, developed: face)
        }
        return card
    }

    /// La même démo, sur une image plus fine (rendu haute définition arrivé après coup).
    /// Nil si l'image n'apporte rien : la recadrer coûterait du temps pour rien.
    func upgraded(with source: UIImage) -> OnboardingDemo? {
        let area = Self.pixelArea(source)
        guard area > sourceArea * 1.3, let studio = Self.framed(source, glow: tier.color) else {
            return nil
        }
        return OnboardingDemo(vehicle: vehicle, tier: tier, paint: paint, studio: studio,
                              raw: Self.weathered(studio), contrast: contrast,
                              sourceArea: area, cardID: cardID, caughtAt: caughtAt)
    }

    /// La même démo, sur la découpe du rendu haute définition : la voiture plus nette, sur
    /// le même studio. Nil si la découpe n'est pas plus fine que l'actuelle.
    func upgraded(withCutout cutout: UIImage) -> OnboardingDemo? {
        let area = Self.pixelArea(cutout)
        guard area > sourceArea * 1.3, let studio = Self.staged(cutout) else { return nil }
        return OnboardingDemo(vehicle: vehicle, tier: tier, paint: paint, studio: studio,
                              raw: Self.weathered(studio), contrast: contrast,
                              sourceArea: area, cardID: cardID, caughtAt: caughtAt)
    }

    // MARK: Fabrication

    static func make(country: String, store: CatalogStore = .shared) -> OnboardingDemo? {
        // Seuls les modèles qui ont un rendu embarqué peuvent servir : la démo doit marcher
        // hors ligne, au tout premier lancement.
        let illustrated = store.vehicles.filter { hasArt($0.id) }
        let ranked = illustrated.map { (vehicle: $0, tier: store.resolve($0, in: country).tier) }

        // La carte la plus impressionnante sans promettre une légendaire à la première
        // photo : le palier trophée le plus haut sous le sommet. C'est le premier contact
        // avec le jeu, il doit donner envie — une citadine rare ne fait rêver personne.
        let top = store.tiers.map(\.rank).max() ?? 0
        let showcase = ranked.filter { $0.tier.isTrophy && $0.tier.rank < top }
        let pick = showcase.max { $0.tier.rank < $1.tier.rank }
            ?? ranked.max { $0.tier.rank < $1.tier.rank }
        guard let pick else { return nil }

        // La teinte livrée, sans repeinture : le masque de repeinture d'un rendu de 660 px,
        // agrandi sur tout l'écran, laissait des bavures sur une voiture qu'on regarde de près.
        // Posée sur le studio unique de l'app, comme partout ailleurs : la découpe du rendu
        // embarqué (par son masque, immédiate). Sans masque, l'ancienne mise en page.
        let source = CarArt.image(for: pick.vehicle.id)
        let cutout = ModelCutoutService.embeddedCutoutNow(for: pick.vehicle.id, paint: nil)
        let studio = cutout.flatMap(staged) ?? source.flatMap { framed($0, glow: pick.tier.color) }

        return OnboardingDemo(vehicle: pick.vehicle, tier: pick.tier, paint: CarArt.referencePaint,
                              studio: studio, raw: studio.flatMap(weathered),
                              contrast: widestContrast(among: illustrated, from: country,
                                                       store: store),
                              sourceArea: (cutout ?? source).map(pixelArea) ?? 0)
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

    private static func pixelArea(_ image: UIImage) -> CGFloat {
        image.size.width * image.scale * image.size.height * image.scale
    }

    // MARK: Cadrage

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Proportions de la zone image d'une carte (`CollectibleCardView`, largeur / hauteur).
    /// Une image à ces proportions s'y affiche pleine, qu'elle soit montrée en entier ou
    /// en remplissage.
    private static let artAspect: CGFloat = 1.02
    private static let canvasWidth: CGFloat = 960

    /// La voiture détourée sur le studio unique (`StudioStage`), à la forme de la zone
    /// image d'une carte.
    static func staged(_ cutout: UIImage) -> UIImage? {
        let canvas = CGSize(width: canvasWidth, height: (canvasWidth / artAspect).rounded())
        return StudioStage.render(cutout, size: canvas, scale: 1)
    }

    /// Met un rendu à la forme de la zone image d'une carte. Repli, quand la voiture n'a
    /// pas pu être détourée.
    ///
    /// Un rendu déjà presque carré (les rendus haute définition) est simplement recadré.
    /// Un bandeau (660 × 290 au catalogue) est posé **sur toute la largeur**, la voiture
    /// un peu au-dessus du centre, sur un sol qui la reflète : c'est le reflet et le halo
    /// qui occupent le bas, plus un aplat vide. Ni la voiture ni son fond ne sont floutés
    /// — un ancien traitement le faisait et rendait une bouillie.
    static func framed(_ source: UIImage, glow: Color) -> UIImage? {
        guard source.size.width > 0, source.size.height > 0 else { return nil }
        let canvas = CGSize(width: canvasWidth, height: (canvasWidth / artAspect).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let ratio = source.size.width / source.size.height

        if ratio < 1.3 {
            return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
                source.draw(in: aspectFill(source.size, in: CGRect(origin: .zero, size: canvas)))
            }
        }

        let (top, ground) = edgeColors(source)
        // Pas tout à fait la pleine largeur : la carte grossit un peu l'image et fond ses
        // bords, et ce sont les pare-chocs qui se trouvent là.
        let carWidth = canvas.width * 0.96
        let carHeight = carWidth / ratio
        let car = CGRect(x: (canvas.width - carWidth) / 2,
                         y: canvas.height * 0.45 - carHeight / 2,
                         width: carWidth, height: carHeight)
        let reflection = CGRect(x: car.minX, y: car.maxY, width: carWidth, height: carHeight)

        guard let carLayer = feathered(source, size: car.size, vertical: [0, 1, 1, 0.85],
                                       horizontal: true),
              let mirror = mirrored(source, size: reflection.size) else { return nil }

        return UIGraphicsImageRenderer(size: canvas, format: format).image { renderer in
            let ctx = renderer.cgContext
            let space = CGColorSpaceCreateDeviceRGB()

            // Fond : la lumière du studio en haut, son sol en bas, prolongés jusqu'aux bords.
            if let backdrop = CGGradient(colorsSpace: space,
                                         colors: [top.cgColor, ground.cgColor] as CFArray,
                                         locations: [0.2, 0.75]) {
                ctx.drawLinearGradient(backdrop, start: .zero,
                                       end: CGPoint(x: 0, y: canvas.height), options: [])
            }

            // Halo du palier derrière la voiture : la carte s'éclaire de sa rareté.
            let halo = UIColor(glow)
            if let light = CGGradient(colorsSpace: space,
                                      colors: [halo.withAlphaComponent(0.28).cgColor,
                                               halo.withAlphaComponent(0).cgColor] as CFArray,
                                      locations: [0, 1]) {
                let center = CGPoint(x: canvas.width / 2, y: car.midY)
                ctx.drawRadialGradient(light, startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: canvas.width * 0.6,
                                       options: [])
            }

            mirror.draw(in: reflection, blendMode: .normal, alpha: 0.32)
            carLayer.draw(in: car)
        }
    }

    /// Position d'une image en remplissage : centrée, rognée sur le côté qui déborde.
    private static func aspectFill(_ size: CGSize, in rect: CGRect) -> CGRect {
        let scale = max(rect.width / size.width, rect.height / size.height)
        let width = size.width * scale, height = size.height * scale
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2,
                      width: width, height: height)
    }

    /// L'image, bords fondus vers la transparence : posée sur le fond prolongé, elle ne
    /// laisse aucune couture rectangulaire. `vertical` donne l'opacité en haut, puis aux
    /// deux tiers intérieurs, puis en bas.
    private static func feathered(_ image: UIImage, size: CGSize, vertical: [CGFloat],
                                  horizontal: Bool) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let space = CGColorSpaceCreateDeviceRGB()
        let rect = CGRect(origin: .zero, size: size)

        func alphas(_ values: [CGFloat]) -> CFArray {
            values.map { UIColor.black.withAlphaComponent($0).cgColor } as CFArray
        }
        guard vertical.count == 4,
              let down = CGGradient(colorsSpace: space, colors: alphas(vertical),
                                    locations: [0, 0.22, 0.8, 1]),
              let across = CGGradient(colorsSpace: space, colors: alphas([0, 1, 1, 0]),
                                      locations: [0, 0.07, 0.93, 1]) else { return nil }

        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let ctx = renderer.cgContext
            image.draw(in: rect)
            // « destinationIn » multiplie l'image déjà posée par l'opacité du dégradé.
            ctx.setBlendMode(.destinationIn)
            ctx.drawLinearGradient(down, start: .zero, end: CGPoint(x: 0, y: size.height),
                                   options: [])
            if horizontal {
                ctx.drawLinearGradient(across, start: .zero, end: CGPoint(x: size.width, y: 0),
                                       options: [])
            }
        }
    }

    /// Le reflet au sol : l'image retournée, qui s'éteint vite vers le bas.
    private static func mirrored(_ image: UIImage, size: CGSize) -> UIImage? {
        guard let faded = feathered(image, size: size, vertical: [0, 0, 0.6, 1],
                                    horizontal: true) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let ctx = renderer.cgContext
            // Retourné autour de son milieu : le haut du reflet touche les roues, et le
            // fondu (opaque en bas de l'image d'origine) devient opaque en haut.
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            faded.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Teinte moyenne du haut et du bas du rendu : le fond prolongé reprend la lumière du
    /// studio au lieu d'un noir qui trancherait avec elle.
    private static func edgeColors(_ image: UIImage) -> (top: UIColor, floor: UIColor) {
        let fallback: (top: UIColor, floor: UIColor) = (UIColor(Theme.surface),
                                                        UIColor(Theme.background))
        guard let cgImage = image.cgImage else { return fallback }
        let source = CIImage(cgImage: cgImage)
        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { return fallback }
        // Core Image compte depuis le bas : le haut du rendu est la bande aux grands y.
        let topBand = CGRect(x: extent.minX, y: extent.maxY - extent.height * 0.12,
                             width: extent.width, height: extent.height * 0.12)
        let floorBand = CGRect(x: extent.minX, y: extent.minY,
                               width: extent.width, height: extent.height * 0.08)
        return (average(source, in: topBand) ?? fallback.top,
                average(source, in: floorBand) ?? fallback.floor)
    }

    private static func average(_ image: CIImage, in band: CGRect) -> UIColor? {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = band
        guard let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        // Un peu plus sombre que la moyenne : le pourtour doit rester derrière la voiture.
        return UIColor(red: CGFloat(pixel[0]) / 255 * 0.8,
                       green: CGFloat(pixel[1]) / 255 * 0.8,
                       blue: CGFloat(pixel[2]) / 255 * 0.8, alpha: 1)
    }

    // MARK: Cliché brut

    /// Fait passer un rendu studio pour une photo prise sur le vif : couleurs un peu
    /// éteintes, lumière plus basse, coins assombris. Assez pour que le passage en studio
    /// se voie, pas plus. On ne touche qu'à la lumière : le cadrage est celui du rendu net,
    /// pour que la carte ne saute pas au moment du passage en studio.
    static func weathered(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let source = CIImage(cgImage: cgImage)
        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let controls = CIFilter.colorControls()
        controls.inputImage = source
        controls.saturation = 0.55
        controls.brightness = -0.06
        controls.contrast = 0.92

        let vignette = CIFilter.vignette()
        vignette.inputImage = controls.outputImage
        vignette.intensity = 0.8
        vignette.radius = 1.4

        guard let output = vignette.outputImage?.cropped(to: extent),
              let rendered = context.createCGImage(output, from: extent) else { return nil }
        return UIImage(cgImage: rendered)
    }
}
