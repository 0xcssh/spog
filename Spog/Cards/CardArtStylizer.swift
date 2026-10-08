import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// La photo prise par l'utilisateur, et sa version transformee en visuel de carte.
struct StyledShot {
    let stylized: UIImage   // la photo redressee, cadree sur la voiture, a peine etalonnee
    let original: UIImage   // le cliche brut (redresse), accessible d'un tap
    /// Rendu studio genere a partir du cliche, une fois la carte « developpee ».
    var developed: UIImage? = nil

    /// Le visuel de la carte : le rendu developpe s'il existe — c'est la meme voiture,
    /// teinte et jantes comprises, en studio —, sinon la photo cadree.
    var face: UIImage { developed ?? stylized }
}

/// Fait d'une photo de voiture le visuel d'une carte : **une vraie photo**, redressee,
/// cadree sur la voiture, a peine etalonnee. Entierement sur l'appareil — aucun appel
/// reseau, aucun cout.
///
/// **Ce que cette chaine ne fait plus, et pourquoi.** Jusqu'au 08/10/2026 elle voulait
/// faire passer la photo pour une illustration du catalogue : saturation poussee, nappe
/// a la couleur du palier, vignette appuyee, et quand Vision detourait, la voiture
/// reposee sur une scene de neons. Sur un iPhone, le resultat etait une photo bleuie,
/// sombre et sale, meconnaissable — le contraire de ce que le joueur a vu dans la rue.
/// La regle est desormais celle de la fiche : **la voiture reellement croisee passe
/// avant tout**, et elle doit se reconnaitre. Le palier de rarete se lit sur le cadre de
/// la carte, pas dans les couleurs de la photo.
///
/// Le detourage sert encore, a deux choses : savoir **ou est la voiture** pour cadrer
/// dessus, et, seulement quand il est net, adoucir et assombrir legerement le decor —
/// l'effet d'un objectif lumineux, qui reste une photo.
///
/// **Reglage :** `tools/preview-stylizer.swift` fait tourner la meme chaine sur macOS et
/// ecrit un PNG. C'est le seul moyen de voir le resultat sans iPhone, `Vision` ne
/// detourant pas dans le simulateur. Toute retouche ici doit y etre reportee.
enum CardArtStylizer {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Largeur sur hauteur du cadre de l'illustration dans `CollectibleCard` (et dans
    /// l'image partagee, 340 × 334). Livrer ce rapport evite que l'affichage recoupe a
    /// l'aveugle ce qu'on a soigneusement cadre ici.
    static let cardAspect: CGFloat = 1.02

    /// Plus long cote du visuel enregistre : trois fois la carte affichee, le reste
    /// ne serait que du poids dans le garage.
    static let outputMaxDimension: CGFloat = 1600

    static func stylize(_ photo: UIImage) async -> StyledShot? {
        // Redressee a la capture deja ; ceci protege des autres sources, et ne coute
        // rien sur une image droite.
        let upright = UprightPhoto.normalize(photo)
        guard let cgImage = upright.cgImage else { return nil }
        let source = CIImage(cgImage: cgImage)
        let size = source.extent.size

        let lifted = await SubjectLifter.lift(upright)
        let cadre = framing(imageSize: size, subject: lifted?.bounds)

        // Decor adouci seulement sur un detourage net : sur un masque approximatif, le
        // flou mordrait la carrosserie et laisserait des bouts de rue nets autour.
        var scene = source
        if let lifted, isClean(lifted) {
            scene = softenBackground(source, mask: lifted.mask)
        }

        let canvas = CGRect(origin: .zero, size: cadre.canvas)
        var card = vignette(compose(grade(scene), framing: cadre, imageHeight: size.height),
                            in: canvas).cropped(to: canvas)

        var outputRect = canvas
        let longest = max(canvas.width, canvas.height)
        if longest > outputMaxDimension {
            let scale = outputMaxDimension / longest
            let resize = CIFilter.lanczosScaleTransform()
            resize.inputImage = card
            resize.scale = Float(scale)
            resize.aspectRatio = 1
            outputRect = CGRect(x: 0, y: 0, width: (canvas.width * scale).rounded(.down),
                                height: (canvas.height * scale).rounded(.down))
            card = (resize.outputImage ?? card).cropped(to: outputRect)
        }

        guard let output = context.createCGImage(card, from: outputRect) else { return nil }
        return StyledShot(stylized: UIImage(cgImage: output), original: upright)
    }

