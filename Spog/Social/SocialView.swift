import SwiftUI
import UIKit

/// Le jeu à plusieurs : ligue de la semaine, chasse aux primes, duels, puis le profil.
///
/// La ligue est le cœur de l'écran : trente joueurs du même palier, remis à zéro chaque
/// lundi, les premiers montent et les derniers descendent. C'est le serveur qui compte
/// (voir backend/functions/identify/social.ts) ; l'écran ne fait qu'afficher, et calcule
/// seulement ce qui se déduit de la liste reçue — l'écart avec le joueur du dessus, la
/// distance à la zone de montée. Une liste de trente lignes ne disait pas au joueur ce
/// qu'il avait à faire ; « encore 12 points pour passer 6e », si.
struct SocialView: View {
    /// Vers le scanner : un état vide qui n'offre pas le geste qui le remplit est une
    /// impasse.
    private let onScan: () -> Void
    /// Vers le garage, où vit le pack de primes à ouvrir.
    private let onOpenGarage: () -> Void

    /// Écrit à la main : avec des `@State` privés, l'initialiseur implicite peut devenir
    /// privé, et `RootView`, dans un autre fichier, ne pourrait plus l'appeler.
    init(onScan: @escaping () -> Void = {}, onOpenGarage: @escaping () -> Void = {}) {
        self.onScan = onScan
        self.onOpenGarage = onOpenGarage
    }

    @Environment(AppState.self) private var app
    @Environment(GarageStore.self) private var garage
    @Environment(ReferralStore.self) private var referral
    @Environment(AccountStore.self) private var account
    @Environment(BountyStore.self) private var bounty

    @State private var enteringCode = false
    @State private var choosingPseudo = false
    @State private var appleFailed = false
    /// Code copie a l'instant : la coche remplace l'icone une seconde.
    @State private var justCopied = false

