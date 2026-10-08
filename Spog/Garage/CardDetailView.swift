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
                    .overlay { if developing { DevelopingVeil() } }
                Spacer()

                Overline(text: developing ? "card.developing" : "card.hint")
                    .padding(.bottom, 18)

                if canDevelop {
                    Button { Task { await develop() } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles").font(.system(size: 13, weight: .bold))
                            Text("card.develop").font(Theme.label(12)).tracking(1)
                        }
                        .foregroundStyle(Theme.accentBright)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(Theme.accent.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
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
