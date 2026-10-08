import SwiftUI

/// Le visuel d'un **modèle** du catalogue — jamais d'une photo du joueur : cible du pack,
/// vitrine du garage, carte sans photo, Spogdex.
///
/// Le rendu haute définition du serveur (1024 × 1024, voiture centrée sur ~80 % de la
/// largeur) remplit tout le cadre. Sur un rendu carré et centré, le remplissage ne rogne
/// que du fond de studio, jamais la voiture : c'est ce qui permet enfin des cartes bord à
/// bord, là où les bandeaux embarqués laissaient la moitié de la carte vide.
///
/// En attendant le rendu (une trentaine de secondes pour le tout premier joueur qui
/// demande un modèle, instantané ensuite), on montre ce qu'on a déjà : le rendu embarqué
/// `CarArt` s'il existe, en entier et fondu (`StudioArt`), sinon la silhouette de la
/// carrosserie qui scintille. Puis fondu vers le rendu HD dès qu'il arrive.
struct ModelArt: View {
    let vehicleID: String
    let carBody: CarBody
    let tint: Color
    /// Teinte appliquée au rendu embarqué de repli (la voiture réellement croisée, pour
    /// une carte du garage). Le rendu HD garde la sienne : il n'a pas de masque à repeindre.
    let paint: UInt32?

    @State private var hd: UIImage?

    init(vehicleID: String, body: CarBody, tint: Color, paint: UInt32? = nil) {
        self.vehicleID = vehicleID
        self.carBody = body
        self.tint = tint
        self.paint = paint
        // Un rendu déjà sur l'appareil s'affiche dès la première image, sans fondu : un
        // rendu connu qui « arrive » à chaque ouverture ferait croire à un chargement.
        _hd = State(initialValue: VehicleArtService.storedImage(for: vehicleID))
    }

    var body: some View {
        // Le fond donne la taille ; les images se posent dessus. Une image en remplissage
        // posée directement dans une pile la ferait grandir au-delà du cadre prévu.
        Rectangle()
            .fill(LinearGradient(colors: [tint.opacity(0.24), Theme.surface],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                RadialGradient(colors: [tint.opacity(0.32), .clear],
                               center: .bottom, startRadius: 2, endRadius: 160)
            }
            .overlay {
                if hd == nil {
                    placeholder
                        .transition(.opacity)
                }
            }
            .overlay {
                if let hd {
                    Image(uiImage: hd)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: vehicleID) { await load() }
    }

    @ViewBuilder private var placeholder: some View {
        if let art = CarArt.image(for: vehicleID, paint: paint) {
            StudioArt(image: art)
        } else {
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
    }

    private func load() async {
        if let ready = VehicleArtService.storedImage(for: vehicleID) {
            hd = ready
            return
        }
        hd = nil
        // Un court délai avant de demander au serveur : une vignette qui ne fait que
        // passer pendant un défilement rapide disparaît avant, et sa tâche est annulée.
        // Sans lui, balayer une grille déclencherait des générations payantes à la chaîne.
        try? await Task.sleep(for: .milliseconds(350))
        if Task.isCancelled { return }
        guard let loaded = await VehicleArtService.remoteImage(for: vehicleID),
              !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.7)) { hd = loaded }
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