    private typealias League = AccountStore.League
    private typealias Member = AccountStore.League.Member

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SectionHeader(overline: "social.section",
                              title: String(localized: "social.title"))
                leagueBlock
                huntBlock
                DuelsBlock()
                identityBlock
                if account.profile?.apple_linked == false { appleBlock }
                referralBlock
                crewBlock
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await account.refresh()
            await bounty.refresh(country: app.country)
        }
        .task { await account.refresh() }
        // Lecture seule : le même appel que le garage, pour que le résumé de la chasse soit
        // à jour même si le joueur n'est pas passé par le garage depuis le lancement.
        .task(id: app.country) { await bounty.refresh(country: app.country) }
        .sheet(isPresented: $enteringCode) { ReferralEntrySheet() }
        .sheet(isPresented: $choosingPseudo) { PseudoSheet() }
        .alert(String(localized: "account.apple.failed"), isPresented: $appleFailed) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        }
    }

    // MARK: Ligue

    private var leagueBlock: some View {
        let tint = account.league.map { Theme.leagueColor($0.tier) } ?? Theme.accent
        return GlassCard(radius: 24, tint: tint, padding: 16) {
            VStack(alignment: .leading, spacing: 16) {
                leagueHeader
                if let league = account.league {
                    if league.joined {
                        let ranked = league.members.sorted { $0.rank < $1.rank }
                        if let me = ranked.first(where: \.me) {
                            myStanding(league, ranked: ranked, me: me)
                        }
                        if account.profile != nil && account.profile?.pseudo == nil {
                            anonymousHint
                        }
                        if ranked.count >= 3 {
                            podium(Array(ranked.prefix(3)))
                        }
                        standings(league, ranked: ranked, skipping: ranked.count >= 3 ? 3 : 0)
                        Text("league.rules \(league.promote) \(league.demote)")
                            .font(Theme.mono(9))
                            .foregroundStyle(Theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        notJoinedState
                    }
                } else if account.isRefreshing {
                    HStack {
                        Spacer()
                        ProgressView().tint(Theme.accentBright)
                        Spacer()
                    }
                    .padding(.vertical, 24)
                } else {
                    EmptySlot(icon: "wifi.slash", message: "league.offline")
                }
            }
        }
    }

    /// Blason, palier et compte à rebours. Le compte à rebours fait partie du jeu : il
    /// pousse à sortir avant lundi.
    private var leagueHeader: some View {
        HStack(alignment: .center, spacing: 13) {
            LeagueCrest(color: account.league.map { Theme.leagueColor($0.tier) } ?? Theme.accent)
                .frame(width: 50, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Overline(text: "league.overline", color: Theme.accentBright)
                if let league = account.league {
                    Text(LocalizedStringKey("league.tier.\(league.tier)"))
                        .font(Theme.display(26, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 6)
            if let ends = account.league?.endsAt {
                LeagueCountdown(ends: ends)
            }
        }
    }

    /// Ma place et mes points en grand, la zone où je me trouve, et ce qu'il me faut pour
    /// grimper. Les écarts sont calculés ici à partir de la liste du serveur : ils ne
    /// demandent aucune donnée de plus.
    private func myStanding(_ league: League, ranked: [Member], me: Member) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("league.you.rank")
                        .font(Theme.label(9)).tracking(1.2).textCase(.uppercase)
                        .foregroundStyle(Theme.textMuted)
                    Text(verbatim: LeagueFormat.ordinal(me.rank))
                        .font(Theme.hero(50))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accentGradient)
                        .shadow(color: Theme.accent.opacity(0.45), radius: 12)
                        .contentTransition(.numericText(value: Double(me.rank)))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("league.you.points")
                        .font(Theme.label(9)).tracking(1.2).textCase(.uppercase)
                        .foregroundStyle(Theme.textMuted)
                    Text(me.points.formatted())
                        .font(Theme.hero(32))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText(value: Double(me.points)))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.bottom, 4)
                }
                Spacer(minLength: 0)
                zoneChip(league.zone(of: me))
                    .padding(.bottom, 8)
            }
            chaseLines(league, ranked: ranked, me: me)
        }
    }

    /// Une ou deux lignes d'objectif : la place juste au-dessus, puis — si le joueur est
    /// loin — la dernière place qui monte. Le leader, lui, voit son avance.
    @ViewBuilder
    private func chaseLines(_ league: League, ranked: [Member], me: Member) -> some View {
        if let index = ranked.firstIndex(where: \.me) {
            VStack(spacing: 7) {
                if index > 0 {
                    let above = ranked[index - 1]
                    // +1 : égaler ne suffit pas pour passer devant.
                    let gap = max(1, above.points - me.points + 1)
                    chaseRow(icon: "arrow.up.right",
                             text: Text("league.gap \(gap) \(LeagueFormat.ordinal(above.rank))"),
                             color: Theme.accentBright)
                } else if ranked.count > 1 {
                    let lead = me.points - ranked[1].points
                    chaseRow(icon: "crown.fill",
                             text: lead > 0 ? Text("league.lead \(lead)") : Text("league.tiedTop"),
                             color: RarityTier.trophyGold)
                } else {
                    chaseRow(icon: "crown.fill", text: Text("league.leadAlone"),
                             color: RarityTier.trophyGold)
                }
                // Plus bas que la place juste sous la zone de montée : l'écart avec la
                // dernière place qui monte devient l'objectif qui compte vraiment.
                // Cherchée par son rang, pas par sa position dans la liste : rien ne garantit
                // que le serveur renverra toujours les trente lignes.
                if me.rank > league.promote + 1,
                   let cutoff = ranked.first(where: { $0.rank == league.promote }) {
                    let gap = max(1, cutoff.points - me.points + 1)
                    chaseRow(icon: "arrow.up.to.line", text: Text("league.toPromotion \(gap)"),
                             color: Theme.cyan)
                }
            }
        }
    }

    private func chaseRow(icon: String, text: Text, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.14), in: Circle())
            text
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.surfaceRaised.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(color.opacity(0.22), lineWidth: 1))
    }

    private func zoneChip(_ zone: League.Zone) -> some View {
        switch zone {
        case .promotion:
            return InfoChip(icon: "arrow.up", text: Text("league.zone.promotion"), color: Theme.cyan)
        case .demotion:
            return InfoChip(icon: "arrow.down", text: Text("league.zone.demotion"), color: Theme.warning)
        case .safe:
            return InfoChip(icon: "equal", text: Text("league.zone.safe"), color: Theme.textSecondary)
        }
    }

    /// Sans pseudo, le joueur figure au classement sous un nom générique : on le lui dit
    /// là où ça se voit, sans jamais l'obliger.
    private var anonymousHint: some View {
        Button { choosingPseudo = true } label: {
            HStack(spacing: 9) {
                Image(systemName: "at")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accentBright)
                Text("league.anonymousHint")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
    }

    /// Les trois premiers sur un podium : la tête du groupe se voit avant de se lire.
    private func podium(_ top: [Member]) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            podiumStep(top[1], place: 2, height: 44)
            podiumStep(top[0], place: 1, height: 62)
            podiumStep(top[2], place: 3, height: 32)
        }
        .padding(.top, 10)
    }

    private func podiumStep(_ member: Member, place: Int, height: CGFloat) -> some View {
        let color = podiumColor(place)
        let side: CGFloat = place == 1 ? 50 : 42
        return VStack(spacing: 5) {
            ZStack {
                Circle().fill(Theme.surfaceRaised)
                if let initial = member.pseudo?.first {
                    Text(String(initial).uppercased())
                        .font(Theme.hero(place == 1 ? 21 : 17))
                        .foregroundStyle(color)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: place == 1 ? 18 : 15, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .frame(width: side, height: side)
            .overlay(Circle().strokeBorder(member.me ? Theme.accentBright : color,
                                           lineWidth: member.me ? 2.5 : 1.5))
            .shadow(color: color.opacity(0.5), radius: 9)
            .overlay(alignment: .top) {
                if place == 1 {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(color)
                        .shadow(color: color.opacity(0.8), radius: 5)
                        .offset(y: -14)
                }
            }

            Text(member.pseudo.map { "@\($0)" } ?? String(localized: "social.anonymous"))
                .font(Theme.mono(10, member.me ? .bold : .medium))
                .foregroundStyle(member.me ? Theme.accentBright : Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(member.points.formatted())
                .font(Theme.mono(11, .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)

            ZStack(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 0,
                                       bottomTrailingRadius: 0, topTrailingRadius: 10,
                                       style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.34), color.opacity(0.04)],
                                         startPoint: .top, endPoint: .bottom))
                Text(verbatim: "\(place)")
                    .font(Theme.hero(18))
                    .foregroundStyle(color)
                    .padding(.top, 5)
            }
            .frame(height: height)
        }
        .frame(maxWidth: .infinity)
    }

    /// Or, argent, bronze : les teintes des paliers du même nom, pour rester une palette.
    private func podiumColor(_ place: Int) -> Color {
        switch place {
        case 1: return RarityTier.trophyGold
        case 2: return Theme.leagueColor("silver")
        default: return Theme.leagueColor("bronze")
        }
    }

    /// Le reste du groupe, avec les frontières de montée et de descente tracées dans la
    /// liste : une flèche par ligne ne montrait pas où passait la limite.
    private func standings(_ league: League, ranked: [Member], skipping: Int) -> some View {
        let shown = Array(ranked.dropFirst(skipping))
        let firstDemoted = ranked.count - league.demote + 1
        return VStack(spacing: 6) {
            ForEach(shown) { member in
                let zone = league.zone(of: member)
                if zone == .demotion && member.rank == firstDemoted {
                    zoneDivider(icon: "arrow.down", text: "league.zone.demotion", color: Theme.warning)
                }
                leagueRow(member, zone: zone)
                if member.rank == league.promote && member.rank < ranked.count {
                    zoneDivider(icon: "arrow.up", text: "league.zone.promotion", color: Theme.cyan)
                }
            }
        }
    }

    private func zoneDivider(icon: String, text: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(color.opacity(0.35)).frame(height: 1)
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 8, weight: .bold))
                Text(text)
                    .font(Theme.label(8)).tracking(1.2).textCase(.uppercase)
                    .lineLimit(1).fixedSize()
            }
            .foregroundStyle(color)
            Rectangle().fill(color.opacity(0.35)).frame(height: 1)
        }
        .padding(.vertical, 3)
    }

    private func leagueRow(_ member: Member, zone: League.Zone) -> some View {
        HStack(spacing: 11) {
            Text(verbatim: "\(member.rank)")
                .font(Theme.mono(13, .bold))
                .foregroundStyle(member.me ? Theme.background : Theme.textMuted)
                .frame(width: 26, height: 26)
                .background {
                    if member.me {
                        Circle().fill(Theme.accentGradient)
                    } else {
                        Circle().fill(Theme.surfaceRaised)
                    }
                }
            Text(member.pseudo.map { "@\($0)" } ?? String(localized: "social.anonymous"))
                .font(Theme.mono(12, member.me ? .bold : .regular))
                .foregroundStyle(member.pseudo == nil ? Theme.textMuted : Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(member.points.formatted())
                .font(Theme.mono(13, .bold))
                .monospacedDigit()
                .foregroundStyle(member.me ? Theme.accentBright : Theme.textSecondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(member.me ? Theme.accent.opacity(0.14) : .clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if member.me {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1)
            }
        }
        // La zone se lit aussi d'un trait à gauche, sans couleur criarde.
        .overlay(alignment: .leading) {
            switch zone {
            case .promotion:
                Capsule().fill(Theme.cyan).frame(width: 2.5, height: 18).offset(x: -1)
            case .demotion:
                Capsule().fill(Theme.warning.opacity(0.7)).frame(width: 2.5, height: 18).offset(x: -1)
            case .safe:
                EmptyView()
            }
        }
    }

    /// Pas encore de prise cette semaine : l'écran montre le geste qui inscrit, au lieu
    /// d'un classement vide.
    private var notJoinedState: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accentBright)
                    .frame(width: 40, height: 40)
                    .background(Theme.accent.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("league.notJoined.title")
                        .font(Theme.display(18))
                        .foregroundStyle(Theme.textPrimary)
                    Text("league.notJoined")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Button { onScan() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "viewfinder").font(.system(size: 13, weight: .bold))
                    Text("league.scanCta")
                }
            }
            .buttonStyle(NeonButtonStyle())
        }
    }

    // MARK: Chasse de la semaine

    /// Résumé du pack de primes, en lecture seule : le pack s'ouvre et se détaille dans le
    /// garage. Ici, on rappelle ce qui reste à chasser et le gros bonus encore libre.
    @ViewBuilder private var huntBlock: some View {
        if let pack = bounty.pack {
            GlassCard(radius: 22, tint: Theme.cyan, padding: 16) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .center, spacing: 11) {
                        Image(systemName: "scope")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.background)
                            .frame(width: 30, height: 30)
                            .background(Theme.accentGradient, in: Circle())
                            .shadow(color: Theme.accent.opacity(0.6), radius: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Overline(text: "bounty.overline", color: Theme.accentBright)
                            Group {
                                if pack.opened {
                                    Text("bounty.progress \(pack.foundCount) \(pack.targets.count)")
                                } else {
                                    Text("bounty.sealed.title")
                                }
                            }
                            .font(Theme.display(17))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Spacer(minLength: 6)
                        if let ends = pack.endsAt {
                            InfoChip(icon: "clock",
                                     text: Text("bounty.endsIn \(ends.formatted(.relative(presentation: .numeric)))"))
                        }
                    }

                    if pack.opened {
                        if !pack.targets.isEmpty {
                            SegmentedBar(progress: Double(pack.foundCount) / Double(pack.targets.count),
                                         color: Theme.cyan, segments: pack.targets.count, height: 5)
                        }
                        VStack(spacing: 7) {
                            ForEach(pack.targets) { target in huntRow(target) }
                        }
                        if pack.foundCount < pack.targets.count {
                            Button { onScan() } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "viewfinder").font(.system(size: 11, weight: .bold))
                                    Text("social.hunt.go")
                                }
                            }
                            .buttonStyle(NeonButtonStyle(prominent: false))
                        }
                    } else {
                        Text("social.hunt.sealed")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button { onOpenGarage() } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "sparkles").font(.system(size: 11, weight: .bold))
                                Text("social.hunt.open")
                            }
                        }
                        .buttonStyle(NeonButtonStyle())
                        .shimmer()
                    }
                }
            }
        }
    }

    private func huntRow(_ target: BountyStore.Target) -> some View {
        let tier = CatalogStore.shared.tier(target.tier)
        return HStack(spacing: 11) {
            Image(systemName: target.found ? "checkmark.seal.fill" : "scope")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(target.found ? tier.color : Theme.textMuted)
                .frame(width: 30, height: 30)
                .background(tier.color.opacity(target.found ? 0.18 : 0.08), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(target.make.uppercased())
                    .font(Theme.label(8)).tracking(1.2)
                    .foregroundStyle(tier.color)
                    .lineLimit(1)
                Text(target.model)
                    .font(Theme.display(14, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            Text(huntStatus(target))
                .font(Theme.mono(9, .semibold))
                .foregroundStyle(target.found ? tier.color
                                 : target.takenFirst ? Theme.textSecondary : RarityTier.trophyGold)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .frame(maxWidth: 130, alignment: .trailing)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.surfaceRaised.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Mêmes états que la carte du garage (`BountyTargetCard`), mêmes textes : la chasse se
    /// lit pareil d'un onglet à l'autre.
    private func huntStatus(_ target: BountyStore.Target) -> String {
        if target.found { return String(localized: "bounty.found") }
        if target.takenFirst {
            if case .some(.some(let pseudo)) = target.first_hunter {
                return String(localized: "bounty.takenBy \(pseudo) \(target.bonus)")
            }
            return String(localized: "bounty.taken \(target.bonus)")
        }
        return String(localized: "bounty.open.bonus \(target.bonus + target.first_bonus)")
    }

    // MARK: Identité

    /// Le pseudo, et ce que le serveur sait du joueur. Sans pseudo, le joueur figure au
    /// classement sous un nom générique : le choisir n'est jamais obligatoire.
    private var identityBlock: some View {
        GlassCard(radius: 22, tint: Theme.accent, padding: 16) {
            VStack(alignment: .leading, spacing: 16) {
                Button { choosingPseudo = true } label: {
                    HStack(spacing: 14) {
                        avatar
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Overline(text: "social.you.overline", color: Theme.accentBright)
                                if account.profile?.apple_linked == true {
                                    Image(systemName: "checkmark.shield.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Theme.cyan)
                                        .accessibilityLabel(Text("account.linked"))
                                }
                            }
                            Text(account.profile?.pseudo.map { "@\($0)" } ?? String(localized: "social.pseudo.choose"))
                                .font(Theme.display(22))
                                .foregroundStyle(account.profile?.pseudo == nil ? Theme.accentBright : Theme.textPrimary)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Theme.surfaceRaised, in: Circle())
                    }
                }
                .buttonStyle(PressScaleStyle(scale: 0.98))

                HStack(spacing: 12) {
                    MetricCell(value: account.profile?.catches ?? garage.catches.count, label: "social.stat.catches")
                    HairlineDivider()
                    MetricCell(value: account.profile?.points ?? garage.totalPoints, label: "social.stat.points",
                               color: Theme.accentBright)
                    HairlineDivider()
                    MetricCell(value: account.profile?.first_spots ?? 0, label: "social.stat.firstSpots",
                               color: RarityTier.trophyGold)
                }
            }
        }
    }

    /// Pastille du joueur : l'initiale de son pseudo dans un anneau néon, ou une
    /// silhouette tant qu'il n'en a pas choisi.
    private var avatar: some View {
        ZStack {
            Circle().fill(Theme.surfaceRaised)
            if let initial = account.profile?.pseudo?.first {
                Text(String(initial).uppercased())
                    .font(Theme.hero(24))
                    .foregroundStyle(Theme.accentGradient)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .frame(width: 56, height: 56)
        .overlay(Circle().strokeBorder(Theme.accentGradient, lineWidth: 2))
        .shadow(color: Theme.accent.opacity(0.5), radius: 12)
    }

    // MARK: Compte Apple

    /// Facultatif : il sert à retrouver sa collection et son rang sur un autre appareil.
    /// Un bouton seul ne disait pas pourquoi le toucher ; les bénéfices le disent.
    private var appleBlock: some View {
        GlassCard(radius: 22, tint: Theme.accent, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Overline(text: "account.apple.overline", color: Theme.accentBright)
                    Text("account.apple.title")
                        .font(Theme.display(20))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                AccountBenefitsList()
                AppleLinkButton { outcome in
                    if outcome == .failed { appleFailed = true }
                }
                AccountPrivacyNote()
            }
        }
    }

    // MARK: Crew

    private var crewBlock: some View {
        GlassCard(radius: 22, tint: Theme.cyan, padding: 16) {
            VStack(alignment: .leading, spacing: 13) {
                Overline(text: "social.crew", color: Theme.cyan)
                EmptySlot(icon: "flag.2.crossed", message: "social.crewEmpty")
                HStack(spacing: 9) {
                    LockedButton(icon: "plus", label: "social.createCrew")
                    LockedButton(icon: "arrow.right.to.line", label: "social.joinCrew")
                }
            }
        }
    }

    // MARK: Parrainage

    /// Le parrainage est la seule partie « sociale » qui marche vraiment aujourd'hui :
    /// partager un code et en saisir un ne demandent ni compte ni serveur. La recompense,
    /// elle, en demande un — elle est donc annoncee comme attendue, pas comme acquise.
    private var referralBlock: some View {
        GlassCard(radius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 13) {
                Overline(text: "social.referral")

                HStack(spacing: 10) {
                    Text(referral.myCode)
                        .font(Theme.mono(21, .bold)).tracking(5)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 4)
                    Button { copyCode() } label: {
                        Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(justCopied ? Theme.accent : Theme.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(Theme.surfaceRaised, in: Circle())
                    }
                    .buttonStyle(.plain)
                    ShareLink(item: referral.shareText) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(Theme.surfaceRaised, in: Circle())
                    }
                }
                .padding(.horizontal, 13).padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.accent.opacity(0.25), lineWidth: 1))

                Text("social.referral.how")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                sponsorRow
            }
        }
    }

    /// Le code de celui qui t'a parraine : deja utilise, propose par un lien, ou a saisir.
    @ViewBuilder private var sponsorRow: some View {
        if let code = referral.enteredCode {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
                Text("social.referral.used \(code)")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 6)
                Text("social.soon")
                    .font(Theme.label(8)).tracking(1).textCase(.uppercase)
                    .lineLimit(1).fixedSize()
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Theme.textMuted.opacity(0.14), in: Capsule())
            }
            .padding(.horizontal, 11).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Button { enteringCode = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                    // Un lien deja ouvert a rempli le code : on le dit, plutot que de
                    // laisser le joueur le retaper de memoire.
                    Text(referral.pendingFromLink == nil
                         ? "social.referral.enter"
                         : "social.referral.fromLink")
                        .font(Theme.label(11)).tracking(0.8)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 11).padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func copyCode() {
        UIPasteboard.general.string = referral.myCode
        withAnimation { justCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { justCopied = false }
        }
    }
}

