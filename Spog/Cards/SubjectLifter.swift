import UIKit
import Vision
import CoreImage

/// Une photo separee en deux plans.
struct LiftedPhoto {
    /// Le sujet detoure, **recadre a ses propres bords**, fond transparent.
    /// Le recadrage n'est pas un detail : sans lui, la voiture reste la ou elle etait
    /// sur la photo — souvent collee a un bord, parfois coupee — et la mise en scene
    /// ne peut ni la centrer ni la poser sur un sol.
    let subject: UIImage
    let background: UIImage   // le decor
}

/// Detoure le sujet principal d'une photo avec Vision, entierement sur l'appareil.
/// Aucun appel reseau, aucun cout.
enum SubjectLifter {

    private static let context = CIContext()

    static func lift(_ image: UIImage) async -> LiftedPhoto? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        do { try handler.perform([request]) } catch { return nil }

        guard let result = request.results?.first, !result.allInstances.isEmpty,
              let masked = try? result.generateMaskedImage(ofInstances: result.allInstances,
                                                           from: handler,
                                                           croppedToInstancesExtent: true)
        else { return nil }

        // Rendu explicite en CGImage : sans quoi l'image n'a pas de bitmap exploitable
        // par la suite de la chaine.
        let ciSubject = CIImage(cvPixelBuffer: masked)
        guard let cgSubject = context.createCGImage(ciSubject, from: ciSubject.extent) else {
            return nil
        }
        return LiftedPhoto(subject: UIImage(cgImage: cgSubject), background: image)
    }
}
