import SwiftUI
import StoreKit

/// Réglages : repérage, abonnement, documents légaux.
/// L'abonnement et la restauration d'achat sont exigés par l'App Store,
/// et la restauration doit fonctionner même sans achat en cours.
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(LocationProvider.self) private var location
    @Environment(TrainingConsent.self) private var training
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var pickingCountry = false
    @State private var document: LegalDocument?
    @State private var restoring = false
    @State private var showingPaywall = false
    @State private var restoreResult: RestoreResult?
    @State private var confirmingDeletion = false
    @State private var deletionFailed = false

    private let store = CatalogStore.shared

    private enum RestoreResult: Identifiable {
        case none, failed
        var id: Int { self == .none ? 0 : 1 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    spotting
                    subscription
                    data
                    legal
                    about
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .background(Theme.background)
            .navigationTitle(Text("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Text("common.close") }
                }
            }
        }
        .preferredColorScheme(.dark)
        // Passer en automatique doit relever la position tout de suite. Sinon le
        // réglage change d'étiquette sans rien changer au pays, ce qui est un mensonge.
        .onChange(of: app.locationMode) { _, mode in
            guard mode == .automatic else { return }
            location.currentCountry { code in
                guard let code else { return }
                @Bindable var state = app
                state.country = code
            }
        }
        .sheet(isPresented: $pickingCountry) { MarketPickerSheet() }
        .sheet(item: $document) { LegalDocumentView(document: $0) }
        .fullScreenCover(isPresented: $showingPaywall) { PaywallView() }
        // Suppression du compte : exigée par l'App Store (5.1.1(v)) dès qu'une app en crée.
        // Le garage local n'est pas touché — il appartient à l'appareil.
        .confirmationDialog(String(localized: "account.delete.title"), isPresented: $confirmingDeletion,
                            titleVisibility: .visible) {
            Button(String(localized: "account.delete.confirm"), role: .destructive) {
                Task { if !(await account.deleteAccount()) { deletionFailed = true } }
            }
        } message: {
            Text("account.delete.message")
        }
        .alert(String(localized: "account.delete.failed"), isPresented: $deletionFailed) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        }
        .alert(item: $restoreResult) { result in
            Alert(title: Text(result == .none ? "settings.restore.none" : "settings.restore.failed"),
                  dismissButton: .default(Text("common.ok")))
        }
    }

    // MARK: Repérage

    private var spotting: some View {
        section("settings.spotting") {
            @Bindable var state = app

            row(icon: "globe", label: "market.title",
                value: store.countryName(app.country)) { pickingCountry = true }

            divider

            // Le mode décide aussi si une prise est vérifiable : ce n'est pas qu'un confort.
            Picker("", selection: $state.locationMode) {
                Text("onboarding.auto.title").tag(AppState.LocationMode.automatic)
                Text("onboarding.manual.title").tag(AppState.LocationMode.manual)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14).padding(.vertical, 10)

            Text(app.locationMode == .automatic ? "settings.mode.auto" : "settings.mode.manual")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.bottom, 12)
        }
    }

    // MARK: Abonnement

    private var subscription: some View {
        section("settings.subscription") {
            row(icon: "crown.fill", label: "settings.plan",
                value: String(localized: subscriptions.isSubscribed ? "settings.plan.premium"
                                                                    : "settings.plan.free"))
            divider
            row(icon: "arrow.up.right.square", label: "settings.manage", value: nil) {
                Task { await openManageSubscriptions() }
            }
            if !subscriptions.isSubscribed {
                divider
                row(icon: "sparkles", label: "settings.subscribe", value: nil) {
                    showingPaywall = true
                }
            }
            divider
            row(icon: "arrow.clockwise", label: "settings.restore",
                value: restoring ? String(localized: "settings.restoring") : nil) {
                Task { await restorePurchases() }
            }
        }
    }

    // MARK: Données

    /// L'accord pour l'entraînement : le désactiver efface les photos déjà confiées
    /// (voir TrainingConsent). Le texte sous l'interrupteur dit ce qu'implique l'état
    /// actuel, pas une généralité.
    private var data: some View {
        section("settings.data") {
            @Bindable var consent = training
            Toggle(isOn: $consent.granted) {
                HStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 22)
                    Text("settings.training")
                        .font(Theme.display(14, .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .tint(Theme.accent)
            .padding(.horizontal, 14).padding(.vertical, 10)

            Text(training.granted ? "settings.training.on" : "settings.training.off")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.bottom, 12)

            divider
            row(icon: "person.crop.circle.badge.xmark", label: "account.delete.row", value: nil) {
                confirmingDeletion = true
            }
        }
    }

    // MARK: Légal

    private var legal: some View {
        section("settings.legal") {
            row(icon: "hand.raised.fill", label: "legal.privacy.title", value: nil) {
                document = .privacy
            }
            divider
            row(icon: "doc.text.fill", label: "legal.terms.title", value: nil) {
                document = .terms
            }
        }
    }

    private var about: some View {
        VStack(spacing: 5) {
            Text(verbatim: "SPOG \(appVersion)")
                .font(Theme.mono(11, .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("settings.publisher")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: Actions

    private func restorePurchases() async {
        restoring = true
        defer { restoring = false }
        do {
            try await AppStore.sync()
            // Aucun abonnement retrouvé tant que StoreKit n'a pas de produit :
            // on le dit clairement plutôt que de laisser l'utilisateur dans le doute.
            restoreResult = .none
        } catch {
            restoreResult = .failed
        }
    }

    private func openManageSubscriptions() async {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
    }

    // MARK: Briques

    private func section<Content: View>(_ title: LocalizedStringKey,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Overline(text: title)
                .padding(.leading, 4)
            NeonFrame(radius: 16) {
                VStack(spacing: 0) { content() }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 46)
    }

    private func row(icon: String, label: LocalizedStringKey, value: String?,
                     action: (() -> Void)? = nil) -> some View {
        Button { action?() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 22)
                Text(label)
                    .font(Theme.display(14, .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                }
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}