/// Mise en forme des rangs : « 6e » en français, « 6th » en anglais. `NumberFormatter`
/// connaît les ordinaux de chaque langue ; une clé « %lldᵉ » se serait trompée sur « 1er ».
enum LeagueFormat {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        // La langue de l'interface, pas la région de l'appareil : un iPhone réglé en
        // anglais sur un compte français afficherait sinon « 6e » au milieu de l'anglais.
        formatter.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        return formatter
    }()

    static func ordinal(_ rank: Int) -> String {
        formatter.string(from: NSNumber(value: rank)) ?? "\(rank)"
    }
}

/// Blason du palier : un écu plein à la teinte de la ligue, qui accroche la lumière. Une
/// simple icône à côté du nom ne donnait aucun poids au palier atteint.
private struct LeagueCrest: View {
    let color: Color

    init(color: Color) {
        self.color = color
    }

    var body: some View {
        ZStack {
            Image(systemName: "shield.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(LinearGradient(colors: [color, color.opacity(0.45)],
                                                startPoint: .top, endPoint: .bottom))
            Image(systemName: "shield")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Theme.highlight.opacity(0.35))
            Image(systemName: "star.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.background.opacity(0.75))
                .offset(y: -2)
        }
        .shadow(color: color.opacity(0.7), radius: 12)
        .accessibilityHidden(true)
    }
}

