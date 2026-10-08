import SwiftUI

/// Illustration de la carte, decomposee en plans qui se decalent a des vitesses
/// differentes quand la carte s'incline. C'est ce qui donne l'impression que la
/// voiture se detache du fond.
///
/// `depth` sur chaque plan : 0 = infiniment loin (immobile), 1 = colle a la vitre.
/// Quand la vraie photo arrivera, le fond et le sujet decoupe remplaceront la scene
/// de substitution sans rien changer a cette mecanique.
struct ParallaxArtwork: View {

    /// Inclinaison normalisee, -1 a 1 sur chaque axe.
    let px: Double
    let py: Double
    let tint: Color
    /// Identifiant du vehicule : sert a retrouver son illustration embarquee.
    var vehicleID: String = ""
    /// Carrosserie et teinte du vehicule, pour la silhouette de repli.
    var carBody: CarBody = .sedan
    var paint: UInt32 = 0xB4B8BE
    /// Photo de l'utilisateur, transformee. Sinon, decor genere.
    var shot: StyledShot? = nil
    /// Afficher le cliche brut plutot que le visuel de carte.
    var showOriginal: Bool = false

    /// Amplitude maximale du decalage, en points, pour un plan colle a la vitre.
    private let travel: CGFloat = 16

    private func shift(_ depth: Double) -> CGSize {
        CGSize(width: CGFloat(px) * travel * depth,
               height: CGFloat(py) * travel * depth * 0.7)
    }

    var body: some View {
        ZStack {
            if showOriginal, let shot {
                // Le cliche brut de l'utilisateur.
                filled(shot.original, depth: 0.3)
            } else if let shot {
                // **La voiture reellement croisee passe avant le modele.**
                //
                // Le rendu studio montre un exemplaire neuf et standard du modele, dans
                // l'une des quatorze teintes de la palette. Il ne sait representer ni un
                // covering zebre, ni une livree de taxi, ni un kit large, ni vingt ans de
                // soleil sur la peinture. Le joueur qui repere une Porsche zebree a trouve
                // **cette** voiture-la ; lui rendre un Macan argente de catalogue, ce
                // serait lui prendre sa prise pour lui donner une illustration.
                //
                // La photo mise en scene est donc le visuel de la carte des qu'il y en a
                // une, et le rendu studio sert aux cartes qui n'en ont pas : le Spogdex,
                // et les modeles pas encore attrapes.
                filled(shot.face, depth: 0.9, scale: 1.06)
            } else if let render = CarArt.image(for: vehicleID, paint: paint) {
                // Rendu studio du modele. Affiche en entier, pas rogne : c'est la
                // silhouette qui fait reconnaitre la voiture, un gros plan sur une aile
                // ne dit rien.
                fitted(render, depth: 0.85)
            } else {
                placeholderScene
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Image affichee en entier, sur un fond sombre teinte par la rarete.
    private func fitted(_ image: UIImage, depth: Double) -> some View {
        Color.clear
            .background {
                LinearGradient(colors: [Theme.background, tint.opacity(0.16), Theme.background],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .offset(shift(depth))
            }
            .clipped()
    }

    /// Image qui remplit la zone sans jamais la deformer ni la repousser.
    /// Le `Color.clear` fixe la taille disponible ; sans lui, une image en
    /// remplissage impose sa propre taille et fait exploser la carte.
    private func filled(_ image: UIImage, depth: Double, scale: CGFloat = 1) -> some View {
        Color.clear
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(scale)
                    .offset(shift(depth))
            }
            .clipped()
    }

    // MARK: Scene de substitution — une route qui fuit, en echo au logo

    private var placeholderScene: some View {
        ZStack {
            // Plan 1 — ciel et horizon, presque immobile
            LinearGradient(colors: [Theme.background, tint.opacity(0.18), Theme.surfaceRaised],
                           startPoint: .top, endPoint: .bottom)
                .scaleEffect(1.15)
                .offset(shift(0.18))

            // Lueur d'horizon
            Ellipse()
                .fill(RadialGradient(colors: [tint.opacity(0.55), .clear],
                                     center: .center, startRadius: 1, endRadius: 90))
                .frame(width: 190, height: 70)
                .offset(y: -18)
                .offset(shift(0.3))
                .blur(radius: 6)

            // Plan 2 — la route
            RoadCanvas(tint: tint)
                .offset(shift(0.6))

            // Plan 3 — la voiture, au plus pres de la vitre.
            if let art = CarArt.image(for: vehicleID) {
                // Illustration du modele exact : on reconnait la voiture.
                Image(uiImage: art)
                    .resizable().scaledToFit()
                    .shadow(color: .black.opacity(0.55), radius: 12,
                            x: -CGFloat(px) * 10, y: 8)
                    .padding(.horizontal, 8)
                    .offset(shift(1.0))
            } else {
                // Repli : silhouette de la carrosserie, valable pour tout le catalogue.
                CarSilhouette(body: carBody, paint: paint, tint: tint)
                    .offset(y: 10)
                    .offset(shift(0.8))
            }
        }
    }
}

/// Route en perspective, dessinee au trait. Motif repris du logo.
private struct RoadCanvas: View {
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let horizon = h * 0.42
            let vanish = CGPoint(x: w / 2, y: horizon)

            // Bitume
            var road = Path()
            road.move(to: CGPoint(x: w * 0.5 - 14, y: horizon))
            road.addLine(to: CGPoint(x: w * 0.5 + 14, y: horizon))
            road.addLine(to: CGPoint(x: w * 1.25, y: h))
            road.addLine(to: CGPoint(x: -w * 0.25, y: h))
            road.closeSubpath()
            context.fill(road, with: .linearGradient(
                Gradient(colors: [Theme.surfaceRaised.opacity(0.0), Color.black.opacity(0.75)]),
                startPoint: vanish, endPoint: CGPoint(x: w / 2, y: h)))

            // Bords lumineux
            for side in [-1.0, 1.0] {
                var edge = Path()
                edge.move(to: CGPoint(x: w * 0.5 + 14 * side, y: horizon))
                edge.addLine(to: CGPoint(x: w * (0.5 + 0.75 * side), y: h))
                context.stroke(edge, with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.0), tint.opacity(0.85)]),
                    startPoint: vanish, endPoint: CGPoint(x: w / 2, y: h)), lineWidth: 2)
            }

            // Ligne centrale discontinue, segments qui s'ecartent avec la distance
            var t = 0.06
            while t < 1.0 {
                let y0 = horizon + (h - horizon) * t * t
                let y1 = horizon + (h - horizon) * min(1, (t + 0.055)) * min(1, (t + 0.055))
                let width = 1.0 + 3.0 * t * t
                var dash = Path()
                dash.move(to: CGPoint(x: w / 2, y: y0))
                dash.addLine(to: CGPoint(x: w / 2, y: y1))
                context.stroke(dash, with: .color(Theme.textSecondary.opacity(0.25 + 0.5 * t)),
                               lineWidth: width)
                t += 0.11
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
