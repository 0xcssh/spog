import UIKit

/// Illustrations de vehicules embarquees, une par identifiant du catalogue.
/// Produites une seule fois par `tools/generate-car-art.py`, donc aucun cout
/// ni appel reseau a l'usage. Tant qu'un modele n'a pas son illustration,
/// la carte retombe sur le rendu 3D genere.
enum CarArt {

    private static var cache: [String: UIImage] = [:]
    private static let lock = NSLock()

    /// Cherche le rendu du modele, d'abord dans la teinte demandee,
    /// sinon dans la teinte de reference.
    static func image(for vehicleID: String, paint: UInt32? = nil) -> UIImage? {
        var candidates: [String] = []
        if let paint { candidates.append(vehicleID + "--" + CarPaint.slug(paint)) }
        candidates.append(vehicleID + "--metallic-silver")
        candidates.append(vehicleID)

        lock.lock(); defer { lock.unlock() }
        for name in candidates {
            if let hit = cache[name] { return hit }
            // JPEG d'abord : c'est le format des illustrations produites en lot, six cents
            // PNG pesant trois fois plus lourd dans le bundle pour une photo.
            for ext in ["jpg", "png"] {
                if let url = Bundle.main.url(forResource: name, withExtension: ext),
                   let image = UIImage(contentsOfFile: url.path) {
                    cache[name] = image
                    return image
                }
            }
        }
        return nil
    }
}
