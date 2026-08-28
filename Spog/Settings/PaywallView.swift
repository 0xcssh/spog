import SwiftUI
import StoreKit

/// Paywall. Il se présente après les prises offertes, pas avant :
/// personne ne paie pour un jeu dont il n'a pas vu une seule carte.
///
/// Structure : un bandeau de titre, **un panneau d'arguments titrés**, puis les deux
/// formules en boutons distincts plutôt qu'en sélecteur — le prix est lisible sans avoir
/// à choisir d'abord. Le prix, la durée et les conditions de renouvellement figurent
/// **à côté du bouton**, exigence App Store 3.1.2, comme les liens légaux.
struct PaywallView: View {
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss

    @State private var document: LegalDocument?
    @State private var redeeming = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Theme.glow
                .frame(height: 420)
                .frame(maxHeight: .infinity, alignment: .top)
                .offset(y: -160)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    advantages
                        .padding(.top, 26)
                    plans
                        .padding(.top, 22)
                    footer
                        .padding(.top, 18)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $document) { LegalDocumentView(document: $0) }
        .sheet(isPresented: $redeeming) { ReferralEntrySheet() }
        .task { await subscriptions.load() }
    }

    // MARK: Bandeau

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text("paywall.wordmark")
                    .font(Theme.mono(21, .heavy)).tracking(6)
                    .foregroundStyle(RarityTier.trophyGold)
                Text("paywall.subtitle")
                    .font(Theme.label(11)).tracking(2).textCase(.uppercase)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 12)
            // Le paywall se déclenche sur une action : il doit pouvoir se refermer.
            // Il bloque le scan, pas le reste de l'app — et Apple l'exige aussi.
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    // MARK: Arguments

    private struct Advantage {
        let icon: String
        let title: LocalizedStringKey
        let body: LocalizedStringKey
    }

    private let items: [Advantage] = [
        .init(icon: "infinity", title: "paywall.unlimited.title", body: "paywall.unlimited.body"),
        .init(icon: "square.grid.2x2.fill", title: "paywall.dex.title", body: "paywall.dex.body"),
        .init(icon: "trophy.fill", title: "paywall.quests.title", body: "paywall.quests.body"),
        .init(icon: "sparkles", title: "paywall.cards.title", body: "paywall.cards.body"),
        .init(icon: "flame.fill", title: "paywall.share.title", body: "paywall.share.body"),
    ]

    private var advantages: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.stroke)
                        .frame(height: 1)
                        .padding(.leading, 52)
                }
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: item.icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(RarityTier.trophyGold)
                        .frame(width: 24)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(Theme.mono(13, .bold)).tracking(1.6).textCase(.uppercase)
                            .foregroundStyle(Theme.textPrimary)
                        Text(item.body)
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(Theme.strokeStrong, lineWidth: 1))
    }

    // MARK: Formules

    /// Les deux formules en boutons, l'annuelle en second. Chacune porte son prix :
    /// un sélecteur obligerait à choisir avant de savoir combien ça coûte.
    /// Elles s'affichent **toujours**, même quand StoreKit n'a rendu aucun produit —
    /// le cas arrive en production, Store injoignable. Seul le prix manque alors,
    /// et il n'est jamais inventé.
    private var plans: some View {
        VStack(spacing: 11) {
            Text("paywall.cancelAnytime")
                .font(Theme.label(10)).tracking(2).textCase(.uppercase)
                .foregroundStyle(Theme.textMuted)
                .frame(maxWidth: .infinity)

            planButton(.monthly, product: subscriptions.monthly, prominent: true)
            planButton(.yearly, product: subscriptions.yearly, prominent: false)

            if subscriptions.monthly == nil && subscriptions.yearly == nil {
                HStack(spacing: 8) {
                    Text("paywall.pricesUnavailable")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textMuted)
                    Button { Task { await subscriptions.load() } } label: {
                        Text("paywall.retry")
                            .font(Theme.label(10)).tracking(0.6)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }

            if let error = subscriptions.lastError {
                Text(error)
                    .font(Theme.mono(10))
                    .foregroundStyle(Color(hex: 0xF43F9D))
                    .frame(maxWidth: .infinity)
            }

            // Le code de parrainage se saisit aussi d'ici : c'est le moment où quelqu'un
            // se souvient qu'un ami lui en a donné un.
            Button { redeeming = true } label: {
                HStack(spacing: 6) {
                    Text("paywall.haveCode")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textSecondary)
                    Text("paywall.redeem")
                        .font(Theme.label(11)).tracking(1.2)
                        .foregroundStyle(Theme.accentBright)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accentBright)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            }
            .buttonStyle(.plain)
        }
    }

    private func planButton(_ plan: SubscriptionStore.Plan, product: Product?,
                            prominent: Bool) -> some View {
        let price = product?.displayPrice ?? "—"
        let period = String(localized: plan == .yearly ? "paywall.perYear" : "paywall.perMonth")
        let saving = plan == .yearly ? subscriptions.yearlySaving : nil

        return Button {
            @Bindable var store = subscriptions
            store.selected = plan
            Task { if await subscriptions.purchase() { dismiss() } }
        } label: {
            HStack(spacing: 9) {
                Spacer(minLength: 0)
                Text(plan == .yearly ? "paywall.plan.yearly" : "paywall.plan.monthly")
                    .font(Theme.mono(13, .bold)).tracking(1.6).textCase(.uppercase)
                Text(verbatim: "·")
                Text(verbatim: "\(price)\(period)")
                    .font(Theme.mono(13, .bold))
                if let saving {
                    Text(verbatim: "·")
                    Text("paywall.save \(saving)")
                        .font(Theme.mono(11, .bold)).tracking(1)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(prominent ? Theme.background : Theme.textPrimary)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background {
                if prominent {
                    Capsule().fill(LinearGradient(colors: [Theme.accentBright, Theme.accent],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    Capsule().fill(Theme.surface)
                        .overlay(Capsule().stroke(Theme.strokeStrong, lineWidth: 1))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(subscriptions.isWorking || product == nil)
        .opacity(product == nil ? 0.45 : 1)
    }

    // MARK: Pied

    private var footer: some View {
        VStack(spacing: 14) {
            Text(priceLine)
                .font(Theme.mono(9))
                .foregroundStyle(Theme.textMuted.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                Button { Task { await subscriptions.restore() } } label: {
                    Text("settings.restore").font(Theme.label(10)).tracking(0.6)
                }
                Button { document = .terms } label: {
                    Text("legal.terms.title").font(Theme.label(10)).tracking(0.6)
                }
                Button { document = .privacy } label: {
                    Text("legal.privacy.title").font(Theme.label(10)).tracking(0.6)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textMuted)

#if DEBUG
            // Contournement de test. Volontairement enfermé dans #if DEBUG plutôt que
            // laissé à retirer à la main avant soumission : un oubli donnerait l'app
            // entière gratuitement. Ici, la version App Store ne peut pas le contenir.
            Button {
                subscriptions.enableDebugBypass()
                dismiss()
            } label: {
                Text(verbatim: "Passer — test, pas d'abonnement")
                    .font(Theme.label(10))
                    .foregroundStyle(Theme.textMuted.opacity(0.6))
            }
            .buttonStyle(.plain)
#endif
        }
        .frame(maxWidth: .infinity)
    }

    /// Mention de renouvellement. Elle nomme la formule mise en avant — celle du bouton
    /// principal — et l'essai quand Apple en déclare un.
    private var priceLine: String {
        let price = subscriptions.monthly?.displayPrice ?? "—"
        let yearly = subscriptions.yearly?.displayPrice ?? "—"
        if let days = subscriptions.trialDays {
            return String(localized: "paywall.legal.trial \(days) \(price) \(yearly)")
        }
        return String(localized: "paywall.legal.plain \(price) \(yearly)")
    }
}
