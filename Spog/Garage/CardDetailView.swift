import SwiftUI

/// Une carte en plein ecran : c'est la qu'on la manipule, qu'on la developpe et qu'on la
/// partage.
struct CardDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(GarageStore.self) private var garage
    @Environment(SubscriptionStore.self) private var subscriptions
    /// Copie locale de la carte : elle change sous les yeux du joueur une fois developpee.
    @State private var card: CardData
    @State private var shareImage: UIImage?
    @State private var confirmingRemoval = false
    @State private var correcting = false
    @State private var developing = false
    @State private var developLimit = false
    @State private var developFailed = false
    @State private var showingPaywall = false

    init(card: CardData) {
        _card = State(initialValue: card)
    }

    /// Une carte se developpe une fois, et seulement si elle porte une vraie photo : une
    /// carte de demonstration n'a rien a developper.
    private var canDevelop: Bool { card.shot != nil && card.shot?.developed == nil }

    private var ambientGlow: Color {
        let base: Color = card.tier.frameColor ?? card.tier.color
        let strength: Double = card.tier.isTrophy ? 0.22 * card.tier.frameIntensity + 0.08 : 0.16
        return base.opacity(strength)
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            // La carte baigne dans la lumière de son palier, trophée ou non : une Clio a
            // sa lueur bleue, plus discrète que l'or d'une exotique, mais elle en a une.
            RadialGradient(colors: [ambientGlow, Color.clear],
                           center: .center, startRadius: 10, endRadius: 340)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 40, height: 40)
                            .background(Theme.glassFill, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.glassEdge, lineWidth: 1))
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.9))
                    Spacer()
                    InfoChip(icon: card.verified ? "checkmark.seal.fill" : "hand.raised.fill",
                             text: Text(card.verified ? LocalizedStringKey("card.verified")
                                                      : LocalizedStringKey("card.declared")),
                             color: card.verified ? Theme.accentBright : Theme.textMuted)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()
                CollectibleCardView(card: card)
                    .frame(maxWidth: 290)
                    .padding(.horizontal, 24)
                    .overlay { if developing { DevelopingVeil() } }
                Spacer()

                factsRow
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                if let price = card.price {
                    priceRow(price)
                        .padding(.bottom, 14)
                }

                Overline(text: developing ? "card.developing" : "card.hint")
                    .padding(.bottom, 14)

                if canDevelop {
                    Button { Task { await develop() } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles").font(.system(size: 13, weight: .bold))
                            Text("card.develop")
                        }
                    }
                    .buttonStyle(NeonButtonStyle(prominent: false))
                    .disabled(developing)
                    .opacity(developing ? 0.5 : 1)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                }

                Button {
                    shareImage = CardShareRenderer.render(card)
                    Analytics.track(.cardShared, ["tier": card.tier.id])
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 13, weight: .bold))
                        Text("card.share")
                    }
                }
                .buttonStyle(NeonButtonStyle())
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
        .alert(String(localized: "develop.limit.title"), isPresented: $developLimit) {
            Button(String(localized: "develop.limit.pro")) { showingPaywall = true }
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text("develop.limit.message")
        }
        .alert(String(localized: "develop.failed"), isPresented: $developFailed) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showingPaywall) { PaywallView() }
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

extension CardDetailView {
    /// Palier, points, lieu et date de la prise, en une rangée de verre sous la carte :
    /// ce que la carte dit en petit, lisible d'un coup d'œil.
    var factsRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.tier.label)
                    .font(Theme.label(10)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(card.tier.color)
                Text(verbatim: "+\(card.tier.points)")
                    .font(Theme.hero(20))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            HairlineDivider()
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(card.placeName).lineLimit(1)
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                }
                .font(Theme.body(12, .semibold))
                .foregroundStyle(Theme.textSecondary)
                Text(card.caughtAt, style: .date)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 0)
            if card.firstSpot {
                Image(systemName: "flag.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(RarityTier.trophyGold)
                    .frame(width: 34, height: 34)
                    .background(RarityTier.trophyGold.opacity(0.14), in: Circle())
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.glassFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Theme.glassEdge, lineWidth: 1))
    }

    /// La cote de la prise, en fourchette dans la devise du pays où elle a été faite.
    /// « Approximative » est écrit en toutes lettres : la cote est devinée d'une photo, sans
    /// kilométrage ni carnet d'entretien, et l'annoncer sèchement promettrait une exactitude
    /// qu'aucune image ne contient.
    func priceRow(_ price: PriceBracket) -> some View {
        VStack(spacing: 4) {
            Overline(text: "card.priceLabel")
            Text(verbatim: PriceFormat.range(price))
                .font(Theme.display(17, .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Envoie la photo du joueur au serveur et remplace le visuel de la carte par le rendu
    /// studio. Le rendu est range sur l'appareil : il ne se regenere jamais.
    @MainActor
    private func develop() async {
        guard let original = card.shot?.original, !developing else { return }
        withAnimation { developing = true }
        let result = await DevelopService.develop(original, entitlement: subscriptions.entitlementJWS)
        withAnimation { developing = false }
        switch result {
        case .success(let image):
            ShotStore.saveDeveloped(image, for: card.id)
            if let item = garage.catches.first(where: { $0.id == card.id }),
               let refreshed = garage.card(item) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { card = refreshed }
            }
            Analytics.track(.cardDeveloped, ["tier": card.tier.id])
        case .failure(.limit):
            developLimit = true
        case .failure(.failed):
            developFailed = true
        }
    }
}

/// Voile pose sur la carte pendant le developpement : un tirage qui apparait lentement,
/// plutot qu'une roue qui tourne. La generation prend une vingtaine de secondes.
private struct DevelopingVeil: View {
    @State private var phase = false

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Theme.background.opacity(phase ? 0.25 : 0.6))
            .overlay {
                LinearGradient(colors: [.clear, Theme.accentBright.opacity(0.35), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
                    .offset(y: phase ? 160 : -160)
                    .blendMode(.screen)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { phase = true }
            }
    }
}

/// Enveloppe pour presenter une image dans une feuille.
private struct ShareableImage: Identifiable {
    let image: UIImage
    var id: String { String(UInt(bitPattern: ObjectIdentifier(image).hashValue)) }
}
