import SwiftUI

/// Une carte en plein ecran : c'est la qu'on la manipule et qu'on la partage.
struct CardDetailView: View {
    let card: CardData
    @Environment(\.dismiss) private var dismiss
    @Environment(GarageStore.self) private var garage
    @State private var shareImage: UIImage?
    @State private var confirmingRemoval = false
    @State private var correcting = false

    /// Fourchette de cote de cette prise, mise en forme, ou nil.
    ///
    /// Elle est lue dans le garage plutot que portee par `CardData` : la cote appartient
    /// a **la prise** — une capture datee, dans un pays donne — pas au modele de voiture,
    /// et le garage est deja la source de verite des prises.
    private var priceText: String? {
        guard let item = garage.catches.first(where: { $0.id == card.id }),
              let low = item.priceLow, let high = item.priceHigh else { return nil }
        let format = FloatingPointFormatStyle<Double>.Currency(code: item.priceCurrency ?? "EUR")
            .precision(.fractionLength(0))
        return "\(Double(low).formatted(format)) – \(Double(high).formatted(format))"
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let frame = card.tier.frameColor {
                RadialGradient(colors: [frame.opacity(0.16 * card.tier.frameIntensity), .clear],
                               center: .center, startRadius: 10, endRadius: 320)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Theme.surface))
                            .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Overline(text: card.verified ? "card.verified" : "card.declared",
                             color: card.verified ? Theme.textSecondary : Theme.textMuted)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()
                CollectibleCardView(card: card)
                    .frame(maxWidth: 290)
                    .padding(.horizontal, 24)
                Spacer()

                if let price = priceText {
                    // Le mot « approximative » n'est pas une precaution de style : la
                    // cote est devinee d'une photo, sans kilometrage ni carnet
                    // d'entretien. L'annoncer sechement serait promettre une exactitude
                    // qu'aucune image ne contient.
                    VStack(spacing: 4) {
                        Overline(text: "card.priceLabel")
                        Text(price)
                            .font(Theme.display(17, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.bottom, 14)
                }

                Overline(text: "card.hint")
                    .padding(.bottom, 18)

                Button { shareImage = CardShareRenderer.render(card) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 13, weight: .bold))
                        Text("card.share").font(Theme.label(12)).tracking(1)
                    }
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(colors: [Theme.accentBright, Theme.accent],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                HStack(spacing: 20) {
                    // L'identification se fait sans question au-dessus du seuil de
                    // confiance : quand elle se trompe, c'est ici qu'on la rattrape.
                    Button { correcting = true } label: {
                        Text("card.correct")
                            .font(Theme.label(11)).tracking(1)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Button { confirmingRemoval = true } label: {
                        Text("card.remove")
                            .font(Theme.label(11)).tracking(1)
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 14)
                .padding(.bottom, 8)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: Binding(get: { shareImage.map(ShareableImage.init) },
                             set: { _ in shareImage = nil })) { wrapper in
            ShareSheet(items: [wrapper.image])
        }
        .sheet(isPresented: $correcting) {
            VehiclePickerSheet(title: "card.correct") { vehicle in
                guard let item = garage.catches.first(where: { $0.id == card.id }) else { return }
                garage.reassign(item, to: vehicle.id)
                // La fiche tient une copie de la carte : elle ne se met pas a jour toute
                // seule. On referme, le garage montre la correction.
                dismiss()
            }
        }
        .confirmationDialog(Text("card.removeConfirm"),
                            isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button(role: .destructive) {
                if let item = garage.catches.first(where: { $0.id == card.id }) {
                    garage.remove(item)
                }
                dismiss()
            } label: { Text("card.remove") }
            Button(role: .cancel) {} label: { Text("common.cancel") }
        }
    }
}

/// Enveloppe pour presenter une image dans une feuille.
private struct ShareableImage: Identifiable {
    let image: UIImage
    var id: String { String(UInt(bitPattern: ObjectIdentifier(image).hashValue)) }
}
