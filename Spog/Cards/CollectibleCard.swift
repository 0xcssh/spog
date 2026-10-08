import SwiftUI
import UIKit

/// Donnees d'une carte. Plus tard remplies par un scan reel ; ici alimentees par le catalogue.
struct CardData: Identifiable {
    let id: UUID
    let vehicle: Vehicle
    let tier: RarityTier
    let serial: Int
    let caughtAt: Date
    let placeName: String
    /// Capturee avec la localisation active : verifiable. Sinon declarative.
    let verified: Bool
    /// Teinte de carrosserie pour le rendu 3D.
    let paint: UInt32
    /// Photo de l'utilisateur et sa version transformee. Nil avant le premier scan.
    var shot: StyledShot? = nil
    /// Premier joueur a attraper ce modele dans ce pays : une marque meritee, a vie.
    var firstSpot: Bool = false
    /// Cote approximative de la prise. Nil pour une démonstration ou une ancienne prise :
    /// la carte n'affiche alors rien plutôt qu'une ligne vide.
    var price: PriceBracket? = nil
}

/// La carte a collectionner. Se penche sous le doigt sur deux axes, avec un reflet
/// holographique qui suit l'inclinaison. Plus le palier est haut, plus le reflet est vif.
struct CollectibleCardView: View {

    let card: CardData
    var interactive: Bool = true
    /// Bascule carte / cliché brut d'un tap. La prise de démonstration de l'onboarding la
    /// coupe : là, toucher la carte la développe, et l'invite « ton cliché » contredirait
    /// la consigne affichée juste en dessous.
    var showsShotToggle: Bool = true

    @State private var tilt: CGSize = .zero
    @State private var isPressed = false
    /// Balancement lent au repos : la carte respire, le reflet et la profondeur
    /// restent visibles sans qu'on la touche. S'arrete des qu'un doigt la prend.
    @State private var sway: Double = -1
    /// Un tap bascule entre le visuel de carte et le cliche brut.
    @State private var showOriginal = false

    private let maxAngle: Double = 26

    private var idleY: Double { isPressed ? 0 : sway * 5.5 }
    private var idleX: Double { isPressed ? 0 : sway * 2.0 }

    private var rotX: Double { clamp(Double(-tilt.height) / 7 + idleX) }
    private var rotY: Double { clamp(Double(tilt.width) / 7 + idleY) }
    private func clamp(_ v: Double) -> Double { min(max(v, -maxAngle), maxAngle) }

    /// Inclinaison ramenee a -1..1, ce que consomme la parallaxe.
    private var px: Double { rotY / maxAngle }
    private var py: Double { -rotX / maxAngle }

    /// 0 pour les paliers bas, 1 pour legendaire : dose l'effet holographique.
    private var shine: Double { card.tier.isTrophy ? card.tier.frameIntensity : 0 }

    var body: some View {
        cardBody
            .aspectRatio(0.70, contentMode: .fit)
            .rotation3DEffect(.degrees(rotX), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
            .rotation3DEffect(.degrees(rotY), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .scaleEffect(isPressed ? 1.03 : 1)
            .shadow(color: .black.opacity(0.55), radius: 18, y: 16)
            .gesture(interactive ? dragGesture : nil)
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: tilt)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
            .onAppear {
                withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                    sway = 1
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                tilt = value.translation
                if !isPressed { isPressed = true }
            }
            .onEnded { _ in
                tilt = .zero
                isPressed = false
            }
    }

    // MARK: Corps

    private var cardBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surface)

