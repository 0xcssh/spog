import UIKit
import Vision
import CoreImage

/// Une photo separee en deux plans.
struct LiftedPhoto {
    /// Le sujet detoure, **recadre a ses propres bords**, fond transparent.
    let subject: UIImage
    let background: UIImage   // le decor
    /// Ou se trouve le sujet dans la photo : coordonnees normalisees (0…1), origine en
    /// haut a gauche comme UIKit. C'est ce qui permet de cadrer la carte sur la voiture
    /// plutot qu'au milieu de la photo.
    let bounds: CGRect
    /// Part de sa boite que le sujet remplit vraiment. Une voiture de profil ou de trois
    /// quarts en couvre bien plus de la moitie ; un masque troue, ou etale sur un bout de
    /// trottoir, beaucoup moins. Sert a juger si le detourage est assez propre pour
    /// etre montre.
    let fill: Double
    /// Le masque du sujet a la taille de la photo (blanc = sujet), pret pour CoreImage.
    let mask: CIImage
}

/// Un sujet detoure seul, sans la photo autour.
struct SubjectCutout {
    /// Le sujet, recadre a ses propres bords, fond transparent.
    let image: UIImage
    /// Sa boite dans l'image d'origine, normalisee (0…1), origine en haut a gauche.
    let bounds: CGRect
    /// Part de sa boite que le sujet remplit (voir `LiftedPhoto.fill`).
    let fill: Double
}

/// Detoure le sujet principal d'une photo avec Vision, entierement sur l'appareil.
/// Aucun appel reseau, aucun cout.
enum SubjectLifter {

    private static let context = CIContext()

    /// - Parameter image: une photo aux pixels droits (`UprightPhoto`). Vision lit les
    ///   pixels bruts et ignore l'orientation de l'image.
    static func lift(_ image: UIImage) async -> LiftedPhoto? {
        guard let cgImage = image.cgImage, let found = detect(in: cgImage),
              let subject = croppedSubject(found),
              let scaledMask = try? found.result.generateScaledMaskForImage(forInstances: found.instances,
                                                                            from: found.handler)
        else { return nil }
        return LiftedPhoto(subject: subject, background: image,
                           bounds: found.bounds, fill: found.fill,
                           mask: CIImage(cvPixelBuffer: scaledMask))
    }

    /// Le sujet seul, recadre a ses bords sur fond transparent : ce que le studio des
    /// modeles pose sur son propre decor (`ModelCutoutService`). Sans le masque plein
    /// format que `lift` calcule pour adoucir le decor d'une photo, inutile ici.
    ///
    /// Synchrone et lourd (inference Vision) : a appeler hors du fil principal.
    static func cutout(_ image: UIImage) -> SubjectCutout? {
        guard let cgImage = image.cgImage, let found = detect(in: cgImage),
              let subject = croppedSubject(found) else { return nil }
        return SubjectCutout(image: subject, bounds: found.bounds, fill: found.fill)
    }

    /// Ce que Vision a trouve : le plus grand sujet, et de quoi en tirer les images.
    private struct Detection {
        let result: VNInstanceMaskObservation
        let handler: VNImageRequestHandler
        let instances: IndexSet
        let bounds: CGRect
        let fill: Double
    }

    private static func detect(in cgImage: CGImage) -> Detection? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        do { try handler.perform([request]) } catch { return nil }

        guard let result = request.results?.first, !result.allInstances.isEmpty,
              let largest = largestInstance(in: result.instanceMask)
        else { return nil }

        // **Le plus grand sujet seul**, pas tous. Vision sort aussi le passant, la voiture
        // garee derriere, le scooter : les garder etirait la boite sur toute la rue, et
        // la carte se cadrait sur le trottoir.
        return Detection(result: result, handler: handler,
                         instances: IndexSet(integer: largest.label),
                         bounds: largest.bounds, fill: largest.fill)
    }

    private static func croppedSubject(_ found: Detection) -> UIImage? {
        guard let masked = try? found.result.generateMaskedImage(ofInstances: found.instances,
                                                                 from: found.handler,
                                                                 croppedToInstancesExtent: true)
        else { return nil }
        // Rendu explicite en CGImage : sans quoi l'image n'a pas de bitmap exploitable
        // par la suite de la chaine.
        let ciSubject = CIImage(cvPixelBuffer: masked)
        guard let cgSubject = context.createCGImage(ciSubject, from: ciSubject.extent) else {
            return nil
        }
        return UIImage(cgImage: cgSubject)
    }

    // MARK: Mesure du sujet

    /// Le plus grand sujet du masque d'instances de Vision : une image basse definition
    /// ou chaque pixel porte le numero de son sujet (0 = decor).
    private static func largestInstance(in buffer: CVPixelBuffer)
        -> (label: Int, bounds: CGRect, fill: Double)? {
        // Un octet par pixel attendu ; dans tout autre format, on renonce plutot que de
        // lire n'importe quoi — la carte se cadrera simplement au centre.
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent8 else {
            return nil
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        return measureLargest(width: CVPixelBufferGetWidth(buffer),
                              height: CVPixelBufferGetHeight(buffer)) { x, y in
            pixels[y * rowBytes + x]
        }
    }

    /// Boite et remplissage du sujet le plus etendu, sur une grille de numeros.
    /// Separee de Vision pour etre testable sans modele d'inference.
    static func measureLargest(width: Int, height: Int,
                               label: (_ x: Int, _ y: Int) -> UInt8)
        -> (label: Int, bounds: CGRect, fill: Double)? {
        guard width > 0, height > 0 else { return nil }
        var count = [Int](repeating: 0, count: 256)
        var minX = [Int](repeating: .max, count: 256), minY = [Int](repeating: .max, count: 256)
        var maxX = [Int](repeating: -1, count: 256), maxY = [Int](repeating: -1, count: 256)

        for y in 0..<height {
            for x in 0..<width {
                let l = Int(label(x, y))
                guard l != 0 else { continue }
                count[l] += 1
                minX[l] = min(minX[l], x); maxX[l] = max(maxX[l], x)
                minY[l] = min(minY[l], y); maxY[l] = max(maxY[l], y)
            }
        }

        guard let best = (1..<256).max(by: { count[$0] < count[$1] }), count[best] > 0 else {
            return nil
        }
        let boxWidth = maxX[best] - minX[best] + 1
        let boxHeight = maxY[best] - minY[best] + 1
        let bounds = CGRect(x: CGFloat(minX[best]) / CGFloat(width),
                            y: CGFloat(minY[best]) / CGFloat(height),
                            width: CGFloat(boxWidth) / CGFloat(width),
                            height: CGFloat(boxHeight) / CGFloat(height))
        return (best, bounds, Double(count[best]) / Double(boxWidth * boxHeight))
    }
}
