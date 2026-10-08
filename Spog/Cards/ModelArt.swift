import SwiftUI

/// Le visuel d'un **modèle** du catalogue — jamais d'une photo du joueur : cible du pack,
/// vitrine du garage, carte sans photo, Spogdex.
///
/// Le rendu HD du serveur est généré **dans la plaque du studio unique** (voir
/// backend/functions/identify/art.ts) : même fond, même sol, même lumière sous chaque
/// modèle, et la voiture y a sa vraie ombre. Il s'affiche donc tel quel, en plein cadre.
/// (Détourer la voiture et la poser sur un décor dessiné la faisait flotter : retour du
/// testeur du 09/10/2026.)
///
/// Ordre d'affichage, du plus immédiat au définitif :
/// 1. la découpe du rendu embarqué `CarArt` (son masque est livré avec lui) sur le décor
///    dessiné, tout de suite, hors ligne compris — un aperçu, le temps du réseau ;
/// 2. le rendu HD du serveur (`VehicleArtService`), en fondu dès qu'il arrive — une
///    trentaine de secondes pour le tout premier joueur qui demande un modèle,
///    instantané ensuite. Sans rendu du tout : la silhouette.
struct ModelArt: View {
    let vehicleID: String
    let carBody: CarBody
    let tint: Color
    /// Teinte appliquée au rendu embarqué de repli (la voiture réellement croisée, pour
    /// une carte du garage). Le rendu HD garde la sienne : il n'a pas de masque à repeindre.
    let paint: UInt32?

    @State private var face: ModelFace
    /// Le modèle (et la teinte) auquel `face` correspond : une vue réutilisée pour un autre
    /// modèle ne doit pas montrer l'ancien le temps de charger le nouveau.
    @State private var faceOwner: String

    init(vehicleID: String, body: CarBody, tint: Color, paint: UInt32? = nil) {
        self.vehicleID = vehicleID
        self.carBody = body
        self.tint = tint
        self.paint = paint
        // Une découpe déjà en mémoire s'affiche dès la première image, sans fondu : un
        // rendu connu qui « arrive » à chaque ouverture ferait croire à un chargement.
        // Mémoire seulement : `init` est rappelé à chaque mise à jour du parent.
        _face = State(initialValue: ModelFace.immediate(vehicleID, paint: paint))
        _faceOwner = State(initialValue: ModelFace.owner(vehicleID, paint: paint))
    }

    private var owner: String { ModelFace.owner(vehicleID, paint: paint) }

    var body: some View {
        // Le décor donne la taille ; la voiture se pose dessus. Une image en remplissage
        // posée directement dans une pile la ferait grandir au-delà du cadre prévu.
        StudioBackdrop()
            .overlay {
                faceView
                    .id(face.identity)
                    .transition(.opacity)
            }
            .clipped()
            .task(id: owner) { await load() }
    }

    @ViewBuilder private var faceView: some View {
        switch face {
        case .pending:
            Color.clear
        case .staged(let cutout, let key, _):
            // Le décor est déjà dessous : la voiture seule.
            StagedCar(cutout: cutout, cutoutKey: key, showsBackdrop: false)
        case .full(let render):
            SharpFill(image: render, key: "hd-" + vehicleID)
        case .banner(let art):
            StudioArt(image: art)
        case .silhouette:
            silhouette
        }
    }

    private var silhouette: some View {
        Image(systemName: carBody.symbol)
            .resizable()
            .scaledToFit()
            .foregroundStyle(LinearGradient(colors: [Theme.textPrimary.opacity(0.75), tint.opacity(0.45)],
                                            startPoint: .top, endPoint: .bottom))
            // Proportionnel plutôt qu'une marge fixe : la même vue sert une vignette
            // de 100 points et une carte plein écran.
            .scaleEffect(0.62)
            .shimmer()
    }

    // MARK: Chargement

