import UIKit

/// Visuel studio d'un modèle du catalogue, pour les cibles du pack de primes.
///
/// Le pack montrait la même silhouette pour ses trois cibles : le joueur devait chercher
/// ailleurs à quoi ressemblait la voiture qu'on lui demandait de repérer. L'ordre de
/// recherche, du gratuit au payant :
///
/// 1. le rendu embarqué (`CarArt`), s'il existe — aucun réseau ;
/// 2. le rendu déjà téléchargé, rangé sur le disque ;
/// 3. l'action `vehicle_art` du serveur (voir backend/functions/identify/art.ts), qui ne
///    génère l'image qu'une fois par modèle pour tous les joueurs. La première demande
///    peut prendre vingt-cinq secondes : l'appelant affiche la silhouette en attendant.
enum VehicleArtService {

    private struct Payload: Decodable {
        let image: String?
    }

    private static let memory = NSCache<NSString, UIImage>()
    private static let flights = ArtFlights()

    /// Dossier des caches, pas des documents : ces images se retéléchargent, iOS peut les
    /// effacer quand l'espace manque sans que le joueur perde rien. Les photos du joueur,
    /// elles, vivent dans les documents (ShotStore), parce qu'elles sont irremplaçables.
    private static var directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("vehicle-art", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    /// Nom de fichier sûr : l'identifiant vient du serveur, on n'en garde que les
    /// caractères d'un identifiant de catalogue.
    private static func fileURL(_ vehicleID: String) -> URL {
        let safe = String(vehicleID.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }.map { Character($0) })
        return directory.appendingPathComponent("\(safe).jpg")
    }

    /// Ce qui est disponible tout de suite, sans réseau. Nil : il faudra demander au serveur.
    static func cachedImage(for vehicleID: String) -> UIImage? {
        if let art = CarArt.image(for: vehicleID) { return art }
        let key = vehicleID as NSString
        if let hit = memory.object(forKey: key) { return hit }
        guard let data = try? Data(contentsOf: fileURL(vehicleID)),
              let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key)
        return image
    }

    /// L'image du modèle, téléchargée si besoin. Nil si le serveur refuse (modèle qui n'est
    /// pas une cible cette semaine) ou ne répond pas : la silhouette reste alors affichée.
    static func image(for vehicleID: String) async -> UIImage? {
        if let hit = cachedImage(for: vehicleID) { return hit }
        return await flights.run(vehicleID) { await VehicleArtService.download(vehicleID) }
    }

    /// Lance les téléchargements sans attendre : à l'ouverture du pack, les trois rendus
    /// partent en même temps plutôt qu'un par un au fil de l'affichage.
    static func prefetch(_ vehicleIDs: [String]) {
        for id in vehicleIDs where cachedImage(for: id) == nil {
            Task { _ = await VehicleArtService.image(for: id) }
        }
    }

    private static func download(_ vehicleID: String) async -> UIImage? {
        // Délai long : la première demande d'un modèle déclenche une génération (~25 s).
        let result = await Backend.call(["action": "vehicle_art", "vehicle_id": vehicleID],
                                        as: Payload.self, timeout: 75)
        guard result.status == 200, let base64 = result.value?.image,
              let data = Data(base64Encoded: base64),
              let image = UIImage(data: data) else { return nil }
        try? data.write(to: fileURL(vehicleID), options: .atomic)
        memory.setObject(image, forKey: vehicleID as NSString)
        return image
    }
}

/// Une seule requête par modèle à la fois : la grille du garage et l'écran d'ouverture
/// peuvent demander la même cible à la même seconde, et chaque génération se paie.
private actor ArtFlights {
    private var tasks: [String: Task<UIImage?, Never>] = [:]

    func run(_ key: String, _ work: @escaping @Sendable () async -> UIImage?) async -> UIImage? {
        if let running = tasks[key] { return await running.value }
        let task = Task { await work() }
        tasks[key] = task
        let value = await task.value
        tasks[key] = nil
        return value
    }
}
