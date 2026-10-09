import SwiftUI
import UIKit

extension CardData {
    /// Une carte passe en studio une fois, et seulement si elle porte une vraie photo : une
    /// carte de démonstration n'a rien à y passer, et un rendu ne se regénère jamais.
    var canGoToStudio: Bool { shot != nil && shot?.developed == nil }

    /// La carte telle qu'on la montre pendant le passage en studio : l'image intermédiaire
    /// à la place du rendu. Une copie d'affichage seulement — la carte de l'écran garde
    /// `canGoToStudio`, sinon le bouton disparaîtrait à la première image.
    func showingStudioPreview(_ preview: UIImage?) -> CardData {
        guard let preview, var shot = shot else { return self }
        var copy = self
        shot.developed = preview
        copy.shot = shot
        return copy
    }
}

/// « Passer en studio » : le bouton, le quota du jour, l'attente, le quota épuisé et l'échec,
/// en un seul endroit. Il vit à deux endroits — la fiche d'une carte et la révélation juste
/// après la prise — et la règle d'argent ne doit pas pouvoir diverger entre les deux.
///
/// La carte affichée appartient à l'écran parent : c'est lui qui la remplace par le rendu
/// (`onDeveloped`), chacun avec sa mise en scène, lui qui pose le voile pendant l'attente
/// (`working`) et lui qui montre les images intermédiaires (`preview`, remis à nil à la fin,
/// après `onDeveloped`).
struct StudioButton: View {
    let card: CardData
    @Binding var working: Bool
    @Binding var preview: UIImage?
    /// Pour les statistiques : d'où le rendu a été demandé (`detail`, `reveal`).
    let source: String
    var onDeveloped: (CardData) -> Void

    @Environment(AppState.self) private var app
    @Environment(GarageStore.self) private var garage
    @Environment(SubscriptionStore.self) private var subscriptions
    @State private var limitReached = false
    @State private var failed = false
    @State private var showingPaywall = false

    /// Rendus restants aujourd'hui selon le dernier décompte du serveur ; nil pour Pro.
    private var left: Int? {
        DailyAllowance.developsLeft(serverLeft: app.developsLeftToday, resetsAt: app.developsResetAt,
                                    hasAccess: subscriptions.hasAccess)
    }

    var body: some View {
        VStack(spacing: 6) {
            Button { Task { await develop() } } label: {
                HStack(spacing: 8) {
                    if working {
                        ProgressView().controlSize(.small).tint(Theme.textPrimary)
                    } else {
                        Image(systemName: "sparkles").font(.system(size: 13, weight: .bold))
                    }
                    Text(working ? "card.developing" : "card.develop")
                }
            }
            .buttonStyle(NeonButtonStyle(prominent: false))
            .disabled(working)
            .opacity(working ? 0.6 : 1)

            caption
        }
        .alert(String(localized: "develop.limit.title"), isPresented: $limitReached) {
            Button(String(localized: "develop.limit.pro")) {
                showingPaywall = true
                Analytics.track(.paywallShown, ["from": "studio"])
            }
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text("develop.limit.message")
        }
        .fullScreenCover(isPresented: $showingPaywall) { PaywallView() }
    }

    /// Une ligne discrète sous le bouton : l'échec s'il y en a eu un (pas d'alerte, rien n'a
    /// été décompté), sinon ce qu'il reste aujourd'hui. Rien pour un abonné.
    @ViewBuilder
    private var caption: some View {
        if failed {
            Text("develop.failed")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        } else if !working, let left {
            // Le gratuit n'a qu'un rendu par jour (`DailyAllowance.dailyDevelops`) : le
            // décompte ne montre donc que 1 ou « déjà utilisé », d'où une clé sans pluriel.
            Group {
                if left > 0 { Text("studio.freeToday \(left)") } else { Text("develop.limit.title") }
            }
            .font(Theme.mono(10))
            .foregroundStyle(Theme.textMuted)
        }
    }

    /// Envoie la photo du joueur au serveur et range le rendu studio sur l'appareil : il ne
    /// se regénère jamais.
    @MainActor
    private func develop() async {
        guard let original = card.shot?.original, !working else { return }
        failed = false
        withAnimation { working = true }
        let result = await DevelopService.develop(original, entitlement: subscriptions.entitlementJWS) { partial in
            // La carte se forme sous les yeux du joueur : chaque image remplace la
            // précédente en fondu, de plus en plus nette.
            withAnimation(.easeInOut(duration: 0.6)) { preview = partial }
        }
        withAnimation { working = false }
        // L'aperçu s'efface après la carte définitive (succès) ou tout de suite (échec) :
        // jamais de retour fugitif à la photo entre la dernière image et le rendu.
        defer { withAnimation(.easeInOut(duration: 0.3)) { preview = nil } }
        switch result {
        case .success(let developed):
            ShotStore.saveDeveloped(developed.image, for: card.id)
            // Nil : pas de quota (Pro, ou installation de test côté serveur). Le miroir
            // suit, sinon un « 0 » d'avant continuerait d'afficher « déjà utilisé ».
            app.developsLeftToday = developed.left
            app.developsResetAt = developed.resetsAt
            // Le retour haptique part d'ici et non d'un `sensoryFeedback` : le bouton
            // disparaît dès que la carte a son rendu, et emporterait le déclencheur avec lui.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Analytics.track(.cardDeveloped, ["tier": card.tier.id, "from": source])
            if let item = garage.catches.first(where: { $0.id == card.id }),
               let refreshed = garage.card(item) {
                onDeveloped(refreshed)
            }
        case .failure(.limit(let resetsAt)):
            app.developsLeftToday = 0
            app.developsResetAt = resetsAt
            limitReached = true
        case .failure(.failed):
            withAnimation { failed = true }
        }
    }
}

/// Voile posé sur la carte pendant le passage en studio : un tirage qui apparaît
/// lentement, plutôt qu'une roue qui tourne. La génération prend quelques secondes.
struct DevelopingVeil: View {
    @State private var phase = false

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Theme.background.opacity(phase ? 0.25 : 0.6))
            .overlay {
                LinearGradient(colors: [.clear, Theme.highlight.opacity(0.18), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
                    .offset(y: phase ? 160 : -160)
                    .blendMode(.screen)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { phase = true }
            }
    }
}
