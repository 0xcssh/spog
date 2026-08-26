import UIKit
import Vision
import CoreImage

/// Une photo separee en deux plans.
struct LiftedPhoto {
    let subject: UIImage      // le sujet detoure, fond transparent
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
                                                           croppedToInstancesExtent: false)
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