    // MARK: Cadrage

    /// Ce qu'on garde de la photo pour la carte.
    struct Framing: Equatable {
        /// Partie de la photo gardee, en pixels, origine en haut a gauche.
        let crop: CGRect
        /// Taille du visuel. Plus haute que `crop` quand la voiture, trop large pour tenir
        /// dans un cadre presque carre decoupe dans la photo, demande des bandes en haut
        /// et en bas — remplies par la photo elle-meme, floutee.
        let canvas: CGSize
    }

    /// Cadre la carte sur la voiture, ou au centre si on ne sait pas ou elle est.
    ///
    /// Une voiture est deux fois plus large que haute, une carte presque carree. Prise en
    /// paysage, la voiture remplit la largeur de la photo, et un carre decoupe au milieu
    /// lui coupe l'avant et l'arriere. On prefere alors garder toute la largeur utile et
    /// completer le haut et le bas : une carte qui montre la voiture entiere vaut mieux
    /// qu'une carte pleine qui montre une portiere.
    ///
    /// - Parameter subject: boite du sujet, normalisee, origine en haut a gauche.
    static func framing(imageSize: CGSize, subject: CGRect?,
                        aspect: CGFloat = cardAspect) -> Framing {
        let width = imageSize.width, height = imageSize.height

        guard let subject, subject.width > 0, subject.height > 0 else {
            // Remplissage centre, sans bandes.
            let w = min(width, height * aspect).rounded(.down)
            let h = min(height, (w / aspect).rounded(.down))
            return Framing(crop: CGRect(x: ((width - w) / 2).rounded(.down),
                                        y: ((height - h) / 2).rounded(.down),
                                        width: w, height: h),
                           canvas: CGSize(width: w, height: h))
        }

        let box = CGRect(x: subject.minX * width, y: subject.minY * height,
                         width: subject.width * width, height: subject.height * height)

        // De l'air autour : environ 12 % de part et d'autre en largeur, un quart en hauteur.
        var w = max(box.width * 1.24, box.height * 1.5 * aspect)
        // Jamais plus serre que la moitie du plus grand cadre possible : au-dela, la
        // voiture lointaine devient une bouillie de pixels.
        w = max(w, min(width, height * aspect) * 0.5)
        w = min(w, width)
        var h = w / aspect
        // Des bandes, d'accord, mais pas plus d'un cinquieme de la hauteur : au-dela on
        // accepte de rogner les pare-chocs plutot que de montrer surtout du flou.
        if h > height * 1.2 {
            h = height * 1.2
            w = h * aspect
        }
        w = w.rounded(.down)
        h = h.rounded(.down)

        let visible = min(h, height)
        let x = min(max(box.midX - w / 2, 0), width - w).rounded(.down)
        let y = min(max(box.midY - visible / 2, 0), height - visible).rounded(.down)
        return Framing(crop: CGRect(x: x, y: y, width: w, height: visible),
                       canvas: CGSize(width: w, height: h))
    }

