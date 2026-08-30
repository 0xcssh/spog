import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Illustrations de vehicules embarquees, une par identifiant du catalogue, produites
/// une fois par `tools/render-car-art.py` — aucun cout ni appel reseau a l'usage.
///
/// **Les illustrations sont livrees en gris metallise, une seule par modele.** La teinte
/// de la voiture reellement photographiee est appliquee ici, sur l'appareil : la carte
/// porte donc la couleur de la vraie voiture, sans qu'il ait fallu generer une image par
/// couple modele + couleur. Quatorze teintes multipliaient la facture par quatorze pour
/// un resultat que deux filtres obtiennent en vingt millisecondes.
enum CarArt {

    private static var cache: [String: UIImage] = [:]
    private static let lock = NSLock()
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Teinte des illustrations livrees. Une carte de cette couleur n'a rien a repeindre.
    private static let referencePaint: UInt32 = 0xB4B8BE

    /// L'illustration du modele, repeinte a la teinte demandee.
    static func image(for vehicleID: String, paint: UInt32? = nil) -> UIImage? {
        let paint = paint ?? referencePaint
        let key = "\(vehicleID)#\(String(paint, radix: 16))"

        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        guard let reference = loadReference(vehicleID) else { return nil }
        var result = reference
        if paint != referencePaint, let mask = loadMask(vehicleID),
           let painted = repaint(reference, mask: mask, to: paint) {
            result = painted
        }

        lock.lock(); cache[key] = result; lock.unlock()
        return result
    }

    /// Prepare les teintes d'une liste de cartes hors du fil principal. Sans ca, la
    /// premiere ouverture du garage repeint quatorze voitures d'un coup et saccade.
    static func warm(_ cards: [(vehicleID: String, paint: UInt32)]) async {
        for card in cards {
            _ = image(for: card.vehicleID, paint: card.paint)
            await Task.yield()
        }
    }

    // MARK: Chargement

    /// L'illustration livree : la teinte exacte si elle existe un jour, sinon la reference.
    private static func loadReference(_ vehicleID: String) -> UIImage? {
        let key = "ref:" + vehicleID
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        let names = [vehicleID + "--" + CarPaint.slug(referencePaint), vehicleID]
        for name in names {
            // JPEG d'abord : c'est le format des illustrations produites en lot, six cents
            // PNG pesant trois fois plus lourd dans le bundle pour une photo.
            for ext in ["jpg", "png"] {
                if let url = Bundle.main.url(forResource: name, withExtension: ext),
                   let image = UIImage(contentsOfFile: url.path) {
                    lock.lock(); cache[key] = image; lock.unlock()
                    return image
                }
            }
        }
        return nil
    }

    // MARK: Peinture

    /// Repeint la carrosserie sans toucher au decor.
    ///
    /// Le masque du sujet est **livre avec l'illustration**, calcule une fois a la
    /// fabrication. Le detourage de Vision n'existe pas dans le simulateur, et charger un
    /// modele ML a chaque affichage pour retrouver une forme qu'on connait deja serait du
    /// gaspillage. A l'interieur du masque, la fusion « couleur » impose teinte et
    /// saturation en gardant la clarte d'origine : c'est la seule qui repeigne une
    /// carrosserie en conservant ses reflets. Un simple melange laisse le gris tel quel.
    private static func repaint(_ image: UIImage, mask maskImage: UIImage,
                                to paint: UInt32) -> UIImage? {
        guard let cgImage = image.cgImage, let cgMask = maskImage.cgImage else { return nil }
        let source = CIImage(cgImage: cgImage)
        var mask = CIImage(cgImage: cgMask)
        guard mask.extent.width > 0, mask.extent.height > 0 else { return nil }
        mask = mask.transformed(by: CGAffineTransform(
            scaleX: source.extent.width / mask.extent.width,
            y: source.extent.height / mask.extent.height))

        let target = CarPaint.uiColor(paint)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        target.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let flat = CIImage(color: CIColor(color: target)).cropped(to: source.extent)

        let colorize = CIFilter.colorBlendMode()
        colorize.inputImage = flat
        colorize.backgroundImage = source

        // Retour partiel vers l'original : a pleine puissance, vitres et chromes virent
        // aussi et la voiture prend un air de jouet en plastique. Une teinte pale se
        // pose plus franchement qu'une teinte saturee, qui deborderait sur le decor.
        let mix = CIFilter.mix()
        mix.inputImage = colorize.outputImage
        mix.backgroundImage = source
        // Même sur une teinte sans couleur, on ne pousse pas la fusion à fond : à pleine
        // puissance la carrosserie perd ses nuances et la voiture paraît en carton.
        mix.amount = 0.8

        // La fusion « couleur » ne transporte **que** la teinte et la saturation : un noir
        // ou un bleu nuit appliques ainsi ressortent gris clair, puisque la clarte reste
        // celle du rendu argent. On rapproche donc la clarte de celle de la peinture voulue
        // — sans quoi « scanner une voiture noire » donnait une carte grise.
        let reference: CGFloat = 0.72   // clarte du gris metallise de reference
        let lightness = CIFilter.colorControls()
        lightness.inputImage = mix.outputImage
        // Correction volontairement partielle : a pleine puissance, un gris nardo ou un
        // bleu nuit tournaient au noir et la voiture disparaissait dans le fond sombre de
        // la carte. La moitie du chemin suffit a lire « sombre » sans perdre la carrosserie.
        // Éclaircir est bien plus destructeur qu'assombrir : les hautes lumières d'une
        // carrosserie sont déjà proches du blanc, et les pousser efface les reliefs.
        // Une voiture blanche reste donc à peine plus claire que l'argent de référence.
        let delta = (brightness - reference) * 0.5
        lightness.brightness = Float(max(-0.22, min(0.04, delta)))
        // Un peu de contraste rendu : c'est lui qui redonne les arêtes de carrosserie.
        lightness.contrast = 1.06
        lightness.saturation = 1

        let compose = CIFilter.blendWithMask()
        compose.inputImage = lightness.outputImage
        compose.backgroundImage = source
        compose.maskImage = mask

        guard let output = compose.outputImage,
              let rendered = context.createCGImage(output, from: source.extent)
        else { return nil }
        return UIImage(cgImage: rendered)
    }

    /// Le masque livre avec l'illustration. Absent : la voiture reste dans sa teinte
    /// de reference, ce qui vaut mieux qu'une carte sans image.
    private static func loadMask(_ vehicleID: String) -> UIImage? {
        let key = "mask:" + vehicleID
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        guard let url = Bundle.main.url(forResource: vehicleID + "-mask", withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        lock.lock(); cache[key] = image; lock.unlock()
        return image
    }
}
