import UIKit

/// « Développer » une carte : le serveur génère un rendu studio de la voiture
/// photographiée, à partir de la photo du joueur (voir backend/functions/identify/develop.ts).
///
/// Le rendu garde ce qui fait cette voiture-là — sa teinte, ses jantes, son covering —,
/// c'est ce qui le distingue d'une illustration de catalogue. Il prend une vingtaine de
/// secondes : l'écran en fait un moment (le développement d'un tirage), pas une attente.
enum DevelopService {

    enum Failure: Error {
        /// Rendu du jour déjà utilisé : 1 par jour en gratuit, Pro illimité.
        case limit(resetsAt: Date?)
        case failed
    }

    private struct Payload: Decodable {
        let image: String?
        let code: String?
        let resets_at: String?
    }

    /// - Parameter photo: le cliché du joueur (plaques déjà floutées), pas la version
    ///   mise en scène : le modèle d'image a besoin de la vraie lumière pour rester fidèle.
    static func develop(_ photo: UIImage, entitlement: String?) async -> Result<UIImage, Failure> {
        guard let jpeg = resized(photo, maxSide: 1024).jpegData(compressionQuality: 0.85) else {
            return .failure(.failed)
        }
        var body: [String: Any] = ["action": "develop", "imageBase64": jpeg.base64EncodedString()]
        if let entitlement { body["entitlement"] = entitlement }
        // Une génération d'image dépasse largement le délai d'une identification.
        let result = await Backend.call(body, as: Payload.self, timeout: 90)
        if result.status == 402 || result.value?.code == "develop_limit" {
            let reset = result.value?.resets_at.flatMap { ISO8601DateFormatter.withFractions.date(from: $0) }
            return .failure(.limit(resetsAt: reset))
        }
        guard result.status == 200, let base64 = result.value?.image,
              let data = Data(base64Encoded: base64), let image = UIImage(data: data) else {
            return .failure(.failed)
        }
        return .success(image)
    }

    private static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        guard scale < 1 else { return image }
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
