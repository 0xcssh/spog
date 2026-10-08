import SwiftUI

/// Les duels, dans l'onglet Social : les défis en cours avec le rapport de force, et de
/// quoi en lancer un nouveau ou en rejoindre un.
///
/// Le duel est l'endroit où le jeu devient personnel : on ne bat pas un inconnu du
/// classement, on bat un ami. L'écran montre donc d'abord deux noms face à face et qui
/// mène, puis le temps qui reste — le score seul, « 120 – 95 », ne disait pas qui gagnait.
struct DuelsBlock: View {
    @Environment(DuelStore.self) private var duels
    @State private var shareCode: String?
    @State private var joining = false
    @State private var creating = false
    @State private var createFailed = false

    /// Les duels qui se jouent d'abord, puis ceux qui attendent un adversaire, puis les
    /// résultats : ce qu'on peut encore changer passe avant ce qui est joué.
    private var ordered: [DuelStore.Duel] {
        func weight(_ duel: DuelStore.Duel) -> Int {
            if duel.finished { return 2 }
            return duel.joined ? 0 : 1
        }
        return duels.duels.enumerated()
            .sorted { (weight($0.element), $0.offset) < (weight($1.element), $1.offset) }
            .map { $0.element }
    }

    private var liveCount: Int { duels.duels.filter { $0.joined && !$0.finished }.count }
    private var wonCount: Int { duels.duels.filter { $0.outcome == .won }.count }

    var body: some View {
        GlassCard(radius: 22, tint: Theme.neutralAccent, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "figure.fencing")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Overline(text: "social.duels")
                    Spacer(minLength: 6)
                    if !duels.duels.isEmpty {
                        InfoChip(icon: "bolt.fill", text: Text("duel.record \(liveCount) \(wonCount)"),
                                 color: Theme.neutralAccent)
                    }
                }
                if duels.duels.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 9) {
                        ForEach(ordered) { duel in DuelRow(duel: duel) }
                    }
                }
                HStack(spacing: 9) {
                    actionButton("figure.fencing", "duel.challenge", primary: true) {
                        Task {
                            creating = true
                            if let code = await duels.create() { shareCode = code } else { createFailed = true }
                            creating = false
                        }
                    }
                    .disabled(creating)
                    .opacity(creating ? 0.6 : 1)
                    actionButton("number", "duel.haveCode", primary: false) { joining = true }
                }
            }
        }
        .task { await duels.refresh() }
        .sheet(item: Binding(get: { shareCode.map(ShareCode.init) }, set: { _ in shareCode = nil })) { item in
            ShareSheet(items: [DuelStore.shareText(item.code)])
        }
        .sheet(isPresented: $joining) { DuelJoinSheet(initialCode: "") }
        .sheet(item: Binding(get: { duels.pendingFromLink.map(ShareCode.init) },
                             set: { _ in duels.pendingFromLink = nil })) { item in
            DuelJoinSheet(initialCode: item.code)
        }
        .alert(String(localized: "duel.createFailed"), isPresented: $createFailed) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        }
    }

    private func actionButton(_ icon: String, _ label: LocalizedStringKey, primary: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(label).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(NeonButtonStyle(prominent: primary))
    }

    /// Un état vide qui montre le duel avant de le décrire : deux joueurs face à face, une
    /// question qui pique, et la règle en une phrase. Le bouton juste dessous fait le reste.
    private var emptyState: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                duelist(icon: "person.fill", filled: true)
                Text(verbatim: "VS")
                    .font(Theme.hero(18))
                    .foregroundStyle(Theme.textMuted)
                duelist(icon: "questionmark", filled: false)
            }
            Text("duel.emptyTitle")
                .font(Theme.display(19))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("social.duelsEmpty")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func duelist(icon: String, filled: Bool) -> some View {
        ZStack {
            if filled {
                Circle().fill(Theme.accentGradient)
            } else {
                Circle().fill(Theme.surfaceRaised)
                Circle().strokeBorder(Theme.neutralAccent.opacity(0.6),
                                      style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
            }
            Image(systemName: icon)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(filled ? Theme.textPrimary : Theme.neutralAccent)
        }
        .frame(width: 54, height: 54)
    }

    private struct ShareCode: Identifiable {
        let code: String
        var id: String { code }
    }
}

/// Un duel : les deux joueurs face à face, le rapport de force, qui mène et de combien, et
/// le temps qui reste — ou le résultat.
private struct DuelRow: View {
    let duel: DuelStore.Duel

    private var diff: Int { duel.my_points - duel.their_points }
    private var leading: Bool { duel.joined && !duel.finished && diff > 0 }

