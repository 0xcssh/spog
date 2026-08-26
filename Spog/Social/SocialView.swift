import SwiftUI

/// Amis et crews. La structure est en place ; les fonctions collectives
/// attendent des comptes utilisateurs et un serveur (voir la note en bas d'ecran).
struct SocialView: View {
    @Environment(AppState.self) private var app
    @Environment(GarageStore.self) private var garage
    @Environment(ProgressStore.self) private var progress
    @Environment(PlayerProfile.self) private var profile

    private var totalPoints: Int { garage.totalPoints + progress.bonusPoints }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionHeader(overline: "social.section",
                              title: String(localized: "social.title"))
                friendsBlock
                crewBlock
                leaderboard
                note
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: Classement

    /// Le classement des amis. Pour l'instant il ne contient que le joueur —
    /// c'est volontairement montre plutot que cache : on voit ce qui viendra s'y ajouter.
    private var leaderboard: some View {
        NeonFrame(radius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Overline(text: "social.leaderboard")

                row(rank: 1, name: profile.displayName,
                    level: Progression.level(for: totalPoints),
                    points: totalPoints, isYou: true)

                ForEach(2...4, id: \.self) { rank in
                    emptyRow(rank: rank)
                }

                Text("social.leaderboardEmpty")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .padding(14)
        }
    }

    private func row(rank: Int, name: String, level: Int,
                     points: Int, isYou: Bool) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(Theme.mono(14, .bold))
                .foregroundStyle(isYou ? Theme.background : Theme.textMuted)
                .frame(width: 28, height: 28)
                .background {
                    if isYou {
                        Circle().fill(LinearGradient(colors: [Theme.accentBright, Theme.accent],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                    } else {
                        Circle().fill(Theme.surfaceRaised)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(Theme.mono(13, .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("profile.level \(level)")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            Text(points.formatted())
                .font(Theme.mono(14, .bold))
                .foregroundStyle(isYou ? Theme.accentBright : Theme.textSecondary)
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(isYou ? Theme.accent.opacity(0.10) : .clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isYou ? Theme.accent.opacity(0.35) : .clear, lineWidth: 1))
    }

    /// Place libre : ce que l'arrivee d'un ami viendra remplir.
    private func emptyRow(rank: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(Theme.mono(14, .bold))
                .foregroundStyle(Theme.textMuted.opacity(0.5))
                .frame(width: 28, height: 28)
            Capsule()
                .fill(Theme.textMuted.opacity(0.12))
                .frame(width: 84, height: 8)
            Spacer()
            Capsule()
                .fill(Theme.textMuted.opacity(0.12))
                .frame(width: 34, height: 8)
        }
        .padding(.horizontal, 11).padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Theme.stroke))
    }

    // MARK: Amis
    // MARK: Amis

    private var friendsBlock: some View {
        NeonFrame(radius: 16) {
            VStack(alignment: .leading, spacing: 13) {
                Overline(text: "social.friends")
                EmptySlot(icon: "person.2", message: "social.friendsEmpty")
                LockedButton(icon: "person.badge.plus", label: "social.invite")
            }
            .padding(14)
        }
    }

    // MARK: Crew

    private var crewBlock: some View {
        NeonFrame(color: Color(hex: 0x22D3EE), radius: 16, intensity: 0.7) {
            VStack(alignment: .leading, spacing: 13) {
                Overline(text: "social.crew")
                EmptySlot(icon: "flag.2.crossed", message: "social.crewEmpty")
                HStack(spacing: 9) {
                    LockedButton(icon: "plus", label: "social.createCrew")
                    LockedButton(icon: "arrow.right.to.line", label: "social.joinCrew")
                }
            }
            .padding(14)
        }
    }

    private var note: some View {
        Text("social.note")
            .font(Theme.mono(10))
            .foregroundStyle(Theme.textMuted)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

/// Emplacement vide, dessine en pointilles : il montre ce qui viendra s'y loger.
private struct EmptySlot: View {
    let icon: String
    let message: LocalizedStringKey

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textMuted)
            Text(message)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.vertical, 17).padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Theme.stroke)
        )
    }
}

/// Action pas encore disponible. Elle est montree, pas cachee : l'utilisateur
/// voit ou va l'app, sans se heurter a un bouton qui ne fait rien en silence.
private struct LockedButton: View {
    let icon: String
    let label: LocalizedStringKey

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(Theme.label(11)).tracking(0.8)
                .lineLimit(1).fixedSize()
            Spacer(minLength: 6)
            Text("social.soon")
                .font(Theme.label(8)).tracking(1).textCase(.uppercase)
                .lineLimit(1).fixedSize()
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Theme.textMuted.opacity(0.14), in: Capsule())
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 11).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }
}
