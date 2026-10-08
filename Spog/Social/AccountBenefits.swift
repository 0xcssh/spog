import SwiftUI
import AuthenticationServices

/// Ce que la connexion Apple apporte, dit en bénéfices concrets.
///
/// Partagé par l'onboarding et l'onglet Social : un simple bouton « Se connecter » ne
/// disait pas pourquoi le faire, et presque personne ne touche un bouton dont il ne voit
/// pas l'intérêt. Les quatre lignes décrivent ce que le serveur fait vraiment d'un compte
/// relié (`apple_link` rattache prises, pseudo, ligue et duels au compte Apple) — rien
/// qu'il ne tienne pas.
struct AccountBenefitsList: View {
    /// Faux sur petit écran : les titres seuls, le détail prendrait la place du bouton.
    var showsDetails: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: showsDetails ? 13 : 10) {
            row("icloud.fill", "account.benefit.backup.title", "account.benefit.backup.body")
            row("at", "account.benefit.pseudo.title", "account.benefit.pseudo.body")
            row("trophy.fill", "account.benefit.league.title", "account.benefit.league.body")
            row("flag.checkered", "account.benefit.first.title", "account.benefit.first.body")
        }
    }

    private func row(_ icon: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: showsDetails ? .top : .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 32, height: 32)
                .background(Theme.surfaceRaised, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.display(15, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if showsDetails {
                    Text(detail)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// La phrase qui rassure, sous le bouton : c'est la crainte qui fait renoncer (un e-mail
/// de plus, un mot de passe de plus), elle doit être levée là où le doigt hésite.
struct AccountPrivacyNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
                .padding(.top, 1)
            Text("account.privacy")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// Bouton Sign in with Apple relié à `AccountStore.linkApple`.
///
/// Un seul endroit traite la réponse d'Apple, pour que l'onboarding et l'onglet Social ne
/// divergent pas : aucune donnée demandée (`requestedScopes` vide, ni nom ni e-mail), et
/// une annulation par le joueur n'est jamais une erreur — il a changé d'avis, c'est tout.
struct AppleLinkButton: View {
    enum Outcome { case linked, cancelled, failed }

    private let onOutcome: (Outcome) -> Void

    @Environment(AccountStore.self) private var account
    /// Le serveur peut mettre une seconde à répondre : sans retour visible, le joueur
    /// toucherait le bouton une deuxième fois.
    @State private var linking = false

    /// Écrit à la main : avec un `@State` privé, l'initialiseur implicite peut devenir
    /// privé, et les écrans des autres fichiers ne pourraient plus l'appeler.
    init(onOutcome: @escaping (Outcome) -> Void) {
        self.onOutcome = onOutcome
    }

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = []
        } onCompletion: { result in
            switch result {
            case .failure(let error):
                let cancelled = (error as? ASAuthorizationError)?.code == .canceled
                onOutcome(cancelled ? .cancelled : .failed)
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let token = credential.identityToken else {
                    onOutcome(.failed)
                    return
                }
                linking = true
                Task { @MainActor in
                    let linked = await account.linkApple(identityToken: token)
                    linking = false
                    onOutcome(linked ? .linked : .failed)
                }
            }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 50)
        .clipShape(Capsule())
        .disabled(linking)
        .overlay {
            if linking {
                ZStack {
                    Capsule().fill(Theme.background.opacity(0.55))
                    ProgressView().tint(Theme.textPrimary)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: linking)
    }
}
