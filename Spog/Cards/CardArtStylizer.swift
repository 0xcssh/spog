import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// La photo prise par l'utilisateur, et sa version transformee en visuel de carte.
struct StyledShot {
    let stylized: UIImage   // la voiture detouree et mise en scene
    let original: UIImage   // le cliche brut, accessible d'un tap
}

/// Transforme une photo de voiture en illustration de carte a collectionner :
/// sujet detoure, recadre et pose sur une scene neon, couleurs poussees, lisere a la
/// couleur de la rarete, reflet au sol. Entierement sur l'appareil — aucun appel
/// reseau, aucun cout.
///
/// **Le resultat doit se confondre avec les illustrations du catalogue.** Quatre-vingt-
/// seize pour cent des modeles n'en ont pas encore ; pour ceux-la, cette chaine est ce
/// que le joueur voit. Si elle rend une photo a peine teintee, sa collection se lit en
/// deux categories — les vraies cartes et les siennes — et les siennes font pauvres.
///
/// **Reglage :** `tools/preview-stylizer.swift` fait tourner la meme chaine sur macOS et
/// ecrit un PNG. C'est le seul moyen de voir le resultat sans iPhone, `Vision` ne
/// detourant pas dans le simulateur. Toute retouche ici doit y etre reportee.
enum CardArtStylizer {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// - Parameter glow: couleur du contre-jour, celle du palier de rarete.
    static func stylize(_ photo: UIImage, glow: UIColor) async -> StyledShot? {
        guard let cgImage = photo.cgImage else { return nil }
        let source = CIImage(cgImage: cgImage)
        let frame = source.extent

        let composed: CIImage
        if let subject = await isolateSubject(cgImage).map({ trimEdge($0, in: frame) }) {
            // Detourage reussi : mise en scene complete, la voiture est isolee.
            let staged = stage(subject, in: frame)
            // `bloom: false` — un bloom appliqué à une image detouree deborde dans le
            // vide et cerne la voiture d'une brume blanche qu'on prend pour un defaut
            // de decoupage. Sur le sujet isole, le lisere colore suffit.
            composed = punch(staged, bloom: false)
                .composited(over: rimLight(staged, color: glow, in: frame))
                .composited(over: floorReflection(staged, in: frame))
                .composited(over: groundShadow(staged, in: frame))
                .composited(over: backdrop(color: glow, in: frame))
                .cropped(to: frame)
        } else {
            // Detourage impossible — cliche a travers une vitre, voiture noyee dans
            // le decor, contre-jour. On traite alors l'image entiere : couleurs
            // poussees, etalonnage a la couleur du palier, bords assombris.
            // Le resultat reste un visuel de carte, jamais la photo brute.
            composed = vignette(grade(punch(source), color: glow, in: frame), in: frame)
                .cropped(to: frame)
        }

        guard let output = context.createCGImage(composed, from: frame) else { return nil }
        return StyledShot(stylized: UIImage(cgImage: output), original: photo)
    }

    // MARK: Detourage

    /// Detourage du sujet principal par Vision, sur l'appareil.
    /// Rend nil dans le simulateur, qui n'embarque pas le modele d'inference.
    private static func isolateSubject(_ cgImage: CGImage) async -> CIImage? {
        guard let lifted = await SubjectLifter.lift(UIImage(cgImage: cgImage)) else {
            return nil
        }
        return CIImage(image: lifted.subject)
    }

    /// Rogne le bord du sujet de quelques pixels.
    ///
    /// Le masque de Vision suit le contour **au pixel pres, celui-ci compris** : sur une
    /// photo de rue, ce dernier pixel appartient encore au ciel ou au bitume clair. Pose
    /// sur un fond sombre, il forme un lisere clair qui trahit le decoupage et donne a
    /// la voiture l'air d'un autocollant.
    ///
    /// On erode **la transparence seule**. Appliquer l'erosion a l'image entiere rogne
    /// aussi les couleurs : chaque reflet clair de la carrosserie est remplace par son
    /// voisin sombre, et la voiture se couvre de trous.
    private static func trimEdge(_ subject: CIImage, in frame: CGRect) -> CIImage {
        let toMask = CIFilter.colorMatrix()
        toMask.inputImage = subject
        toMask.rVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        toMask.gVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        toMask.bVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        toMask.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        toMask.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)