    var body: some View {
        VStack(spacing: 10) {
            if duel.joined {
                faceOff
                balanceBar
                footer
            } else {
                waitingLine
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(leading ? Theme.accent.opacity(0.45) : Theme.stroke, lineWidth: 1))
        .opacity(duel.finished ? 0.75 : 1)
    }

    private var opponentName: String {
        duel.opponent.map { "@\($0)" } ?? String(localized: "social.anonymous")
    }

    private var faceOff: some View {
        HStack(alignment: .center, spacing: 8) {
            side(name: String(localized: "social.you"), points: duel.my_points,
                 color: Theme.accentBright, trailing: false)
            Text(verbatim: "VS")
                .font(Theme.label(10)).tracking(1.5)
                .foregroundStyle(Theme.textMuted)
            side(name: opponentName, points: duel.their_points,
                 color: Theme.neutralAccent, trailing: true)
        }
    }

    private func side(name: String, points: Int, color: Color, trailing: Bool) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
            Text(name)
                .font(Theme.mono(11, .semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(points.formatted())
                .font(Theme.hero(24))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(points)))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }

    /// Rapport de force du duel : la part du joueur en violet, celle de l'adversaire en
    /// cyan. Un score se lit ; une barre se voit.
    private var balanceBar: some View {
        let total = duel.my_points + duel.their_points
        let mine = total > 0 ? Double(duel.my_points) / Double(total) : 0.5
        return GeometryReader { geo in
            HStack(spacing: 2) {
                Capsule().fill(Theme.accentGradient)
                    .frame(width: max(4, (geo.size.width - 2) * mine))
                Capsule().fill(Theme.neutralAccent.opacity(0.7))
            }
        }
        .frame(height: 5)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(standing)
                .font(Theme.mono(10, .bold))
                .foregroundStyle(standingColor)
                .lineLimit(1)
            Spacer(minLength: 6)
            if !duel.finished, let ends = duel.endsAt {
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.system(size: 8, weight: .bold))
                    Text("duel.endsIn \(ends.formatted(.relative(presentation: .numeric)))")
                        .font(Theme.mono(9))
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.textMuted)
            }
        }
    }

    /// Qui mène, et de combien : c'est la phrase qui donne envie de ressortir chasser.
    private var standing: String {
        switch duel.outcome {
        case .won: return String(localized: "duel.won")
        case .lost: return String(localized: "duel.lost")
        case .draw: return String(localized: "duel.draw")
        case nil:
            if diff > 0 { return String(localized: "duel.lead \(diff)") }
            if diff < 0 { return String(localized: "duel.behind \(-diff)") }
            return String(localized: "duel.tied")
        }
    }

    private var standingColor: Color {
        switch duel.outcome {
        case .won: return RarityTier.trophyGold
        case .lost, .draw: return Theme.textMuted
        case nil: return diff > 0 ? Theme.accentBright : diff < 0 ? Theme.warning : Theme.textSecondary
        }
    }

    /// Défi lancé, personne encore en face : le code, et de quoi le renvoyer d'un geste.
    private var waitingLine: some View {
        HStack(spacing: 11) {
            Image(systemName: "hourglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.neutralAccent)
                .frame(width: 34, height: 34)
                .background(Theme.neutralAccent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("duel.waiting")
                    .font(Theme.mono(12, .bold))
                    .foregroundStyle(Theme.textPrimary)
                if let code = duel.code {
                    Text("duel.code \(code)")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                }
                Text("duel.shareHint")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if let code = duel.code {
                ShareLink(item: DuelStore.shareText(code)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(Theme.surface, in: Circle())
                }
            }
        }
    }
}

/// Saisie d'un code de duel, ou confirmation d'un lien reçu.
struct DuelJoinSheet: View {
    let initialCode: String
    @Environment(DuelStore.self) private var duels
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var result: DuelStore.JoinResult?
    @State private var busy = false
    @FocusState private var typing: Bool

    private var valid: Bool { code.range(of: "^[A-Z0-9]{6}$", options: .regularExpression) != nil }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("duel.joinWhy")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField(text: $code) { Text("duel.placeholder") }
                    .focused($typing)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(Theme.mono(22, .bold)).tracking(6)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16).padding(.vertical, 16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(typing ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1))
                    .onChange(of: code) { _, typed in
                        let cleaned = String(typed.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                        if cleaned != typed { code = cleaned }
                        result = nil
                    }
                if let message {
                    Text(message)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.warning)
                }
                Spacer()
                Button { Task { await join() } } label: {
                    Text("duel.join")
                        .font(Theme.label(13)).tracking(1.2)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accentGradient,
                                    in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!valid || busy)
                .opacity(valid ? 1 : 0.45)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
            .background(Theme.background)
            .navigationTitle(Text("social.duels"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Text("common.close") }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            code = initialCode
            typing = initialCode.isEmpty
        }
    }

    private var message: LocalizedStringKey? {
        switch result {
        case .unknown: "duel.error.unknown"
        case .own: "duel.error.own"
        case .taken: "duel.error.taken"
        case .failed: "duel.error.failed"
        default: nil
        }
    }

    private func join() async {
        busy = true
        result = await duels.join(code)
        busy = false
        if result == .ok { dismiss() }
    }
}