/// Compte à rebours jusqu'à la remise à zéro de lundi. Il passe à l'orange et prend une
/// flamme le dernier jour : l'urgence doit se voir sans lire les chiffres.
private struct LeagueCountdown: View {
    let ends: Date

    init(ends: Date) {
        self.ends = ends
    }

    var body: some View {
        // Une minute suffit : le compte n'affiche pas les secondes.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let left = max(0, ends.timeIntervalSince(context.date))
            let urgent = left < 86_400
            InfoChip(icon: urgent ? "flame.fill" : "clock",
                     text: Self.text(left),
                     color: urgent ? Theme.warning : Theme.textSecondary)
        }
    }

    private static func text(_ left: TimeInterval) -> Text {
        let minutes = Int(left / 60)
        let days = minutes / 1_440
        let hours = (minutes % 1_440) / 60
        if days > 0 { return Text("league.countdown.days \(days) \(hours)") }
        return Text("league.countdown.hours \(hours) \(minutes % 60)")
    }
}


/// Saisie d'un code de parrainage, depuis l'onglet Social ou depuis le paywall — c'est
/// souvent la qu'on se souvient qu'un ami en a donne un. Memes regles que dans
/// l'onboarding : un seul endroit decide de ce qu'est un code valable, `ReferralStore`.
struct ReferralEntrySheet: View {
    @Environment(ReferralStore.self) private var referral
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("social.referral.enterWhy")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField(text: $code) { Text("referral.placeholder") }
                    .focused($typing)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { save() }
                    .font(Theme.mono(22, .bold)).tracking(6)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16).padding(.vertical, 16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(typing ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1))
                    .onChange(of: code) { _, typed in
                        let cleaned = ReferralStore.normalize(typed)
                        if cleaned != typed { code = cleaned }
                    }

                feedback
                Spacer()

                Button { save() } label: {
                    Text("social.referral.save")
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
                .disabled(referral.check(code) != .ready)
                .opacity(referral.check(code) == .ready ? 1 : 0.45)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.background)
            .navigationTitle(Text("social.referral"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Text("common.close") }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            code = referral.pendingFromLink ?? ""
            typing = true
        }
    }

    @ViewBuilder private var feedback: some View {
        switch referral.check(code) {
        case .ready:
            line("checkmark.circle.fill", "referral.valid", Theme.accent)
        case .ownCode:
            line("exclamationmark.triangle.fill", "referral.ownCode", RarityTier.trophyGold)
        case .tooShort:
            line("ellipsis.circle", "referral.tooShort", Theme.textMuted)
        case .empty:
            EmptyView()
        }
    }

    private func line(_ icon: String, _ text: LocalizedStringKey, _ color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
    }

    private func save() {
        guard referral.apply(code) else { return }
        referral.pendingFromLink = nil
        dismiss()
    }
}

/// Emplacement vide, dessine en pointilles : il montre ce qui viendra s'y loger.
private struct EmptySlot: View {
    let icon: String
    let message: LocalizedStringKey

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accentBright)
                .frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.12), in: Circle())
            Text(message)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.vertical, 17).padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Theme.strokeStrong)
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
