import UIKit

/// La voiture seule, détourée de son rendu, prête à poser sur le studio unique
/// (`StudioStage`).
///
/// Deux sources, deux méthodes :
/// - le rendu haute définition du serveur (`VehicleArtService`) : détouré par Vision, sur
///   l'appareil. Les rendus déjà générés gardent leur décor de néons ; on ne paie pas pour
///   les refaire, on les découpe ;
/// - le rendu embarqué `CarArt` : son masque est livré avec lui (`<id>-mask.jpg`), Vision
///   n'a rien à deviner — et il n'existe pas dans le simulateur.
///
/// Une découpe se calcule **une fois par modèle** puis vit sur le disque (PNG avec
/// transparence), et tout le travail se fait hors du fil principal. Nil quand le détourage
/// échoue : l'appelant montre alors le rendu tel quel, en plein cadre, comme avant.
enum ModelCutoutService {

    /// Une découpe HD de 900 × 400 décodée pèse 1,4 Mo : la mémoire en garde une
    /// soixantaine, le disque sert le reste.
    private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 60
        return cache
    }()
    /// Vision à la file, une découpe après l'autre : une grille qui en demande douze d'un
    /// coup ne charge pas douze modèles d'inférence en mémoire.
    private static let visionFlights = CutoutFlights()
    /// Les découpes par masque sont légères : elles ne patientent pas derrière Vision.
    private static let maskFlights = CutoutFlights()
    /// Échecs de la session, retentés au prochain lancement : un détourage peut échouer
    /// pour une raison passagère (app en arrière-plan, mémoire).
    private static let failures = FailureMemo()

    /// Dossier des caches : tout se recalcule à partir des rendus, iOS peut l'effacer.
    /// `v1` : changer la méthode de découpe, c'est changer de dossier — les anciennes
    /// découpes ne doivent pas être resservies, ni les échecs qu'elle a notés.
    private static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("model-cutouts-v1", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    // MARK: Clés

    /// Même filtre que `VehicleArtService` : l'identifiant devient un nom de fichier.
    private static func safe(_ vehicleID: String) -> String {
        String(vehicleID.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }.map { Character($0) })
    }

    /// Clé de la découpe du rendu HD : sert aussi au cache des calques du studio.
    static func hdKey(_ vehicleID: String) -> String { "hd-\(safe(vehicleID))" }

    /// Clé de la découpe du rendu embarqué, à la teinte de la voiture (le garage repeint
    /// le rendu embarqué ; le rendu HD, lui, garde la sienne).
    static func embeddedKey(_ vehicleID: String, paint: UInt32?) -> String {
        "art-\(safe(vehicleID))-\(String(paint ?? CarArt.referencePaint, radix: 16))"
    }

    private static func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent("\(key).png")
    }

    /// Marque d'une découpe jugée inexploitable : Vision a bien répondu, mais pas une
    /// voiture montrable. Le résultat ne changera pas, inutile de relancer l'inférence à
    /// chaque lancement.
    private static func rejectURL(_ key: String) -> URL {
        directory.appendingPathComponent("\(key).rejected")
    }

    // MARK: Lecture immédiate

    /// En mémoire seulement, sans disque : de quoi afficher dès la première image d'une vue.
    static func memoryCutout(_ key: String) -> UIImage? {
        memory.object(forKey: key as NSString)
    }

    /// La découpe HD si elle a déjà été faite (mémoire, puis disque). Ne lance jamais
    /// Vision : sert au partage, qui part tout de suite.
    static func storedHDCutout(for vehicleID: String) -> UIImage? {
        stored(hdKey(vehicleID))
    }

    // MARK: Découpe

    /// La voiture détourée du rendu HD. Nil si Vision échoue ou rend une découpe douteuse.
    static func hdCutout(for vehicleID: String, from render: UIImage) async -> UIImage? {
        guard !vehicleID.isEmpty else { return nil }
        let key = hdKey(vehicleID)
        if let hit = memoryCutout(key) { return hit }
        if failures.contains(key) { return nil }
        let image = await visionFlights.run(key) {
            if let hit = ModelCutoutService.stored(key) { return hit }
            let reject = ModelCutoutService.rejectURL(key).path
            if FileManager.default.fileExists(atPath: reject) { return nil }
            switch ModelCutoutService.visionCutout(render) {
            case .cutout(let cutout):
                ModelCutoutService.store(cutout, key: key)
                return cutout
            case .rejected:
                FileManager.default.createFile(atPath: reject, contents: Data())
                return nil
            case .failed:
                return nil
            }
        }
        if image == nil { failures.insert(key) }
        return image
    }

    /// La voiture détourée du rendu embarqué, par son masque. Nil sans rendu ni masque.
    static func embeddedCutout(for vehicleID: String, paint: UInt32?) async -> UIImage? {
        let key = embeddedKey(vehicleID, paint: paint)
        if let hit = memoryCutout(key) { return hit }
        if failures.contains(key) { return nil }
        let image = await maskFlights.run(key) { ModelCutoutService.embeddedCutoutNow(for: vehicleID, paint: paint) }
        if image == nil { failures.insert(key) }
        return image
    }

    /// Même chose, tout de suite, sur le fil de l'appelant : pour la démonstration de
    /// l'onboarding et le partage, qui ne peuvent pas attendre. Un rendu de 660 × 290 se
    /// découpe en quelques millisecondes.
    static func embeddedCutoutNow(for vehicleID: String, paint: UInt32?) -> UIImage? {
        let key = embeddedKey(vehicleID, paint: paint)
        if let hit = stored(key) { return hit }
        guard let art = CarArt.image(for: vehicleID, paint: paint),
              let mask = CarArt.loadMask(vehicleID),
              let cutout = maskedCutout(art, mask: mask) else { return nil }
        store(cutout, key: key)
        return cutout
    }

    // MARK: Vision

    private enum VisionOutcome {
        case cutout(UIImage)
        /// Vision a répondu, mais rien de montrable : définitif pour ce rendu.
        case rejected
        /// Vision n'a pas tourné (simulateur, arrière-plan) : à retenter plus tard.
        case failed
    }

    private static func visionCutout(_ render: UIImage) -> VisionOutcome {
        guard let source = bitmap(render) else { return .failed }
        guard let found = SubjectLifter.cutout(source) else { return .failed }
        let size = CGSize(width: found.image.size.width * found.image.scale,
                          height: found.image.size.height * found.image.scale)
        guard StudioStageLayout.isPlausibleCutout(size: size, fill: found.fill,
                                                  relativeWidth: found.bounds.width) else {
            return .rejected
        }
        return .cutout(found.image)
    }

    /// Vision a besoin d'un bitmap : un rendu décodé autrement (sans `cgImage`) est
    /// redessiné une fois.
    private static func bitmap(_ image: UIImage) -> UIImage? {
        if image.cgImage != nil { return image }
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
        }
    }

    // MARK: Masque

    /// Applique le masque livré comme transparence, puis recadre aux bords de la voiture.
    ///
    /// À la main, pixel par pixel, plutôt qu'avec les masques de Core Graphics : selon
    /// l'appel, ceux-ci lisent le gris comme une opacité ou comme son inverse, et l'erreur
    /// ne se verrait qu'à l'écran — qu'on n'a pas, sans Mac.
    static func maskedCutout(_ image: UIImage, mask: UIImage) -> UIImage? {
        guard let source = image.cgImage, let cgMask = mask.cgImage else { return nil }
        let width = source.width, height = source.height
        guard width > 0, height > 0 else { return nil }
        let full = CGRect(x: 0, y: 0, width: width, height: height)

        // Le masque, en niveaux de gris, à la taille du rendu (il peut être plus petit).
        guard let gray = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let rgba = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        gray.interpolationQuality = .high
        gray.draw(cgMask, in: full)
        rgba.draw(source, in: full)
        guard let maskBase = gray.data, let pixelBase = rgba.data else { return nil }

        let maskRow = gray.bytesPerRow, pixelRow = rgba.bytesPerRow
        let alpha = maskBase.assumingMemoryBound(to: UInt8.self)
        let pixels = pixelBase.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let m = UInt16(alpha[y * maskRow + x])
                guard m < 255 else { continue }
                // Prémultiplié : les quatre composantes suivent l'opacité.
                let p = y * pixelRow + x * 4
                for c in 0..<4 { pixels[p + c] = UInt8(UInt16(pixels[p + c]) * m / 255) }
            }
        }

        // Le bruit du JPEG laisse des gris très sombres autour de la voiture : la boîte
        // ne retient que ce qui est franchement dans le masque.
        guard let box = SubjectLifter.measureLargest(width: width, height: height, label: { x, y in
            alpha[y * maskRow + x] > 127 ? 1 : 0
        }), let composed = rgba.makeImage() else { return nil }
        let crop = CGRect(x: box.bounds.minX * CGFloat(width), y: box.bounds.minY * CGFloat(height),
                          width: box.bounds.width * CGFloat(width),
                          height: box.bounds.height * CGFloat(height)).integral
        guard let cropped = composed.cropping(to: crop) else { return nil }
        return UIImage(cgImage: cropped)
    }

    // MARK: Stockage

    private static func stored(_ key: String) -> UIImage? {
        if let hit = memoryCutout(key) { return hit }
        guard let image = UIImage(contentsOfFile: fileURL(key).path) else { return nil }
        let decoded = image.preparingForDisplay() ?? image
        memory.setObject(decoded, forKey: key as NSString)
        return decoded
    }

    private static func store(_ image: UIImage, key: String) {
        memory.setObject(image, forKey: key as NSString)
        if let data = image.pngData() {
            try? data.write(to: fileURL(key), options: .atomic)
        }
    }
}

/// Une seule découpe par clé à la fois, et une seule à la fois tout court.
private actor CutoutFlights {
    private var tasks: [String: Task<UIImage?, Never>] = [:]
    private var tail: Task<Void, Never>?

    func run(_ key: String, _ work: @escaping @Sendable () -> UIImage?) async -> UIImage? {
        if let running = tasks[key] { return await running.value }
        let previous = tail
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            await previous?.value
            return work()
        }
        tail = Task { _ = await task.value }
        tasks[key] = task
        let value = await task.value
        tasks[key] = nil
        return value
    }
}

/// Ensemble protégé par un verrou : lu depuis le fil principal comme depuis les tâches.
private final class FailureMemo: @unchecked Sendable {
    private var keys: Set<String> = []
    private let lock = NSLock()

    func contains(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return keys.contains(key)
    }

    func insert(_ key: String) {
        lock.lock(); keys.insert(key); lock.unlock()
    }
}
