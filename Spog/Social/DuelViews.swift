import SwiftUI

/// Les duels, dans l'onglet Social : les défis en cours avec leur score, et de quoi en
/// lancer un nouveau ou en rejoindre un.
struct DuelsBlock: View {
    @Environment(DuelStore.self) private var duels
    @State private var shareCode: String?
    @State private var joining = false
    @State private var creating = false
    @State private var createFailed = false

    var body: some View {
        GlassCard(radius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "figure.fencing")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accentBright)
                    Overline(text: "social.duels", color: Theme.accentBright)
                }
                if duels.duels.isEmpty {
                    // Un état vide qui montre le duel avant de le décrire : deux joueurs
                    // face à face, et la règle en une phrase.
                    HStack(spacing: 14) {
                        versusBadge
                        Text("social.duelsEmpty")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(duels.duels) { duel in DuelRow(duel: duel) }
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

    /// Deux pastilles qui se font face : le duel en image.
    private var versusBadge: some View {
        HStack(spacing: -10) {
            Circle().fill(Theme.accentGradient)
                .frame(width: 34, height: 34)
                .overlay(Image(systemName: "person.fill").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.background))
            Circle().fill(Theme.surfaceRaised)
                .frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(Theme.cyan.opacity(0.6), lineWidth: 1.2))
                .overlay(Image(systemName: "questionmark").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.cyan))
        }
    }

    private struct ShareCode: Identifiable {
        let code: String
        var id: String { code }
    }
}

/// Un duel : l'adversaire, les deux scores, et le temps qui reste — ou le résultat.
private struct DuelRow: View {
    let duel: DuelStore.Duel

    var body: some View {
        VStack(spacing: 9) {
            scoreLine
            if duel.joined { balanceBar }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private var scoreLine: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                if duel.joined {
                    Text(duel.opponent.map { "@\($0)" } ?? String(localized: "social.anonymous"))
                        .font(Theme.mono(12, .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                } else {
                    Text("duel.waiting")
                        .font(Theme.mono(12, .bold))
                        .foregroundStyle(Theme.textSecondary)
                    if let code = duel.code {
                        Text("duel.code \(code)")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.accentBright)
                            .textSelection(.enabled)
                    }
                }
                Text(subtitle)
                    .font(Theme.mono(9))
                    .foregroundStyle(subtitleColor)
            }
            Spacer(minLength: 6)
            if duel.joined {
                Text(verbatim: "\(duel.my_points.formatted()) – \(duel.their_points.formatted())")
                    .font(Theme.hero(17))
                    .monospacedDigit()
                    .foregroundStyle(duel.my_points >= duel.their_points ? Theme.accentBright : Theme.textSecondary)
            }
        }
    }

    /// Rapport de force du duel : la part du joueur en violet, celle de l'adversaire en
    /// cyan. Un score « 120 – 95 » se lit ; une barre se voit.
    private var balanceBar: some View {
        let total = duel.my_points + duel.their_points
        let mine = total > 0 ? Double(duel.my_points) / Double(total) : 0.5
        return GeometryReader { geo in
            HStack(spacing: 2) {
                Capsule().fill(Theme.accentGradient)
                    .frame(width: max(4, (geo.size.width - 2) * mine))
                Capsule().fill(Theme.cyan.opacity(0.7))
            }
        }
        .frame(height: 3)
    }

    private var subtitle: String {
        switch duel.outcome {
        case .won: return String(localized: "duel.won")
        case .lost: return String(localized: "duel.lost")
        case .draw: return String(localized: "duel.draw")
        case nil:
            if let ends = duel.endsAt {
                return String(localized: "duel.endsIn \(ends.formatted(.relative(presentation: .numeric)))")
            }
            return String(localized: "duel.shareHint")
        }
    }

    private var subtitleColor: Color {
        switch duel.outcome {
        case .won: return RarityTier.trophyGold
        case .lost, .draw: return Theme.textMuted
        case nil: return Theme.textMuted
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
                        .foregroundStyle(RarityTier.trophyGold)
                }
                Spacer()
                Button { Task { await join() } } label: {
                    Text("duel.join")
                        .font(Theme.label(13)).tracking(1.2)
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient(colors: [Theme.accentBright, Theme.accent],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
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