    /// Decoupe la photo selon le cadrage, et complete le haut et le bas s'il le faut.
    private static func compose(_ image: CIImage, framing: Framing, imageHeight: CGFloat) -> CIImage {
        // CoreImage compte depuis le bas, le cadrage depuis le haut.
        let crop = CGRect(x: framing.crop.minX, y: imageHeight - framing.crop.maxY,
                          width: framing.crop.width, height: framing.crop.height)
        let canvas = CGRect(origin: .zero, size: framing.canvas)
        let band = ((canvas.height - crop.height) / 2).rounded(.down)

        let strip = image.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY + band))
        guard band >= 1 else { return strip.cropped(to: canvas) }

        // Les bandes : la meme photo, agrandie pour couvrir la carte, tres floutee et
        // assombrie. Elle prolonge les couleurs de la scene au lieu de poser deux
        // barres noires, et s'efface sous la vignette.
        let cover = canvas.height / crop.height
        let backdrop = strip
            .transformed(by: CGAffineTransform(translationX: 0, y: -band))
            .transformed(by: CGAffineTransform(scaleX: cover, y: cover))
            .transformed(by: CGAffineTransform(translationX: (canvas.width - crop.width * cover) / 2,
                                               y: 0))
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = backdrop.clampedToExtent()
        blur.radius = Float(canvas.height * 0.04)
        let dim = CIFilter.exposureAdjust()
        dim.inputImage = blur.outputImage
        dim.ev = -1.3
        let background = (dim.outputImage ?? backdrop).cropped(to: canvas)

        // Raccord fondu : une ligne nette entre photo et flou se verrait comme une couture.
        let feather = max(2, crop.height * 0.04)
        let bottom = CIFilter.linearGradient()
        bottom.point0 = CGPoint(x: 0, y: band)
        bottom.point1 = CGPoint(x: 0, y: band + feather)
        bottom.color0 = CIColor(red: 0, green: 0, blue: 0)
        bottom.color1 = CIColor(red: 1, green: 1, blue: 1)
        let top = CIFilter.linearGradient()
        top.point0 = CGPoint(x: 0, y: band + crop.height)
        top.point1 = CGPoint(x: 0, y: band + crop.height - feather)
        top.color0 = CIColor(red: 0, green: 0, blue: 0)
        top.color1 = CIColor(red: 1, green: 1, blue: 1)
        let both = CIFilter.multiplyCompositing()
        both.inputImage = top.outputImage
        both.backgroundImage = bottom.outputImage

        let blend = CIFilter.blendWithMask()
        blend.inputImage = strip
        blend.backgroundImage = background
        blend.maskImage = both.outputImage?.cropped(to: canvas)
        return blend.outputImage?.cropped(to: canvas) ?? strip
    }

    // MARK: Detourage

    /// Un detourage merite d'etre montre s'il couvre une bonne part de sa boite — une
    /// voiture est un bloc, pas une dentelle — et si le sujet n'est ni un detail perdu
    /// au loin ni la photo entiere.
    private static func isClean(_ lifted: LiftedPhoto) -> Bool {
        let area = lifted.bounds.width * lifted.bounds.height
        return lifted.fill >= 0.45 && (0.04...0.8).contains(area)
    }

    /// Decor legerement flou et assombri, voiture intacte : l'effet d'un objectif ouvert.
    /// Le decor reste **la vraie rue** et la voiture ne bouge pas d'un pixel : un bord de
    /// masque imparfait se fond dans sa propre photo au lieu de trancher sur un fond
    /// invente, comme le faisait la scene de neons.
    private static func softenBackground(_ image: CIImage, mask: CIImage) -> CIImage {
        let extent = image.extent
        let side = min(extent.width, extent.height)

        // Le masque est rendu a la taille de la photo ; on s'en assure plutot que de
        // decaler la mise au point de quelques pixels si ce n'etait pas le cas.
        var matte = mask
        if mask.extent.width > 0, mask.extent.height > 0, mask.extent.size != extent.size {
            matte = mask.transformed(by: CGAffineTransform(scaleX: extent.width / mask.extent.width,
                                                           y: extent.height / mask.extent.height))
        }
        let soft = CIFilter.gaussianBlur()
        soft.inputImage = matte.clampedToExtent()
        soft.radius = Float(max(1.5, side * 0.002))

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image.clampedToExtent()
        blur.radius = Float(side * 0.006)
        let dim = CIFilter.exposureAdjust()
        dim.inputImage = blur.outputImage
        dim.ev = -0.45

        let blend = CIFilter.blendWithMask()
        blend.inputImage = image
        blend.backgroundImage = dim.outputImage?.cropped(to: extent)
        blend.maskImage = soft.outputImage?.cropped(to: extent)
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    // MARK: Lumiere

    /// Un etalonnage qu'on ne doit pas remarquer : un peu de tenue, aucune teinte.
    private static func grade(_ image: CIImage) -> CIImage {
        let colors = CIFilter.colorControls()
        colors.inputImage = image
        colors.saturation = 1.04
        colors.contrast = 1.06
        colors.brightness = 0
        return colors.outputImage ?? image
    }

    /// Coins a peine assombris : le regard va a la voiture, et la photo se fond dans
    /// la carte sombre. A 1,35 comme avant, la moitie de la photo partait au noir.
    private static func vignette(_ image: CIImage, in frame: CGRect) -> CIImage {
        let filter = CIFilter.vignetteEffect()
        filter.inputImage = image
        filter.center = CGPoint(x: frame.midX, y: frame.midY)
        filter.radius = Float(min(frame.width, frame.height) * 0.5)
        filter.intensity = 0.4
        filter.falloff = 0.65
        return filter.outputImage ?? image
    }
}
