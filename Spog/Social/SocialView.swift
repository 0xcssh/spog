import SwiftUI
import AuthenticationServices

/// Le jeu à plusieurs : pseudo, ligue de la semaine, compte Apple, parrainage.
///
/// La ligue est le cœur de l'écran : trente joueurs du même palier, remis à zéro chaque
/// lundi, les premiers montent et les derniers descendent. C'est le serveur qui compte
/// (voir backend/functions/identify/social.ts) ; l'écran ne fait qu'afficher.
struct SocialView: View {
    @Environment(AppState.self) private var app
    @Environment(GarageStore.self) private var garage
    @Environment(ProgressStore.self) private var progress
    @Environment(PlayerProfile.self) private var profile
    @Environment(ReferralStore.self) private var referral
    @Environment(AccountStore.self) private var account

    @State private var enteringCode = false
    @State private var choosingPseudo = false
    @State private var appleFailed = false
    /// Code copie a l'instant : la coche remplace l'icone une seconde.
    @State private var justCopied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionHeader(overline: "social.section",
                              title: String(localized: "social.title"))
                identityBlock
                leagueBlock
                if account.profile?.apple_linked == false { appleBlock }
                duelsBlock
                referralBlock
                crewBlock
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .refreshable { await account.refresh() }
        .task { await account.refresh() }
        .sheet(isPresented: $enteringCode) { ReferralEntrySheet() }
        .sheet(isPresented: $choosingPseudo) { PseudoSheet() }
        .alert(String(localized: "account.apple.failed"), isPresented: $appleFailed) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        }
    }

    // MARK: Identité

    /// Le pseudo, et ce que le serveur sait du joueur. Sans pseudo, le joueur figure au
    /// classement sous un nom générique : le choisir n'est jamais obligatoire.
    private var identityBlock: some View {
        NeonFrame(radius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Overline(text: "social.you.overline")
                Button { choosingPseudo = true } label: {
                    HStack(spacing: 10) {
                        Text(account.profile?.pseudo.map { "@\($0)" } ?? String(localized: "social.pseudo.choose"))
                            .font(Theme.mono(18, .bold))
                            .foregroundStyle(account.profile?.pseudo == nil ? Theme.accentBright : Theme.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Spacer(minLength: 6)
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 0) {
                    stat(value: account.profile?.catches ?? garage.catches.count, label: "social.stat.catches")
                    stat(value: account.profile?.points ?? garage.totalPoints, label: "social.stat.points")
                    stat(value: account.profile?.first_spots ?? 0, label: "social.stat.firstSpots")
                }
            }
            .padding(14)
        }
    }

    private func stat(value: Int, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.formatted())
                .font(Theme.mono(17, .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(Theme.mono(9))
                .foregroundStyle(Theme.textMuted)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Ligue

    private var leagueBlock: some View {
        NeonFrame(radius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Overline(text: "league.overline")
                    Spacer()
                    if let ends = account.league?.endsAt {
                        // Le compte à rebours fait partie du jeu : il pousse à sortir avant lundi.
                        Text("league.endsIn \(ends.formatted(.relative(presentation: .numeric)))")
                            .font(Theme.mono(9))
                            .foregroundStyle(Theme.textMuted)
                    }
                }

                if let league = account.league {
                    Text(LocalizedStringKey("league.tier.\(league.tier)"))
                        .font(Theme.display(22))
                        .foregroundStyle(Theme.textPrimary)

                    if league.joined {
                        VStack(spacing: 6) {
                            ForEach(league.members) { member in
                                leagueRow(member, zone: league.zone(of: member))
                            }
                        }
                        Text("league.rules \(league.promote) \(league.demote)")
                            .font(Theme.mono(9))
                            .foregroundStyle(Theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        EmptySlot(icon: "trophy", message: "league.notJoined")
                    }
                } else {
                    EmptySlot(icon: "wifi.slash", message: "league.offline")
                }
            }
            .padding(14)
        }
    }

    private func leagueRow(_ member: AccountStore.League.Member, zone: AccountStore.League.Zone) -> some View {
        HStack(spacing: 11) {
            Text("\(member.rank)")
                .font(Theme.mono(13, .bold))
                .foregroundStyle(member.me ? Theme.background : Theme.textMuted)
                .frame(width: 26, height: 26)
                .background {
                    if member.me {
                        Circle().fill(LinearGradient(colors: [Theme.accentBright, Theme.accent],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                    } else {
                        Circle().fill(Theme.surfaceRaised)
                    }
                }
            Text(member.pseudo.map { "@\($0)" } ?? String(localized: "social.anonymous"))
                .font(Theme.mono(12, member.me ? .bold : .regular))
                .foregroundStyle(member.pseudo == nil ? Theme.textMuted : Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 6)
            switch zone {
            case .promotion:
                Image(systemName: "arrow.up").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.accentBright)
            case .demotion:
                Image(systemName: "arrow.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textMuted)
            case .safe:
                EmptyView()
            }
            Text(member.points.formatted())
                .font(Theme.mono(13, .bold))
                .foregroundStyle(member.me ? Theme.accentBright : Theme.textSecondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(member.me ? Theme.accent.opacity(0.10) : .clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Compte Apple

    /// Facultatif : il ne sert qu'à retrouver sa collection et son rang sur un autre
    /// appareil. Rien d'autre n'est demandé à Apple — ni nom, ni e-mail.
    private var appleBlock: some View {
        NeonFrame(radius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Overline(text: "account.apple.overline")
                Text("account.apple.why")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = []
                } onCompletion: { result in
                    guard case .success(let authorization) = result,
                          let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                          let token = credential.identityToken else {
                        if case .failure(let error) = result,
                           (error as? ASAuthorizationError)?.code == .canceled { return }
                        appleFailed = true
                        return
                    }
                    Task { if !(await account.linkApple(identityToken: token)) { appleFailed = true } }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 46)
                .clipShape(Capsule())
            }
            .padding(14)
        }
    }

    // MARK: Duels

    private var duelsBlock: some View {
        NeonFrame(radius: 16) {
            VStack(alignment: .leading, spacing: 13) {
                Overline(text: "social.duels")
                EmptySlot(icon: "figure.fencing", message: "social.duelsEmpty")
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

    // MARK: Parrainage

    /// Le parrainage est la seule partie « sociale » qui marche vraiment aujourd'hui :
    /// partager un code et en saisir un ne demandent ni compte ni serveur. La recompense,
    /// elle, en demande un — elle est donc annoncee comme attendue, pas comme acquise.
    private var referralBlock: some View {
        NeonFrame(radius: 16) {
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
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                sponsorRow
            }
            .padding(14)
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
