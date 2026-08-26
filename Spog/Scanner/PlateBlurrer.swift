import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// Masque les plaques d'immatriculation détectées dans une photo.
///
/// Une plaque est une donnée personnelle en Europe. Le masquage a lieu **avant**
/// tout enregistrement et toute transmission : la photo conservée sur l'appareil
/// est déjà anonymisée, pas seulement celle qui part au serveur.
///
/// Entièrement sur l'appareil, aucun appel réseau, aucun coût.
enum PlateBlurrer {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Proportions plausibles d'une plaque selon les pays : ~4,7:1 en Europe,
    /// ~2:1 en Amérique du Nord. On accepte large, quitte à masquer un peu trop.
    private static let ratioRange: ClosedRange<CGFloat> = 1.6...7.0

    /// - Returns: la photo avec les plaques masquées, et le nombre de zones traitées.
    static func mask(_ photo: UIImage) async -> (image: UIImage, masked: Int) {
        guard let cgImage = photo.cgImage else { return (photo, 0) }

        let boxes = await detect(in: cgImage)
        guard !boxes.isEmpty else { return (photo, 0) }

        guard let result = apply(boxes, to: cgImage) else { return (photo, 0) }
        return (UIImage(cgImage: result, scale: photo.scale, orientation: photo.imageOrientation),
                boxes.count)
    }

    // MARK: Détection

    /// Rectangles à masquer, en coordonnées normalisées Vision (origine en bas à gauche).
    private static func detect(in cgImage: CGImage) async -> [CGRect] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast          // on cherche des formes, pas du sens
        request.usesLanguageCorrection = false    // une plaque n'est pas un mot
        request.minimumTextHeight = 0.012

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let observations = request.results else { return [] }

        return observations.compactMap { observation -> CGRect? in
            let box = observation.boundingBox
            guard box.height > 0 else { return nil }

            let ratio = box.width / box.height
            guard ratioRange.contains(ratio) else { return nil }
            // Ni un détail minuscule, ni la moitié de l'image : ce ne serait pas une plaque.
            guard box.width > 0.03, box.width < 0.7 else { return nil }

            guard let text = observation.topCandidates(1).first?.string,
                  looksLikePlate(text) else { return nil }
            return box
        }
    }

    /// Une plaque mêle lettres et chiffres, en majuscules, sur quelques caractères.
    /// Ce filtre évite de masquer les enseignes et les inscriptions de carrosserie.
    private static func looksLikePlate(_ text: String) -> Bool {
        let stripped = text.filter { !$0.isWhitespace && $0 != "-" && $0 != "·" }
        guard (4...10).contains(stripped.count) else { return false }

        let digits = stripped.filter(\.isNumber).count
        let letters = stripped.filter(\.isLetter).count
        guard digits >= 2, letters >= 1, digits + letters == stripped.count else { return false }

        let uppercase = stripped.filter { $0.isLetter && $0.isUppercase }.count
        return uppercase >= letters - 1   // une lettre mal lue est tolérée
    }

    // MARK: Masquage

    private static func apply(_ boxes: [CGRect], to cgImage: CGImage) -> CGImage? {
        let source = CIImage(cgImage: cgImage)
        let frame = source.extent

        // Pixellisation plutôt que flou : l'anonymisation se voit, et ne se devine pas.
        let pixellate = CIFilter.pixellate()
        pixellate.inputImage = source
        pixellate.scale = Float(max(frame.width, frame.height) * 0.018)
        pixellate.center = CGPoint(x: frame.midX, y: frame.midY)
        guard let pixellated = pixellate.outputImage?.cropped(to: frame) else { return nil }

        guard let mask = maskImage(boxes, in: frame) else { return nil }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = pixellated
        blend.backgroundImage = source
        blend.maskImage = mask
        guard let output = blend.outputImage?.cropped(to: frame) else { return nil }

        return context.createCGImage(output, from: frame)
    }

    /// Blanc là où il faut masquer, noir ailleurs. Les zones sont élargies :
    /// la détection cadre le texte, pas le support de la plaque.
    private static func maskImage(_ boxes: [CGRect], in frame: CGRect) -> CIImage? {
        // Échelle forcée à 1 : sinon le rendu suit la densité de l'écran (3× sur un
        // iPhone récent) et le masque, trois fois plus grand que la photo, se retrouve
        // décalé. C'est ce qui laissait la plaque intacte.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: frame.size, format: format)
        let image = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: frame.size))
            UIColor.white.setFill()
            for box in boxes {
                // Vision compte depuis le bas, UIKit depuis le haut.
                var rect = CGRect(x: box.minX * frame.width,
                                  y: (1 - box.maxY) * frame.height,
                                  width: box.width * frame.width,
                                  height: box.height * frame.height)
                rect = rect.insetBy(dx: -rect.width * 0.14, dy: -rect.height * 0.55)
                UIBezierPath(roundedRect: rect, cornerRadius: rect.height * 0.18).fill()
            }
        }
        guard let cgMask = image.cgImage else { return nil }
        return CIImage(cgImage: cgMask)
    }
}
