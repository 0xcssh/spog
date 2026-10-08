import UIKit

/// Remet une photo « à l'endroit » dans ses pixels mêmes.
///
/// L'appareil photo n'écrit pas les pixels dans le sens où le téléphone était tenu : il
/// les écrit dans le sens du capteur, et range la rotation à appliquer dans une
/// étiquette à part (`imageOrientation`, l'EXIF du fichier). `UIImage` sait la lire,
/// mais tout ce qui descend vers `cgImage` — CoreImage, Vision — l'ignore et voit les
/// pixels bruts. C'est ainsi qu'une voiture photographiée en paysage s'est retrouvée
/// debout sur sa carte, le ciel à gauche : la mise en scène travaillait sur le capteur,
/// la photo d'origine sur l'étiquette.
///
/// On redessine donc l'image une fois, juste après la capture, avec l'étiquette
/// appliquée : ensuite il n'y a plus qu'un sens, `.up`, et chaque étape de la chaîne
/// peut prendre `cgImage` sans se poser la question.
enum UprightPhoto {

    /// Plus long côté conservé. Un cliché de 12 Mpx pèse 48 Mo décompressé, et tout ce
    /// qu'on en tire est plus petit : 1280 px pour l'identification, une carte de quelques
    /// centaines de points. 2560 laisse de la marge au masquage des plaques, qui lit du
    /// texte, et au recadrage serré sur la voiture.
    static let maxDimension: CGFloat = 2560

    /// - Returns: la même image si elle est déjà droite et assez petite, sinon une copie
    ///   aux pixels droits (`.up`), à l'échelle 1, plus long côté borné à `maxDimension`.
    static func normalize(_ image: UIImage, maxDimension: CGFloat = maxDimension) -> UIImage {
        // `size` tient déjà compte de l'orientation : c'est la taille affichée.
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        guard width > 0, height > 0 else { return image }

        let longest = max(width, height)
        let factor = longest > maxDimension ? maxDimension / longest : 1
        if image.imageOrientation == .up, factor == 1, image.cgImage != nil {
            return image
        }

        let target = CGSize(width: (width * factor).rounded(), height: (height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        // Échelle 1 : sinon le rendu suit la densité de l'écran et sort trois fois trop grand.
        format.scale = 1
        format.opaque = true
        // Plage standard : une photo HDR passerait sinon en flottants 16 bits, deux fois
        // plus lourds, pour une carte qui ne s'affiche pas en HDR.
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            // `draw(in:)` applique l'orientation : c'est tout le travail.
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
