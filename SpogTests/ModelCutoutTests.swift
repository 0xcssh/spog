import Testing
import UIKit
@testable import Spog

/// La découpe d'un rendu embarqué par son masque livré : sans Vision, elle marche aussi
/// dans le simulateur, et c'est elle qu'on voit en attendant le rendu HD.
struct ModelCutoutTests {

    private func image(_ size: CGSize, _ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
    }

    @Test("La découpe est recadrée aux bords du masque")
    func croppedToMask() throws {
        let size = CGSize(width: 100, height: 50)
        let render = image(size) { ctx in
            ctx.setFillColor(UIColor.red.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let mask = image(size) { ctx in
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            // Gris sous le seuil : le bruit d'un JPEG autour de la voiture, hors de la boîte.
            ctx.setFillColor(UIColor(white: 0.3, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 50))
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(CGRect(x: 20, y: 10, width: 40, height: 30))
        }

        let cutout = try #require(ModelCutoutService.maskedCutout(render, mask: mask))
        #expect(cutout.size == CGSize(width: 40, height: 30))
    }

    @Test("Un masque vide ne donne aucune découpe")
    func emptyMask() {
        let size = CGSize(width: 40, height: 20)
        let render = image(size) { ctx in
            ctx.setFillColor(UIColor.blue.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let mask = image(size) { ctx in
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        #expect(ModelCutoutService.maskedCutout(render, mask: mask) == nil)
    }
}
