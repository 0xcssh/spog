import SwiftUI

/// Un rendu studio (catalogue `CarArt`, visuel d'une cible du pack, carte passée en studio),
/// montré **en entier** et fondu dans le fond de la carte.
///
/// Ces rendus sont des bandeaux : 660 × 290 pour le catalogue, 1536 × 1024 pour les rendus
/// générés. Affichés en remplissage dans une vignette presque carrée, ils perdaient l'avant
/// et l'arrière de la voiture — exactement ce qui la fait reconnaître. Affichés en entier
/// sans précaution, leur fond de studio s'arrêtait net sur celui de la carte, en rectangle
/// visible. Le fondu des bords règle les deux : la voiture entière, sans couture.
///
/// La **photo du joueur**, elle, continue de remplir son cadre : c'est un cliché, il est
/// cadré pour ça, et le rogner un peu ne coûte rien.
struct StudioArt: View {
    let image: UIImage
    /// Grossissement léger : le studio laisse de la marge autour de la voiture, qu'on peut
    /// sacrifier sans jamais couper la carrosserie.
    var zoom: CGFloat = 1.12

    var body: some View {
        Color.clear
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoom)
                    .mask {
                        // Fondu sur les quatre bords : plus court sur les côtés, où se trouvent
                        // les pare-chocs, plus long en haut et en bas, où il n'y a que le studio.
                        LinearGradient(stops: [.init(color: .clear, location: 0),
                                               .init(color: .black, location: 0.18),
                                               .init(color: .black, location: 0.82),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                            .mask {
                                LinearGradient(stops: [.init(color: .clear, location: 0),
                                                       .init(color: .black, location: 0.06),
                                                       .init(color: .black, location: 0.94),
                                                       .init(color: .clear, location: 1)],
                                               startPoint: .leading, endPoint: .trailing)
                            }
                    }
            }
            .clipped()
    }
}