            // Halo dore, reserve aux cartes remarquables
            if let frame = card.tier.frameColor {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        RadialGradient(colors: [frame.opacity(0.22 * card.tier.frameIntensity), .clear],
                                       center: .topLeading, startRadius: 8, endRadius: 340)
                    )
            }

            content

            // Reflet holographique, decale par l'inclinaison
            holographicSheen
                .opacity(0.20 + 0.55 * shine)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)

            // Le neon est pose sur le corps entier de la carte, pas ici :
            // un contour interieur ne peut pas deborder de lumiere.
            if card.tier.frameColor == nil {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .modifier(TrophyNeon(tier: card.tier))
    }

    private var holographicSheen: some View {
        GeometryReader { geo in
            let shift = CGFloat(rotY / maxAngle)
            LinearGradient(
                colors: [.clear,
                         Color(hex: 0x8FD4FF).opacity(0.35),
                         Color(hex: 0xE79BFF).opacity(0.45),
                         Color(hex: 0xFFD59B).opacity(0.30),
                         .clear],
                startPoint: UnitPoint(x: -0.4 + shift, y: 0),
                endPoint: UnitPoint(x: 0.9 + shift, y: 1)
            )
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: Contenu

    private var content: some View {
        VStack(spacing: 0) {
            artwork
            rarityBand
            infoBlock
        }
    }

    /// Le rendu occupe toute la largeur, sans marge : c'est lui le sujet de la carte.
    private var artwork: some View {
        ZStack(alignment: .topLeading) {
            ParallaxArtwork(px: px, py: py, tint: card.tier.color,
                            vehicleID: card.vehicle.id,
                            carBody: CarBody(card.vehicle.body),
                            paint: card.paint,
                            shot: card.shot,
                            showOriginal: showOriginal)

            Text(String(format: "%03d", card.serial))
                .font(Theme.mono(11, .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(10)

            if card.shot != nil && showsShotToggle {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Overline(text: showOriginal ? "card.yourShot" : "card.tapForShot",
                                 color: showOriginal ? card.tier.color : Theme.textMuted)
                            .padding(10)
                    }
                }
            }
        }
        .aspectRatio(1.02, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture {
            guard card.shot != nil, showsShotToggle else { return }
            withAnimation(.easeInOut(duration: 0.22)) { showOriginal.toggle() }
        }
    }

    /// Bandeau de rarete : le palier a gauche, sa position sur l'echelle a droite.
    private var rarityBand: some View {
        HStack {
            Text(card.tier.label)
                .font(Theme.mono(10, .bold))
                .tracking(2)
                .textCase(.uppercase)
            Spacer()
            HStack(spacing: 3) {
                ForEach(0..<6, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(index <= card.tier.rank ? card.tier.color : card.tier.color.opacity(0.22))
                        .frame(width: 11, height: 4)
                }
            }
        }
        .foregroundStyle(card.tier.color)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(card.tier.color.opacity(0.16))
    }

    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(card.vehicle.make.uppercased())
                .font(Theme.mono(9, .medium))
                .tracking(2)
                .foregroundStyle(Theme.textMuted)
            Text(card.vehicle.model.uppercased())
                .font(Theme.mono(19, .bold))
                .tracking(0.5)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.55)

            // Discrète, sous le nom : la rareté reste la valeur du jeu, la cote n'est qu'une
            // curiosité. Le mot « approx. » n'est pas une précaution de style — elle est
            // devinée d'une photo, sans kilométrage ni carnet d'entretien.
            if let price = card.price {
                Text("card.priceInline \(PriceFormat.range(price))")
                    .font(Theme.mono(9, .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }

            Rectangle().fill(Theme.stroke).frame(height: 1).padding(.vertical, 7)

            HStack(spacing: 6) {
                Text(card.caughtAt, format: .dateTime.day().month(.abbreviated).year())
                    .font(Theme.mono(10))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textSecondary)
                if card.verified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(card.tier.color)
                }
                if card.firstSpot {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(RarityTier.trophyGold)
                        .accessibilityLabel(Text("card.firstSpot"))
                }
                Spacer()
                Image("LogoMark")
                    .resizable()
                    .frame(width: 15, height: 15)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .opacity(0.75)
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 11)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card.tier.color.opacity(0.07))
    }
}


/// Néon doré autour des cartes remarquables. En plein écran une seule carte est
/// visible : elle peut respirer sans que l'écran devienne une guirlande.
private struct TrophyNeon: ViewModifier {
    let tier: RarityTier

    func body(content: Content) -> some View {
        if let color = tier.frameColor {
            content.neonBorder(color: color, radius: 22,
                               intensity: tier.frameIntensity, breathing: true)
        } else {
            content
        }
    }
}
