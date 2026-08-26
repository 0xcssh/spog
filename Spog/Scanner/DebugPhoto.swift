import UIKit

/// TEMP — à retirer avec la vraie caméra.
/// Le simulateur n'a pas de caméra : cette photo de synthèse permet d'éprouver
/// la chaîne complète (masquage de plaque, mise en scène, carte) sans appareil.
enum DebugPhoto {

    static func sample() -> UIImage {
        let size = CGSize(width: 1200, height: 900)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext

            // Décor
            let sky = [UIColor(white: 0.30, alpha: 1).cgColor,
                       UIColor(white: 0.14, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: sky, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero,
                                      end: CGPoint(x: 0, y: size.height), options: [])
            }

            // Caisse
            UIColor(red: 0.16, green: 0.32, blue: 0.55, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 170, y: 300, width: 860, height: 380),
                         cornerRadius: 70).fill()
            UIColor(white: 0.08, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 320, y: 210, width: 540, height: 150),
                         cornerRadius: 50).fill()

            // Roues
            UIColor(white: 0.06, alpha: 1).setFill()
            for x in [300.0, 800.0] {
                UIBezierPath(ovalIn: CGRect(x: x, y: 590, width: 160, height: 160)).fill()
            }

            // Plaque : fond blanc, texte noir, format français
            let plate = CGRect(x: 490, y: 560, width: 240, height: 62)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: plate, cornerRadius: 8).fill()
            let text = "AB-123-CD" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 40, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: plate.midX - textSize.width / 2,
                                  y: plate.midY - textSize.height / 2),
                      withAttributes: attributes)
        }
    }
}
