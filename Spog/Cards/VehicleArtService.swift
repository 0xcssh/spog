import UIKit

/// Rendu studio haute définition d'un modèle du catalogue (1024 × 1024, au format des
/// cartes), pour tout ce que l'app montre sans photo du joueur.
///
/// Les rendus embarqués (`CarArt`, 660 × 290) sont des bandeaux : dans une carte presque
/// carrée, la voiture n'en occupait que la moitié haute, floue dès qu'on l'agrandissait.
/// Le serveur génère désormais un rendu carré par modèle, une seule fois pour tous les
/// joueurs. L'ordre de recherche, du gratuit au payant :
///
/// 1. le rendu HD déjà téléchargé, en mémoire puis sur le disque ;
/// 2. l'action `vehicle_art` du serveur (voir backend/functions/identify/art.ts). La
///    première demande d'un modèle déclenche une génération qui peut prendre une
///    trentaine de secondes : l'appelant montre le rendu embarqué ou la silhouette en
///    attendant (c'est ce que fait `ModelArt`) ;
/// 3. à défaut, le rendu embarqué `CarArt`, toujours là, mais en bandeau.
enum VehicleArtService {

    private struct Payload: Decodable {
        let image: String?
    }

    /// Une image 1024² décodée pèse 4 Mo : la mémoire n'en garde qu'une poignée, le disque
    /// sert le reste en quelques millisecondes.
    private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 40
        return cache
    }()
    private static let flights = ArtFlights()

    /// Dossier des caches, pas des documents : ces images se retéléchargent, iOS peut les
    /// effacer quand l'espace manque sans que le joueur perde rien. Les photos du joueur,
    /// elles, vivent dans les documents (ShotStore), parce qu'elles sont irremplaçables.
    ///
    /// `vehicle-art-v2` : l'ancien dossier `vehicle-art` contenait des bandeaux 1536 × 1024
    /// que le nouveau cadrage plein couperait. On le supprime une fois, plutôt que de les
    /// resservir pour toujours.
    private static var directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        // `v4` : rendus sans emblème, voiture un peu plus petite (vehicles/v4 côté serveur).
        // Les dossiers d'avant (bandeaux, décors néon, rendus avec logos) sont supprimés une fois.
        for old in ["vehicle-art", "vehicle-art-v2", "vehicle-art-v3"] {
            try? FileManager.default.removeItem(at: base.appendingPathComponent(old, isDirectory: true))
        }
        let folder = base.appendingPathComponent("vehicle-art-v4", isDirectory: true)
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

    /// Ce qui est disponible tout de suite, sans réseau : le rendu HD s'il est déjà là,
    /// sinon le rendu embarqué. Nil : il faudra demander au serveur.
    static func cachedImage(for vehicleID: String) -> UIImage? {
        storedImage(for: vehicleID) ?? CarArt.image(for: vehicleID)
    }

    /// Le rendu HD seul, s'il est déjà sur l'appareil. Sert à `ModelArt`, qui doit savoir
    /// s'il tient le rendu définitif ou seulement le bandeau embarqué en attendant.
    /// En mémoire seulement, sans disque : de quoi afficher dès la première image d'une vue.
    static func memoryImage(for vehicleID: String) -> UIImage? {
        vehicleID.isEmpty ? nil : memory.object(forKey: vehicleID as NSString)
    }

    static func storedImage(for vehicleID: String) -> UIImage? {
        guard !vehicleID.isEmpty else { return nil }
        let key = vehicleID as NSString
        if let hit = memory.object(forKey: key) { return hit }
        guard let data = try? Data(contentsOf: fileURL(vehicleID)),
              let image = UIImage(data: data) else { return nil }
        let decoded = image.preparingForDisplay() ?? image
        memory.setObject(decoded, forKey: key)
        return decoded
    }

    /// L'image du modèle, sans jamais faire attendre plus que nécessaire : le rendu HD s'il
    /// est déjà là ; sinon le rendu embarqué tout de suite, pendant que le rendu HD se
    /// télécharge en arrière-plan pour la fois suivante ; sinon le téléchargement, attendu.
    /// Nil s'il n'y a rien du tout (la silhouette reste alors affichée).
    ///
    /// Le délai d'avant (instantané pour un modèle embarqué) est gardé exprès : des écrans
    /// attendent cette fonction avant de s'afficher. Pour attendre le rendu HD lui-même,
    /// c'est `remoteImage(for:)` — ce que fait `ModelArt`.
    static func image(for vehicleID: String) async -> UIImage? {
        if let hd = storedImage(for: vehicleID) { return hd }
        if let embedded = CarArt.image(for: vehicleID) {
            prefetch([vehicleID])
            return embedded
        }
        return await remoteImage(for: vehicleID)
    }

    /// Le rendu HD seul : depuis le cache, sinon depuis le serveur. Nil en cas d'échec.
    static func remoteImage(for vehicleID: String) async -> UIImage? {
        guard !vehicleID.isEmpty else { return nil }
        if let hit = storedImage(for: vehicleID) { return hit }
        return await flights.run(vehicleID) { await VehicleArtService.download(vehicleID) }
    }

    /// Lance les téléchargements sans attendre : à l'ouverture du pack, les trois rendus
    /// partent en même temps plutôt qu'un par un au fil de l'affichage.
    static func prefetch(_ vehicleIDs: [String]) {
        for id in vehicleIDs where storedImage(for: id) == nil {
            Task { _ = await VehicleArtService.remoteImage(for: id) }
        }
    }

    private static func download(_ vehicleID: String) async -> UIImage? {
        // Délai long : la première demande d'un modèle déclenche une génération en haute
        // qualité (~30 s, parfois plus quand OpenAI est chargé).
        let result = await Backend.call(["action": "vehicle_art", "vehicle_id": vehicleID],
                                        as: Payload.self, timeout: 90)
        guard result.status == 200, let base64 = result.value?.image,
              let data = Data(base64Encoded: base64),
              let image = UIImage(data: data) else { return nil }
        try? data.write(to: fileURL(vehicleID), options: .atomic)
        // Décodé ici, hors du fil principal : sinon c'est le premier affichage qui paie la
        // décompression d'un JPEG 1024², et la grille saccade au moment du fondu.
        let decoded = image.preparingForDisplay() ?? image
        memory.setObject(decoded, forKey: vehicleID as NSString)
        return decoded
    }
}

