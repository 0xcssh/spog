import SwiftUI
import UIKit

/// Le moment où la carte apparaît. C'est la récompense de la boucle :
/// jusqu'ici, une prise ajoutait silencieusement une carte au garage et le joueur
/// devait aller la chercher. Un jeu de collection se joue sur cette seconde-là.
struct CatchRevealView: View {

    let card: CardData
    let isNewModel: Bool
    let questReward: Int
    var onScanAgain: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .developing
    @State private var scanLine = false
    @State private var shownPoints = 0

    private enum Phase { case developing, revealed }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if phase == .revealed, let glow = card.tier.frameColor {
                RadialGradient(colors: [glow.opacity(0.18), .clear],
                               center: .center, startRadius: 20, endRadius: 380)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 20)
                Overline(text: phase == .developing ? "reveal.developing" : "reveal.caught",
                         color: phase == .developing ? Theme.textMuted : card.tier.color)
                Spacer(minLength: 14)

                cardStage
                    .frame(maxWidth: 280)

                Spacer(minLength: 14)
                if phase == .revealed { details.transition(.opacity.combined(with: .move(edge: .bottom))) }
                Spacer(minLength: 14)
                if phase == .revealed { actions.transition(.opacity) }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .preferredColorScheme(.dark)
        .task { await run() }
    }

    // MARK: Développement puis révélation

    private var cardStage: some View {
        ZStack {
            CollectibleCardView(card: card, interactive: phase == .revealed)
                .blur(radius: phase == .developing ? 14 : 0)
                .saturation(phase == .developing ? 0.15 : 1)
                .scaleEffect(phase == .developing ? 0.9 : 1)

            if phase == .developing {
                // Ligne de développement, comme un tirage qui apparaît.
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, Theme.accentBright, .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 2)
                    .shadow(color: Theme.accentBright, radius: 10)
                    .offset(y: scanLine ? 150 : -150)
                    .allowsHitTesting(false)
            }
        }
    }

    private var details: some View {
        VStack(spacing: 12) {
            if isNewModel {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 11, weight: .bold))
                    Text("reveal.newModel").font(Theme.label(11)).tracking(1)
                }
                .foregroundStyle(Color(hex: 0x22D3EE))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color(hex: 0x22D3EE).opacity(0.13), in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "+\(shownPoints)")
                    .font(Theme.display(34, .heavy))
                    .foregroundStyle(card.tier.color)
                    .contentTransition(.numericText())
                Text("stat.points")
                    .font(Theme.label(12)).tracking(1.4).textCase(.uppercase)
                    .foregroundStyle(Theme.textSecondary)
            }

            if questReward > 0 {
                HStack(spacing: 7) {
                    Image(systemName: "trophy.fill").font(.system(size: 11))
                    Text("reveal.questDone \(questReward)")
                        .font(Theme.mono(11, .semibold))
                }
                .foregroundStyle(RarityTier.trophyGold)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RarityTier.trophyGold.opacity(0.13), in: Capsule())
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button { onScanAgain(); dismiss() } label: {
                Text("reveal.again")
                    .font(Theme.label(13)).tracking(1.2)
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(colors: [Theme.accentBright, Theme.accent],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule())
            }
            .buttonStyle(.plain)

            Button { dismiss() } label: {
                Text("reveal.toGarage")
                    .font(Theme.label(11)).tracking(1)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Déroulé

    private func run() async {
        withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
            scanLine = true
        }
        try? await Task.sleep(for: .milliseconds(1_150))

        // Une secousse proportionnelle à la rareté : le corps sait avant les yeux.
        UIImpactFeedbackGenerator(style: card.tier.isTrophy ? .heavy : .light)
            .impactOccurred()

        withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { phase = .revealed }

        // Les points montent plutôt que d'apparaître : c'est ce qui fait la récompense.
        let total = card.tier.points
        let steps = min(total, 26)
        guard steps > 0 else { shownPoints = total; return }
        for index in 1...steps {
            try? await Task.sleep(for: .milliseconds(26))
            withAnimation(.easeOut(duration: 0.12)) {
                shownPoints = total * index / steps
            }
        }
    }
}
