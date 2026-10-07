import SwiftUI

/// Choix du pseudo : ce qui apparaît au classement. La forme est vérifiée en direct, et
/// l'unicité par le serveur au moment d'enregistrer — deux joueurs ne portent jamais le
/// même nom, majuscules comprises.
struct PseudoSheet: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var pseudo = ""
    @State private var saving = false
    @State private var result: AccountStore.PseudoResult?
    @FocusState private var typing: Bool

    private var valid: Bool { AccountStore.isValidPseudo(pseudo) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("pseudo.why")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text(verbatim: "@").foregroundStyle(Theme.textMuted)
                    TextField(text: $pseudo) { Text("pseudo.placeholder") }
                        .focused($typing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { Task { await save() } }
                        .foregroundStyle(Theme.textPrimary)
                }
                .font(Theme.mono(20, .bold))
                .padding(.horizontal, 16).padding(.vertical, 16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(typing ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1))
                .onChange(of: pseudo) { _, _ in result = nil }

                feedback
                Spacer()

                Button { Task { await save() } } label: {
                    Group {
                        if saving { ProgressView().tint(Theme.background) }
                        else { Text("pseudo.save").font(Theme.label(13)).tracking(1.2) }
                    }
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(LinearGradient(colors: [Theme.accentBright, Theme.accent],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!valid || saving)
                .opacity(valid ? 1 : 0.45)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(Theme.background)
            .navigationTitle(Text("pseudo.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Text("common.close") }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            pseudo = account.profile?.pseudo ?? ""
            typing = true
        }
    }

    @ViewBuilder private var feedback: some View {
        let message: LocalizedStringKey? = switch result {
        case .taken: "pseudo.taken"
        case .invalid: "pseudo.rules"
        case .failed: "pseudo.failed"
        default: pseudo.isEmpty || valid ? nil : "pseudo.rules"
        }
        if let message {
            Text(message)
                .font(Theme.mono(11))
                .foregroundStyle(result == .taken || result == .failed ? RarityTier.trophyGold : Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func save() async {
        guard valid, !saving else { return }
        saving = true
        result = await account.setPseudo(pseudo)
        saving = false
        if result == .ok { dismiss() }
    }
}
