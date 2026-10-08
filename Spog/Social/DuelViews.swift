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
        NeonFrame(radius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Overline(text: "social.duels")
                if duels.duels.isEmpty {
                    Text("social.duelsEmpty")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
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
            .padding(14)
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
                Text(label).font(Theme.label(11)).tracking(0.8).lineLimit(1)
            }
            .foregroundStyle(primary ? Theme.background : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                if primary {
                    Capsule().fill(LinearGradient(colors: [Theme.accentBright, Theme.accent],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    Capsule().fill(Theme.surfaceRaised)
                }
            }
        }
        .buttonStyle(.plain)
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
                    .font(Theme.mono(14, .bold))
                    .foregroundStyle(duel.my_points >= duel.their_points ? Theme.accentBright : Theme.textSecondary)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 10)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
