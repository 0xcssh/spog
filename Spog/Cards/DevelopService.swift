import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// « Passer en studio » : le serveur génère un rendu studio de la voiture photographiée,
/// à partir de la photo du joueur (voir backend/functions/identify/develop.ts), dans le
/// même studio que les rendus du catalogue.
///
/// Le rendu garde ce qui fait cette voiture-là — sa teinte, ses jantes, son covering —,
/// c'est ce qui le distingue d'une illustration de catalogue. Il prend une vingtaine de
/// secondes : le serveur relaie en flux les images intermédiaires d'OpenAI, et la carte
/// prend forme sous les yeux du joueur au lieu de rester voilée jusqu'au bout (retour
/// testeur du 09/10/2026 : « la génération a pris énormément de temps »).
enum DevelopService {

    enum Failure: Error {
        /// Rendu du jour déjà utilisé : 1 par jour en gratuit, Pro illimité.
        case limit(resetsAt: Date?)
        case failed
    }

    /// Le rendu, et le décompte du jour que le serveur renvoie avec lui : de quoi tenir à
    /// jour le miroir affiché sous le bouton (« 1 gratuit aujourd'hui »).
    struct Developed {
        let image: UIImage
        /// Rendus restants aujourd'hui ; nil pour un abonné, qui n'a pas de quota.
        let left: Int?
        let resetsAt: Date?
    }

    /// - Parameters:
    ///   - photo: le cliché du joueur (plaques déjà floutées), pas la version mise en
    ///     scène : le modèle d'image a besoin de la vraie lumière pour rester fidèle.
    ///   - onPartial: chaque image intermédiaire, déjà adoucie selon son rang. Jamais
    ///     appelé par un serveur qui répond d'un bloc (pas encore déployé, ou refus).
    static func develop(_ photo: UIImage, entitlement: String?,
                        onPartial: @escaping @MainActor (UIImage) -> Void = { _ in }) async -> Result<Developed, Failure> {
        guard let jpeg = resized(photo, maxSide: 1024).jpegData(compressionQuality: 0.85) else {
            return .failure(.failed)
        }
        // `stream` et l'en-tête Accept annoncent que ce build sait lire le flux ; un ancien
        // build, qui ne les envoie pas, reçoit toujours une réponse JSON d'un bloc.
        var body: [String: Any] = ["action": "develop", "imageBase64": jpeg.base64EncodedString(), "stream": true]
        if let entitlement { body["entitlement"] = entitlement }
        // Une génération d'image dépasse largement le délai d'une identification. Le délai
        // d'URLSession court entre deux paquets : il ne coupe pas un flux qui avance.
        guard var request = Backend.request(body, timeout: 90) else { return .failure(.failed) }
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        guard let (bytes, response) = try? await URLSession.shared.bytes(for: request),
              let http = response as? HTTPURLResponse else { return .failure(.failed) }

        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard contentType.contains("text/event-stream") else {
            // Réponse d'un bloc : un refus (402, 5xx), ou un serveur qui ignore `stream`.
            var data = Data()
            do {
                for try await byte in bytes { data.append(byte) }
            } catch {
                return .failure(.failed)
            }
            return outcome(status: http.statusCode, payload: try? JSONDecoder().decode(DevelopPayload.self, from: data))
        }

        // Découpage en lignes à la main : `bytes.lines` saute les lignes vides, qui sont
        // justement ce qui clôt un événement SSE.
        var decoder = SSEDecoder()
        var line: [UInt8] = []
        do {
            for try await byte in bytes {
                guard byte == 0x0A else {
                    line.append(byte)
                    continue
                }
                let text = String(decoding: line, as: UTF8.self)
                line.removeAll(keepingCapacity: true)
                guard let event = decoder.feed(text), let parsed = DevelopStreamEvent(event) else { continue }
                switch parsed {
                case .partial(let data, let index):
                    if let image = UIImage(data: data) {
                        let shown = softened(image, radius: partialBlur(index))
                        await onPartial(shown)
                    }
                case .done(let payload):
                    return outcome(status: 200, payload: payload)
                case .failure(let code):
                    return code == "develop_limit" ? .failure(.limit(resetsAt: nil)) : .failure(.failed)
                }
            }
        } catch {
            return .failure(.failed)
        }
        // Flux fermé sans rendu final : le serveur n'a rien décompté.
        return .failure(.failed)
    }

    /// Le résultat d'une réponse complète, qu'elle vienne d'un bloc JSON ou de l'événement
    /// `done` du flux.
    private static func outcome(status: Int, payload: DevelopPayload?) -> Result<Developed, Failure> {
        let reset = payload?.resets_at.flatMap { ISO8601DateFormatter.withFractions.date(from: $0) }
        if status == 402 || payload?.code == "develop_limit" {
            return .failure(.limit(resetsAt: reset))
        }
        guard status == 200, let base64 = payload?.image,
              let data = Data(base64Encoded: base64), let image = UIImage(data: data) else {
            return .failure(.failed)
        }
        return .success(Developed(image: image, left: payload?.develops_left, resetsAt: reset))
    }

    /// Flou ajouté aux images intermédiaires, en pixels d'une image de 1024 : la première
    /// très douce, la suivante presque nette. La carte passe du flou au net au lieu de
    /// montrer des détails encore faux comme s'ils étaient définitifs.
    static func partialBlur(_ index: Int) -> Double {
        switch index {
        case ..<1: return 14
        case 1: return 6
        default: return 3
        }
    }

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    private static func softened(_ image: UIImage, radius: Double) -> UIImage {
        guard radius > 0, let input = CIImage(image: image) else { return image }
        let blur = CIFilter.gaussianBlur()
        // Bords étendus avant le flou, puis recadrage : sans quoi le pourtour s'assombrit.
        blur.inputImage = input.clampedToExtent()
        blur.radius = Float(radius)
        guard let output = blur.outputImage?.cropped(to: input.extent),
              let cg = context.createCGImage(output, from: input.extent) else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
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