        let erode = CIFilter.morphologyMinimum()
        erode.inputImage = toMask.outputImage
        erode.radius = Float(max(1.5, min(frame.width, frame.height) * 0.005))
        guard let tightened = erode.outputImage else { return subject }

        let apply = CIFilter.blendWithMask()
        apply.inputImage = subject
        apply.backgroundImage = CIImage(color: .clear).cropped(to: subject.extent)
        apply.maskImage = tightened
        return apply.outputImage ?? subject
    }

    // MARK: Mise en scene

    /// Place le sujet dans la scene : mis a l'echelle, centre, pose sur le sol.
    ///
    /// Sans ca, la voiture reste la ou elle etait sur la photo — souvent collee aux
    /// bords, parfois coupee. Les illustrations du catalogue montrent toutes une voiture
    /// **centree, avec de l'air autour et du sol dessous** ; c'est cette composition,
    /// plus que les filtres, qui fait qu'une carte a l'air fabriquee plutot que
    /// photographiee.
    private static func stage(_ subject: CIImage, in frame: CGRect) -> CIImage {
        let box = subject.extent
        guard box.width > 0, box.height > 0 else { return subject }

        // La voiture occupe au plus 82 % de la largeur et 58 % de la hauteur : le reste
        // est de l'air au-dessus et du sol en dessous, comme sur les rendus.
        let scale = min(frame.width * 0.82 / box.width, frame.height * 0.58 / box.height)
        let width = box.width * scale

        // Posee au tiers inferieur, pas au milieu : il faut de la place pour le reflet.
        let x = frame.midX - width / 2
        let y = frame.minY + frame.height * 0.30

        return subject
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: x - box.minX * scale,
                                               y: y - box.minY * scale))
    }

    /// Le reflet de la voiture sur le sol : retourne, attenue, flou.
    /// C'est le detail qui transforme un decoupage en scene — sans lui, la voiture
    /// flotte, et l'oeil le remarque avant meme de savoir pourquoi.
    private static func floorReflection(_ staged: CIImage, in frame: CGRect) -> CIImage {
        let box = staged.extent
        let flip = CGAffineTransform(scaleX: 1, y: -1)
            .concatenating(CGAffineTransform(translationX: 0, y: box.minY * 2 + box.height))
        let mirrored = staged.transformed(by: flip)
            .transformed(by: CGAffineTransform(scaleX: 1, y: 0.55)
                .concatenating(CGAffineTransform(translationX: 0, y: box.minY * 0.45)))

        let fade = CIFilter.colorMatrix()
        fade.inputImage = mirrored
        fade.aVector = CIVector(x: 0, y: 0, z: 0, w: 0.22)

        let soften = CIFilter.gaussianBlur()
        soften.inputImage = fade.outputImage
        soften.radius = Float(frame.height * 0.012)
        return (soften.outputImage ?? CIImage.empty()).cropped(to: frame)
    }

    // MARK: Lumiere

    private static func punch(_ image: CIImage, bloom useBloom: Bool = true) -> CIImage {
        let colors = CIFilter.colorControls()
        colors.inputImage = image
        colors.saturation = 1.38
        colors.contrast = 1.22
        colors.brightness = 0.02

        let vibrance = CIFilter.vibrance()
        vibrance.inputImage = colors.outputImage
        vibrance.amount = 0.5

        guard useBloom else { return vibrance.outputImage ?? image }

        // Un leger halo sur les hautes lumieres : reflets de carrosserie appuyes.
        let bloom = CIFilter.bloom()
        bloom.inputImage = vibrance.outputImage
        bloom.radius = 5
        bloom.intensity = 0.14
        return bloom.outputImage ?? image
    }

    private static func rimLight(_ subject: CIImage, color: UIColor, in frame: CGRect) -> CIImage {
        // La silhouette pleine du sujet, coloree.
        let silhouette = CIFilter.colorMatrix()
        silhouette.inputImage = subject
        let c = color.rgba
        // Un lisere, pas un neon de plus : a pleine puissance il cerne la voiture d'un
        // trait lumineux qui la detache du fond au lieu de l'y poser.
        let force: CGFloat = 0.45
        // **Les composantes suivent l'alpha.** CoreImage travaille en alpha premultiplie :
        // une couleur laissee a pleine intensite sous un alpha de 0,45 vaut, une fois
        // demultipliee, plus de 1 — donc du blanc apres ecretage. C'etait l'origine du
        // halo blafard autour de la voiture, longtemps pris pour un defaut de decoupage.
        silhouette.rVector = CIVector(x: 0, y: 0, z: 0, w: c.r * force)
        silhouette.gVector = CIVector(x: 0, y: 0, z: 0, w: c.g * force)
        silhouette.bVector = CIVector(x: 0, y: 0, z: 0, w: c.b * force)
        silhouette.aVector = CIVector(x: 0, y: 0, z: 0, w: force)

        // Flou serre : un lisere, pas une aura. Plus large, le halo debordait si loin
        // qu'il noyait la voiture dans une brume.
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = silhouette.outputImage
        blur.radius = Float(min(frame.width, frame.height) * 0.012)
        guard let blurred = blur.outputImage else { return CIImage.empty() }

        // Legerement agrandie **autour de son propre centre**, pour deborder du sujet.
        let box = subject.extent
        let grown = CGAffineTransform(translationX: -box.midX, y: -box.midY)
            .concatenating(CGAffineTransform(scaleX: 1.02, y: 1.02))
            .concatenating(CGAffineTransform(translationX: box.midX, y: box.midY))
        return blurred.transformed(by: grown).cropped(to: frame)
    }

    private static func groundShadow(_ subject: CIImage, in frame: CGRect) -> CIImage {
        let dark = CIFilter.colorMatrix()
        dark.inputImage = subject
        dark.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        dark.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        dark.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        dark.aVector = CIVector(x: 0, y: 0, z: 0, w: 0.55)

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = dark.outputImage
        blur.radius = Float(min(frame.width, frame.height) * 0.03)
        guard let blurred = blur.outputImage else { return CIImage.empty() }

        // Ecrasee **sur la base du sujet**, pas decalee d'une fraction de l'image :
        // c'est ce decalage aveugle qui faisait flotter la voiture au-dessus de son ombre.
        let box = subject.extent
        let squash = CGAffineTransform(translationX: 0, y: -box.minY)
            .concatenating(CGAffineTransform(scaleX: 1.04, y: 0.13))
            .concatenating(CGAffineTransform(translationX: 0, y: box.minY + frame.height * 0.012))
        return blurred.transformed(by: squash).cropped(to: frame)
    }

    // MARK: Decor

    /// Le decor derriere la voiture : halo sombre, puis des neons horizontaux.
    ///
    /// Les neons ne sont pas un ornement. Ce sont eux qui font qu'une photo de rue
    /// detouree **ressemble aux illustrations studio** au lieu de flotter sur un degrade
    /// anonyme. Le joueur doit voir la meme scene, que la carte vienne du catalogue ou
    /// de son propre appareil photo.
    private static func backdrop(color: UIColor, in frame: CGRect) -> CIImage {
        let gradient = CIFilter.radialGradient()
        gradient.center = CGPoint(x: frame.midX, y: frame.midY + frame.height * 0.08)
        gradient.radius0 = Float(frame.width * 0.05)
        gradient.radius1 = Float(frame.width * 0.62)

        // Les deux bornes sont **opaques**. Une couleur a alpha partiel laisse le centre
        // du degrade translucide ; la scene n'ayant rien derriere elle, ce trou se lit
        // en clair et forme un halo autour de la voiture, qu'on prend pour un defaut de
        // decoupage. La teinte du palier se melange donc au noir plutot que de s'y
        // fondre par transparence.
        let nuit = (r: CGFloat(0.02), g: CGFloat(0.015), b: CGFloat(0.035))
        let c = color.rgba
        let melange: CGFloat = 0.16
        gradient.color0 = CIColor(red: nuit.r + (c.r - nuit.r) * melange,
                                  green: nuit.g + (c.g - nuit.g) * melange,
                                  blue: nuit.b + (c.b - nuit.b) * melange,
                                  alpha: 1)
        gradient.color1 = CIColor(red: nuit.r, green: nuit.g, blue: nuit.b, alpha: 1)
        let base = (gradient.outputImage ?? CIImage(color: .black)).cropped(to: frame)

        // Trois bandes a des hauteurs differentes : deux dans les teintes de la scene,
        // une a la couleur du palier pour que la rarete se lise jusque dans le decor.
        let strips: [(y: CGFloat, height: CGFloat, color: CIColor, alpha: CGFloat)] = [
            (0.80, 0.009, CIColor(red: 0.13, green: 0.83, blue: 0.93), 1.0),   // cyan
            (0.70, 0.006, CIColor(color: color), 0.85),
            (0.60, 0.007, CIColor(red: 0.96, green: 0.25, blue: 0.62), 0.75),  // magenta
        ]

        return strips.reduce(base) { scene, strip in
            let bar = CIImage(color: strip.color.withAlpha(strip.alpha))
                .cropped(to: CGRect(x: frame.minX - frame.width * 0.1,
                                    y: frame.minY + frame.height * strip.y,
                                    width: frame.width * 1.2,
                                    height: max(1, frame.height * strip.height)))
            let glow = CIFilter.gaussianBlur()
            glow.inputImage = bar
            glow.radius = Float(frame.height * 0.008)
            guard let blurred = glow.outputImage else { return scene }
            // Fusion additive : un neon ajoute de la lumiere, il n'en cache pas.
            let add = CIFilter.additionCompositing()
            add.inputImage = blurred.cropped(to: frame)
            add.backgroundImage = scene
            return add.outputImage?.cropped(to: frame) ?? scene
        }
    }

    // MARK: Repli, quand le detourage echoue

    /// Etalonnage : une nappe a la couleur du palier posee en lumiere douce sur l'image.
    private static func grade(_ image: CIImage, color: UIColor, in frame: CGRect) -> CIImage {
        let tint = CIImage(color: CIColor(color: color.withAlphaComponent(0.22)))
            .cropped(to: frame)
        let blend = CIFilter.softLightBlendMode()
        blend.inputImage = tint
        blend.backgroundImage = image.cropped(to: frame)
        return blend.outputImage ?? image
    }

    /// Bords assombris : concentre le regard sur la voiture, signature du visuel de carte.
    private static func vignette(_ image: CIImage, in frame: CGRect) -> CIImage {
        let filter = CIFilter.vignetteEffect()
        filter.inputImage = image
        filter.center = CGPoint(x: frame.midX, y: frame.midY)
        filter.radius = Float(min(frame.width, frame.height) * 0.52)
        filter.intensity = 1.35
        filter.falloff = 0.72
        return filter.outputImage ?? image
    }
}

private extension CIColor {
    /// Meme couleur, opacite imposee. `CIColor` n'offre pas l'equivalent de
    /// `withAlphaComponent`, et recopier les trois composantes a chaque appel
    /// noierait l'intention sous la mecanique.
    func withAlpha(_ alpha: CGFloat) -> CIColor {
        CIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

private extension UIColor {
    var rgba: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}
