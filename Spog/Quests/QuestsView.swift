import SwiftUI

/// Quetes : la quete du jour, la serie, le niveau, les statistiques et les badges.
/// Tout ce qui releve de la progression vit ici — le garage ne montre que les voitures.
struct QuestsView: View {
    @Environment(AppState.self) private var app
    @Environment(GarageStore.self) private var garage
    @Environment(ProgressStore.self) private var progress
    @Environment(PlayerProfile.self) private var profile
    @State private var glow = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                emblem
                levelBar
                questCard
                streakStrip
                tiles
                rarityBreakdown
                badgeRow
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: Embleme

    private var emblem: some View {
        VStack(spacing: 12) {
            Image("LogoMark")
                .resizable()
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Theme.strokeStrong, lineWidth: 1)
                )
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { glow = true }
                }

            HStack(spacing: 7) {
                Overline(text: "profile.level")
                Text("\(Progression.level(for: totalPoints))")
                    .font(Theme.display(20))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(.top, 4)
    }

    private var levelBar: some View {
        NeonFrame(radius: 16) {
            VStack(spacing: 10) {
                SegmentedBar(progress: Progression.progress(for: totalPoints))
                HStack {
                    Text("\(totalPoints.formatted()) pts")
                        .font(Theme.mono(11, .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("profile.toNext \(Progression.toNextLevel(for: totalPoints))")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .padding(14)
        }
    }

    /// La quete du jour. Meme objectif pour tout le monde, tire de la date.
    private var questCard: some View {
        let quest = QuestFactory.quest(for: Date(), country: app.country,
                                        favourites: profile.favouriteList)
        let done = progress.isDone(quest)
        return NeonFrame(radius: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Overline(text: "quest.section")
                    Text(quest.title)
                        .font(Theme.mono(15, .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                if done {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        Text("quest.done").font(Theme.label(10)).tracking(1)
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Theme.surfaceRaised, in: Capsule())
                } else {
                    Text("+\(quest.reward)")
                        .font(Theme.mono(13, .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(Theme.surfaceRaised, in: Capsule())
                        .overlay(Capsule().stroke(Theme.strokeStrong, lineWidth: 1))
                }
            }
            .padding(14)
        }
    }

    /// La serie en cours, mise en avant : c'est elle qui fait revenir tous les jours.
    private var streakStrip: some View {
        let alive = progress.currentStreak > 0
        // La flamme seule garde l'ambre quand la série est vivante : un petit signal, pas
        // un cadre doré de plus.
        return NeonFrame(radius: 16) {
            HStack(spacing: 13) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 21))
                    .foregroundStyle(alive ? Theme.warning : Theme.textMuted)
                VStack(alignment: .leading, spacing: 3) {
                    Overline(text: "stat.streak")
                    Text(alive ? String(localized: "streak.days \(progress.currentStreak)")
                               : String(localized: "streak.none"))
                        .font(Theme.mono(15, .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Overline(text: "stat.bestStreak")
                    Text("\(progress.bestStreak)")
                        .font(Theme.mono(15, .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(14)
        }
    }

    // MARK: Chiffres

    private var totalPoints: Int { garage.totalPoints + progress.bonusPoints }

    private var tiles: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                NeonTile(icon: "square.stack.3d.up.fill", value: "\(garage.cards.count)",
                         label: "stat.catches", color: Theme.textSecondary)
                NeonTile(icon: "car.2.fill", value: "\(garage.uniqueModels)",
                         label: "stat.models", color: Theme.textSecondary)
                NeonTile(icon: "building.2.fill", value: "\(garage.uniqueBrands)",
                         label: "stat.brands", color: Theme.textSecondary)
            }
            HStack(spacing: 10) {
                NeonTile(icon: "crown.fill",
                         value: garage.bestCard.map { "\($0.tier.points)" } ?? "—",
                         label: "stat.best", color: Theme.textSecondary)
                NeonTile(icon: "bolt.fill", value: progress.bonusPoints.formatted(),
                         label: "stat.bonus", color: Theme.textSecondary)
                NeonTile(icon: "checkmark.seal.fill", value: "\(garage.verifiedCount)",
                         label: "stat.verified", color: Theme.textSecondary)
            }
        }
    }

    private var rarityBreakdown: some View {
        NeonFrame(radius: 16) {
            VStack(alignment: .leading, spacing: 11) {
                Overline(text: "profile.rarities")
                let counts = garage.countByTier()
                let peak = max(1, counts.map(\.1).max() ?? 1)
                ForEach(counts, id: \.0.id) { tier, count in
                    StatRow(label: tier.label, value: count, total: peak, color: tier.color)
                }
            }
            .padding(14)
        }
    }

    private var badgeRow: some View {
        NeonFrame(radius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Overline(text: "profile.badges")
                HStack(spacing: 10) {
                    ForEach(garage.badges) { badge in
                        BadgeChip(icon: badge.icon, unlocked: badge.unlocked)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(14)
        }
    }
}
