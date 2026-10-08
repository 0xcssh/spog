import SwiftUI

/// Un rendu studio du catalogue, montré **en entier** et fondu dans le fond de la carte —
/// ou en plein cadre s'il est carré.
///
/// Les rendus embarqués (`CarArt`) sont des bandeaux de 660 × 290. Affichés en
/// remplissage dans une vignette presque carrée, ils perdaient l'avant et l'arrière de la
/// voiture — exactement ce qui la fait reconnaître. Affichés en entier sans précaution,
/// leur fond de studio s'arrêtait net sur celui de la carte, en rectangle visible. Le
/// fondu des bords règle les deux : la voiture entière, sans couture. Ce n'est plus qu'un
/// repli, le temps que le rendu carré haute définition arrive (voir `ModelArt`).
///
/// Un rendu **carré** (celui du serveur, 1024 × 1024, voiture centrée) n'a pas besoin de
/// cette rustine : le remplissage ne rogne que du studio. On le reconnaît à ses
/// proportions, pour que tout appelant qui passe un tel rendu obtienne le cadrage plein.
///
/// La **photo du joueur**, elle, continue de remplir son cadre : c'est un cliché, il est
/// cadré pour ça, et le rogner un peu ne coûte rien.
struct StudioArt: View {
    let image: UIImage
    /// Grossissement léger : le studio laisse de la marge autour de la voiture, qu'on peut
    /// sacrifier sans jamais couper la carrosserie.
    var zoom: CGFloat = 1.12

    /// Carré ou presque : au-delà de 1,25 de large pour 1 de haut, c'est un bandeau.
    private var isSquare: Bool {
        image.size.height > 0 && image.size.width / image.size.height < 1.25
    }

    var body: some View {
        if isSquare {
            Color.clear
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                }
                .clipped()
        } else {
            banner
        }
    }

    private var banner: some View {
        Color.clear
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
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
