import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// La photo prise par l'utilisateur, et sa version transformee en visuel de carte.
struct StyledShot {
    let stylized: UIImage   // la voiture detouree et mise en scene
    let original: UIImage   // le cliche brut, accessible d'un tap
}

/// Transforme une photo de voiture en illustration de carte a collectionner :
/// sujet detoure, couleurs poussees, lumiere de contre-jour a la couleur de la rarete,
/// ombre portee, fond sombre. Entierement sur l'appareil — aucun appel reseau, aucun cout.
enum CardArtStylizer {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// - Parameter glow: couleur du contre-jour, celle du palier de rarete.
    static func stylize(_ photo: UIImage, glow: UIColor) async -> StyledShot? {
        guard let cgImage = photo.cgImage else { return nil }
        let source = CIImage(cgImage: cgImage)
        let frame = source.extent

        let composed: CIImage
        if let subject = await isolateSubject(cgImage) {
            // Detourage reussi : mise en scene complete, la voiture est isolee.
            composed = punch(subject)
                .composited(over: rimLight(subject, color: glow, in: frame))
                .composited(over: groundShadow(subject, in: frame))
                .composited(over: backdrop(color: glow, in: frame))
                .cropped(to: frame)
        } else {
            // Detourage impossible — cliche a travers une vitre, voiture noyee dans
            // le decor, contre-jour. On traite alors l'image entiere : couleurs
            // poussees, etalonnage a la couleur du palier, bords assombris.
            // Le resultat reste un visuel de carte, jamais la photo brute.
            composed = vignette(grade(punch(source), color: glow, in: frame),
                                in: frame)
                .cropped(to: frame)
        }

        guard let output = context.createCGImage(composed, from: frame) else { return nil }
        return StyledShot(stylized: UIImage(cgImage: output), original: photo)
    }

    // MARK: Etapes

    /// Detourage du sujet principal par Vision, sur l'appareil.
    private static func isolateSubject(_ cgImage: CGImage) async -> CIImage? {
        guard let lifted = await SubjectLifter.lift(UIImage(cgImage: cgImage)) else {
            return nil
        }
        return CIImage(image: lifted.subject)
    }

    private static func punch(_ image: CIImage) -> CIImage {
        let colors = CIFilter.colorControls()
        colors.inputImage = image
        colors.saturation = 1.38
        colors.contrast = 1.22
        colors.brightness = 0.02

        let vibrance = CIFilter.vibrance()
        vibrance.inputImage = colors.outputImage
        vibrance.amount = 0.5

        // Un leger halo sur les hautes lumieres : reflets de carrosserie appuyes.
        let bloom = CIFilter.bloom()
        bloom.inputImage = vibrance.outputImage
        bloom.radius = 9
        bloom.intensity = 0.45

        return bloom.outputImage ?? image
    }

    private static func rimLight(_ subject: CIImage, color: UIColor, in frame: CGRect) -> CIImage {
        // La silhouette pleine du sujet, coloree.
        let silhouette = CIFilter.colorMatrix()
        silhouette.inputImage = subject
        let components = color.rgba
        silhouette.rVector = CIVector(x: 0, y: 0, z: 0, w: components.r)
        silhouette.gVector = CIVector(x: 0, y: 0, z: 0, w: components.g)
        silhouette.bVector = CIVector(x: 0, y: 0, z: 0, w: components.b)
        silhouette.aVector = CIVector(x: 0, y: 0, z: 0, w: 0.9)

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = silhouette.outputImage
        blur.radius = Float(min(frame.width, frame.height) * 0.045)

        // Legerement agrandie, pour deborder du sujet et former le lisere lumineux.
        guard let blurred = blur.outputImage else { return CIImage.empty() }
        let scale = CGAffineTransform(scaleX: 1.06, y: 1.06)
            .concatenating(CGAffineTransform(translationX: -frame.width * 0.03,
                                             y: -frame.height * 0.03))
        return blurred.transformed(by: scale).cropped(to: frame)
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
        blur.radius = Float(min(frame.width, frame.height) * 0.05)

        guard let blurred = blur.outputImage else { return CIImage.empty() }
        // Ecrasee et posee sous le sujet.
        let squash = CGAffineTransform(scaleX: 1.0, y: 0.22)
            .concatenating(CGAffineTransform(translationX: 0, y: frame.height * 0.06))
        return blurred.transformed(by: squash).cropped(to: frame)
    }

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

    private static func backdrop(color: UIColor, in frame: CGRect) -> CIImage {
        let gradient = CIFilter.radialGradient()
        gradient.center = CGPoint(x: frame.midX, y: frame.midY + frame.height * 0.08)
        gradient.radius0 = Float(frame.width * 0.05)
        gradient.radius1 = Float(frame.width * 0.62)
        gradient.color0 = CIColor(color: color.withAlphaComponent(0.42))
        gradient.color1 = CIColor(red: 0.03, green: 0.02, blue: 0.05, alpha: 1)
        return (gradient.outputImage ?? CIImage(color: .black)).cropped(to: frame)
    }
}

private extension UIColor {
    var rgba: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}
