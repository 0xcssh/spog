import SwiftUI

/// Fabrique l'image partagee : la carte, mise a plat, en haute definition.
enum CardShareRenderer {

    @MainActor
    static func render(_ card: CardData) -> UIImage? {
        let artwork = flatArtwork(for: card)
        let renderer = ImageRenderer(content: ShareCardView(card: card, artwork: artwork))
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Le visuel de la carte, dans le meme ordre de priorite que l'affichage :
    /// la voiture reellement croisee passe avant le rendu du modele. Une carte
    /// partagee doit montrer ce que le joueur a trouve, pas un exemplaire de catalogue.
    private static func flatArtwork(for card: CardData) -> (image: UIImage, studio: Bool)? {
        if let developed = card.shot?.developed { return (developed, true) }
        if let stylized = card.shot?.stylized { return (stylized, false) }
        return CarArt.image(for: card.vehicle.id, paint: card.paint).map { ($0, true) }
    }
}

/// Version figee de la carte, destinee au partage. Pas d'animation, pas de reflet
/// mobile : une image que l'on peut poster.
private struct ShareCardView: View {
    let card: CardData
    let artwork: (image: UIImage, studio: Bool)?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let artwork, artwork.studio {
                    ZStack {
                        Theme.surfaceRaised
                        StudioArt(image: artwork.image)
                    }
                } else if let artwork {
                    Image(uiImage: artwork.image).resizable().scaledToFill()
                } else {
                    // Ni photo ni rendu : la silhouette, comme sur la carte affichee.
                    ZStack {
                        Theme.surfaceRaised
                        CarSilhouette(body: CarBody(card.vehicle.body),
                                      paint: card.paint, tint: card.tier.color)
                    }
                }
                Text(String(format: "%03d", card.serial))
                    .font(Theme.mono(13, .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(12)
            }
            .frame(width: 340, height: 334)
            .clipped()

            HStack {
                Text(card.tier.label)
                    .font(Theme.mono(11, .bold)).tracking(2).textCase(.uppercase)
                Spacer()
                HStack(spacing: 3) {
                    ForEach(0..<6, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(index <= card.tier.rank ? card.tier.color : card.tier.color.opacity(0.22))
                            .frame(width: 12, height: 4)
                    }
                }
            }
            .foregroundStyle(card.tier.color)
            .padding(.horizontal, 15).padding(.vertical, 11)
            .background(card.tier.color.opacity(0.16))

            VStack(alignment: .leading, spacing: 4) {
                Text(card.vehicle.make.uppercased())
                    .font(Theme.mono(10, .medium)).tracking(2)
                    .foregroundStyle(Theme.textMuted)
                Text(card.vehicle.model.uppercased())
                    .font(Theme.mono(21, .bold)).tracking(0.5)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.55)
                Rectangle().fill(Theme.stroke).frame(height: 1).padding(.vertical, 8)
                HStack {
                    Text(card.caughtAt, format: .dateTime.day().month(.abbreviated).year())
                        .font(Theme.mono(11)).textCase(.uppercase)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(verbatim: "SPOG")
                        .font(Theme.display(11, .heavy)).tracking(3)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .padding(.horizontal, 15).padding(.top, 13).padding(.bottom, 15)
            .frame(width: 340, alignment: .leading)
            .background(card.tier.color.opacity(0.07))
        }
        .frame(width: 340)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(card.tier.color.opacity(0.75), lineWidth: 1.5)
        )
        .padding(22)
        .background(Theme.background)
    }
}

/// Feuille de partage iOS.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
