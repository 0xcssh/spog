import SwiftUI
import StoreKit

/// Paywall. Il se présente après les prises offertes, pas avant :
/// personne ne paie pour un jeu dont il n'a pas vu une seule carte.
///
/// Le prix, la durée et les conditions sont affichés **à côté du bouton**,
/// exigence App Store 3.1.2. Les liens légaux aussi.
struct PaywallView: View {
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss

    @State private var document: LegalDocument?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Theme.glow
                .frame(height: 480)
                .frame(maxHeight: .infinity, alignment: .top)
                .offset(y: -140)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Le paywall se declenche sur une action, il doit donc pouvoir se refermer :
                // il bloque le scan, pas le reste de l'app. Apple l'exige aussi.
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Theme.surface))
                            .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 6)

                header
                Spacer(minLength: 14)
                advantages
                Spacer(minLength: 14)
                plans
                callToAction
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $document) { LegalDocumentView(document: $0) }
        .task { await subscriptions.load() }
    }

    private var header: some View {
        VStack(spacing: 16) {
            Image("LogoMark")
                .resizable()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .neonBorder(color: RarityTier.trophyGold, radius: 22,
                            intensity: 0.9, breathing: true)

            Text("paywall.title")
                .font(Theme.display(27))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text("paywall.subtitle")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var advantages: some View {
        VStack(alignment: .leading, spacing: 10) {
            advantage("infinity", "paywall.unlimited")
            advantage("trophy.fill", "paywall.quests")
            advantage("sparkles", "paywall.cards")
        }
    }

    private func advantage(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RarityTier.trophyGold)
                .frame(width: 24)
            Text(text)
                .font(Theme.display(14, .medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Les deux formules, l'annuelle mise en avant. Elles s'affichent **toujours**,
    /// meme quand StoreKit n'a pas rendu les produits : un paywall vide ne dit rien
    /// au joueur, et le cas arrive pour de vrai (reseau coupe, Store injoignable).
    /// Seul le prix manque alors, et il n'est jamais inventé.
    private var plans: some View {
        VStack(spacing: 9) {
            planCard(subscriptions.yearly, plan: .yearly,
                     badge: subscriptions.yearlySaving.map { "-\($0) %" })
            planCard(subscriptions.monthly, plan: .monthly, badge: nil)

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
                .padding(.top, 2)
            }
        }
        .padding(.bottom, 14)
    }

    private func planCard(_ product: Product?, plan: SubscriptionStore.Plan,
                          badge: String?) -> some View {
        let selected = subscriptions.selected == plan
        let gold = RarityTier.trophyGold
        return Button {
            @Bindable var store = subscriptions
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                store.selected = plan
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(selected ? gold : Theme.textMuted)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(plan == .yearly ? "paywall.plan.yearly" : "paywall.plan.monthly")
                            .font(Theme.display(15, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let badge {
                            Text(verbatim: badge)
                                .font(Theme.label(9)).tracking(0.6)
                                .foregroundStyle(Theme.background)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(gold, in: Capsule())
                        }
                    }
                    // Pour l'annuel, on affiche l'equivalent mensuel :
                    // c'est la seule comparaison honnete entre deux durees.
                    if let product, let perMonth = subscriptions.monthlyEquivalent(for: product) {
                        Text("paywall.perMonth \(perMonth)")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                Spacer(minLength: 6)
                Text(product?.displayPrice ?? "—")
                    .font(Theme.mono(15, .bold))
                    .foregroundStyle(selected ? gold : Theme.textSecondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .background(selected ? gold.opacity(0.10) : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? gold.opacity(0.7) : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var callToAction: some View {
        VStack(spacing: 12) {
            Button {
                Task { if await subscriptions.purchase() { dismiss() } }
            } label: {
                Text(subscriptions.isWorking ? "paywall.working" : buttonTitle)
                    .font(Theme.label(13)).tracking(1.2)
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(
                        LinearGradient(colors: [Theme.accentBright, Theme.accent],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(subscriptions.isWorking || subscriptions.product == nil)

            // Prix et conditions de renouvellement, juste sous le bouton : exigence App Store.
            Text(priceLine)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let error = subscriptions.lastError {
                Text(error)
                    .font(Theme.mono(10))
                    .foregroundStyle(Color(hex: 0xF43F9D))
            }

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
            .padding(.top, 2)

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
            .padding(.top, 6)
#endif
        }
    }

    private var buttonTitle: LocalizedStringKey {
        subscriptions.trialDays != nil ? "paywall.startTrial" : "paywall.subscribe"
    }

    private var priceLine: String {
        let price = subscriptions.priceText
        let period = String(localized: subscriptions.selected == .yearly
                            ? "paywall.period.year" : "paywall.period.month")
        if let days = subscriptions.trialDays {
            return String(localized: "paywall.price.trial \(days) \(price) \(period)")
        }
        return String(localized: "paywall.price.plain \(price) \(period)")
    }
}