    private func show(_ next: ModelFace, animated: Bool = true) {
        guard next.identity != face.identity else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.45)) { face = next }
        } else {
            face = next
        }
    }

    private func load() async {
        let id = vehicleID, paint = paint
        if faceOwner != owner {
            faceOwner = owner
            face = ModelFace.immediate(id, paint: paint)
        }
        if face.isFinal { return }

        // Le rendu HD déjà sur l'appareil : lu et décodé hors du fil principal.
        let stored = await Task.detached(priority: .userInitiated) {
            VehicleArtService.storedImage(for: id)
        }.value
        if let stored {
            show(.full(stored), animated: face.isVisible)
            return
        }

        // En attendant le serveur : le rendu embarqué, détouré par son masque.
        if !face.isVisible {
            let preview = await Self.previewFace(id, paint: paint)
            show(preview)
        }

        // Un court délai avant de demander au serveur : une vignette qui ne fait que
        // passer pendant un défilement rapide disparaît avant, et sa tâche est annulée.
        // Sans lui, balayer une grille déclencherait des générations payantes à la chaîne.
        try? await Task.sleep(for: .milliseconds(350))
        if Task.isCancelled { return }
        guard let remote = await VehicleArtService.remoteImage(for: id), !Task.isCancelled else { return }
        show(.full(remote))
    }

    /// Le visuel d'attente : la découpe du rendu embarqué, sinon le bandeau entier, sinon
    /// la silhouette.
    private static func previewFace(_ id: String, paint: UInt32?) async -> ModelFace {
        if let cutout = await ModelCutoutService.embeddedCutout(for: id, paint: paint) {
            return .staged(cutout, key: ModelCutoutService.embeddedKey(id, paint: paint), definitive: false)
        }
        if let art = CarArt.image(for: id, paint: paint) { return .banner(art) }
        return .silhouette
    }
}

/// Ce que `ModelArt` montre à un instant donné.
private enum ModelFace {
    /// Rien encore : le studio vide, le temps d'une lecture sur le disque.
    case pending
    /// La voiture du rendu embarqué, détourée sur le décor dessiné : un aperçu.
    case staged(UIImage, key: String, definitive: Bool)
    /// Le rendu HD, studio compris, en plein cadre : le visuel définitif.
    case full(UIImage)
    /// Le rendu embarqué sans masque, en entier et fondu.
    case banner(UIImage)
    case silhouette

    var isFinal: Bool {
        switch self {
        case .staged(_, _, let definitive): return definitive
        case .full: return true
        default: return false
        }
    }

    var isVisible: Bool {
        if case .pending = self { return false }
        return true
    }

    /// Identité de la vue, pour le fondu d'un visuel à l'autre.
    var identity: String {
        switch self {
        case .pending: return "pending"
        case .staged(_, let key, _): return "staged-" + key
        case .full: return "full"
        case .banner: return "banner"
        case .silhouette: return "silhouette"
        }
    }

    static func owner(_ id: String, paint: UInt32?) -> String {
        ModelCutoutService.embeddedKey(id, paint: paint)
    }

    /// Ce qui est déjà en mémoire, sans disque ni calcul.
    static func immediate(_ id: String, paint: UInt32?) -> ModelFace {
        if let hd = VehicleArtService.memoryImage(for: id) { return .full(hd) }
        let embedded = ModelCutoutService.embeddedKey(id, paint: paint)
        if let cutout = ModelCutoutService.memoryCutout(embedded) {
            return .staged(cutout, key: embedded, definitive: false)
        }
        return .pending
    }
}

/// Une carte « passée en studio » : le rendu 1536 × 1024 généré à partir de la photo du
/// joueur, dans un cadre presque carré.
///
/// Le remplir couperait un tiers de sa largeur, donc l'avant ou l'arrière de **sa**
/// voiture. On le montre en entier, et le reste du cadre est rempli par le même rendu,
/// agrandi et flouté : le studio continue sous la voiture et au-dessus, sans la couture
/// ni le vide d'un simple fondu sur fond uni.
struct DevelopedArt: View {
    let image: UIImage
    /// Décalage de parallaxe du plan net (le fond flou, lointain, ne bouge pas).
    var offset: CGSize = .zero

    var body: some View {
        Color.clear
            .background {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 22, opaque: true)
                    .overlay(Theme.background.opacity(0.35))
            }
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .mask {
                        // Fondu haut et bas seulement : sur les côtés, l'image touche déjà
                        // les bords du cadre, et c'est là que sont les pare-chocs.
                        LinearGradient(stops: [.init(color: .clear, location: 0),
                                               .init(color: .black, location: 0.14),
                                               .init(color: .black, location: 0.86),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .offset(offset)
            }
            .clipped()
    }
}
