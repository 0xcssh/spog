import UIKit

/// Range les photos sur le disque et les relit a la demande.
/// Les images ne sont jamais gardees toutes en memoire : une collection de
/// plusieurs centaines de cartes tiendrait sinon plusieurs gigaoctets.
enum ShotStore {

    private static let cache = NSCache<NSString, UIImage>()

    private static var directory: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    private static func url(_ id: UUID, _ kind: String) -> URL {
        directory.appendingPathComponent("\(id.uuidString)-\(kind).jpg")
    }

    /// Ecrit les deux images en JPEG. Compression volontaire : le poids du garage
    /// compte plus que le dernier pourcent de qualite.
    static func save(_ shot: StyledShot, for id: UUID) {
        try? shot.original.jpegData(compressionQuality: 0.82)?.write(to: url(id, "o"))
        try? shot.stylized.jpegData(compressionQuality: 0.86)?.write(to: url(id, "s"))
    }

    static func load(_ id: UUID) -> StyledShot? {
        guard let original = image(id, "o"), let stylized = image(id, "s") else { return nil }
        return StyledShot(stylized: stylized, original: original, developed: image(id, "d"))
    }

    /// Range le rendu studio d'une carte developpee, a cote de ses deux photos.
    static func saveDeveloped(_ image: UIImage, for id: UUID) {
        try? image.jpegData(compressionQuality: 0.88)?.write(to: url(id, "d"))
        cache.removeObject(forKey: key(id, "d"))
    }

    static func delete(_ id: UUID) {
        for kind in ["o", "s", "d"] {
            try? FileManager.default.removeItem(at: url(id, kind))
            cache.removeObject(forKey: key(id, kind))
        }
    }

    private static func key(_ id: UUID, _ kind: String) -> NSString {
        "\(id.uuidString)-\(kind)" as NSString
    }

    private static func image(_ id: UUID, _ kind: String) -> UIImage? {
        if let hit = cache.object(forKey: key(id, kind)) { return hit }
        guard let data = try? Data(contentsOf: url(id, kind)),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key(id, kind))
        return image
    }
}