/// Une seule requête par modèle à la fois, et pas plus de quelques-unes en même temps.
///
/// La grille du garage et l'écran d'ouverture peuvent demander la même cible à la même
/// seconde, et chaque génération se paie. Une grille qui affiche douze cartes sans photo
/// ne doit pas non plus ouvrir douze connexions de quatre-vingt-dix secondes : au-delà de
/// `maxConcurrent`, les demandes attendent leur tour. Un échec est retenu quelques minutes,
/// pour qu'une vignette qui réapparaît en défilant ne relance pas une requête refusée.
private actor ArtFlights {
    private var tasks: [String: Task<UIImage?, Never>] = [:]
    private var failedUntil: [String: Date] = [:]
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private let maxConcurrent = 4
    private let failureCooldown: TimeInterval = 300

    func run(_ key: String, _ work: @escaping @Sendable () async -> UIImage?) async -> UIImage? {
        if let running = tasks[key] { return await running.value }
        if let until = failedUntil[key], until > Date() { return nil }
        let task = Task { () -> UIImage? in
            await self.acquire()
            let value = await work()
            await self.release()
            return value
        }
        tasks[key] = task
        let value = await task.value
        tasks[key] = nil
        if value == nil {
            failedUntil[key] = Date().addingTimeInterval(failureCooldown)
        } else {
            failedUntil[key] = nil
        }
        return value
    }

    private func acquire() async {
        if active < maxConcurrent {
            active += 1
            return
        }
        // La place est transmise directement par `release` : `active` ne bouge pas.
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty {
            active -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}
