import SwiftUI

/// La chasse de la semaine, en tête du garage : un pack scellé à ouvrir, puis les trois
/// cibles épinglées jusqu'à lundi.
struct BountyPanel: View {
    @Environment(AppState.self) private var app
    @Environment(BountyStore.self) private var bounty
    @State private var opening: BountyStore.Pack?
    @State private var busy = false

    var body: some View {
        if let pack = bounty.pack {
            NeonFrame(radius: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Overline(text: "bounty.overline")
                        Spacer()
                        if let ends = pack.endsAt {
                            Text("bounty.endsIn \(ends.formatted(.relative(presentation: .numeric)))")
                                .font(Theme.mono(9))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    if pack.opened {
                        targets(pack)
                    } else {
                        sealed
                    }
                }
                .padding(14)
            }
            .fullScreenCover(item: $opening) { pack in
                BountyOpeningView(pack: pack) { opening = nil }
            }
        }
    }

    // MARK: Pack scellé

    private var sealed: some View {
        HStack(spacing: 14) {
            SealedPack()
                .frame(width: 58, height: 80)
            VStack(alignment: .leading, spacing: 6) {
                Text("bounty.sealed")
                    .font(Theme.display(15, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task {
                        busy = true
                        if let pack = await bounty.open(country: app.country) { opening = pack }
                        busy = false
                    }
                } label: {
                    Text("bounty.open")
                        .font(Theme.label(11)).tracking(1)
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(LinearGradient(colors: [Theme.accentBright, Theme.accent],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .opacity(busy ? 0.5 : 1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Cibles

    private func targets(_ pack: BountyStore.Pack) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(pack.targets) { target in
                    BountyTargetCard(target: target, compact: true)
                }
            }
            Text("bounty.hint")
                .font(Theme.mono(9))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Une cible du pack : silhouette, modèle, rareté locale, bonus, et l'état de la course.
struct BountyTargetCard: View {
    let target: BountyStore.Target
    var compact: Bool = false

    private var tier: RarityTier { CatalogStore.shared.tier(target.tier) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: CarBody(target.body).symbol)
                    .resizable().scaledToFit()
                    .foregroundStyle(target.found ? tier.color : Theme.textSecondary.opacity(0.7))
                    .frame(height: compact ? 22 : 44)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 6 : 14)
                if target.found {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: compact ? 11 : 16))
                        .foregroundStyle(tier.color)
                }
            }
            Text(target.make.uppercased())
                .font(Theme.mono(compact ? 7 : 9, .medium)).tracking(1)
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
            Text(target.model)
                .font(Theme.mono(compact ? 11 : 15, .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(tier.label)
                .font(Theme.label(compact ? 8 : 10)).tracking(0.8)
                .foregroundStyle(tier.color)
            Text(status)
                .font(Theme.mono(compact ? 8 : 10))
                .foregroundStyle(target.found ? tier.color : Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(compact ? 8 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tier.color.opacity(target.found ? 0.14 : 0.06),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(tier.color.opacity(target.found ? 0.6 : 0.25), lineWidth: 1))
    }

    /// Ce qui se joue sur cette cible : déjà trouvée, prise par un autre, ou ouverte avec le
    /// gros bonus du premier chasseur.
    private var status: String {
        if target.found { return String(localized: "bounty.found") }
        if target.takenFirst {
            if case .some(.some(let pseudo)) = target.first_hunter {
                return String(localized: "bounty.takenBy \(pseudo) \(target.bonus)")
            }
            return String(localized: "bounty.taken \(target.bonus)")
        }
        return String(localized: "bounty.open.bonus \(target.bonus + target.first_bonus)")
    }
}

/// Le pack scellé : une enveloppe néon, la seule image du jeu qui promette sans montrer.
private struct SealedPack: View {
    @State private var glow = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(colors: [Theme.accent.opacity(0.55), Theme.surfaceRaised],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image("LogoMark")
                    .resizable().scaledToFit()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .opacity(0.9)
            }
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.accentBright.opacity(glow ? 0.9 : 0.4), lineWidth: 1.2))
            .shadow(color: Theme.accent.opacity(glow ? 0.7 : 0.3), radius: glow ? 14 : 6)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { glow = true }
            }
    }
}

/// L'ouverture du pack : les trois cartes se retournent une à une, la plus rare en dernier.
/// C'est le frisson de l'ouverture, sans rien vendre au hasard : le pack ne donne pas la
/// voiture, il donne une mission.
struct BountyOpeningView: View {
    let pack: BountyStore.Pack
    let onDone: () -> Void
    @State private var revealed = 0

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.25), .clear],
                           center: .center, startRadius: 10, endRadius: 360)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Overline(text: "bounty.overline")
                Text("bounty.reveal.title")
                    .font(Theme.display(24))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    ForEach(Array(pack.targets.enumerated()), id: \.element.id) { index, target in
                        ZStack {
                            if index < revealed {
                                BountyTargetCard(target: target)
                                    .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity),
                                                            removal: .opacity))
                            } else {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Theme.surfaceRaised)
                                    .overlay(Image(systemName: "questionmark")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(Theme.textMuted))
                                    .frame(height: 92)
                            }
                        }
                        .frame(maxWidth: 320)
                    }
                }

                Text("bounty.hint")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(revealed >= pack.targets.count ? 1 : 0)

                Button(action: onDone) {
                    Text("bounty.reveal.done")
                        .font(Theme.label(13)).tracking(1.2)
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: 320)
                        .padding(.vertical, 15)
                        .background(LinearGradient(colors: [Theme.accentBright, Theme.accent],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
                .opacity(revealed >= pack.targets.count ? 1 : 0)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        .task {
            // Une carte toutes les 0,7 s : assez lent pour l'attente, assez vif pour ne pas lasser.
            for index in pack.targets.indices {
                try? await Task.sleep(for: .milliseconds(index == 0 ? 500 : 700))
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { revealed = index + 1 }
            }
        }
    }
}

extension BountyStore.Pack: Identifiable {
    var id: String { "\(week)-\(country)" }
}
