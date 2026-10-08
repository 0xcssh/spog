import SwiftUI

/// Tableau de bord de l'écran d'accueil : niveau et jauge, puis trois cases (cartes,
/// valeur, série), puis la ligne Spog Pro avec les scans du jour.
///
/// Une seule boîte à filets fins plutôt que trois panneaux de verre : le testeur voulait
/// un vrai garage en arrivant, et l'ancien en-tête empilait compteur géant, valeur,
/// métriques et Spogdex sans hiérarchie. Le violet n'y sert qu'à la jauge de niveau.
struct HomeStatsCard: View {
    var onOpenPro: () -> Void

    @Environment(AppState.self) private var app
    @Environment(GarageStore.self) private var garage
    @Environment(ProgressStore.self) private var progress
    @Environment(SubscriptionStore.self) private var subscriptions
    @State private var explainingValue = false

    private let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    /// Mêmes points que l'écran Quêtes : prises plus bonus de quête. Deux niveaux
    /// différents d'un onglet à l'autre feraient douter des deux.
    private var points: Int { garage.totalPoints + progress.bonusPoints }

    var body: some View {
        VStack(spacing: 0) {
            levelBlock
                .padding(16)
            hairline
            HStack(spacing: 0) {
                cardsCell
                verticalHairline
                valueCell
                verticalHairline
                streakCell
            }
            hairline
            proRow
        }
        .background(Theme.surface, in: shape)
        .overlay(shape.strokeBorder(Theme.stroke, lineWidth: 1))
        .alert(Text("garage.value.title"), isPresented: $explainingValue) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(verbatim: valueExplanation)
        }
    }

    // MARK: Niveau

    private var levelBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Overline(text: "profile.level")
                    Text(verbatim: "\(Progression.level(for: points))")
                        .font(Theme.hero(40))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText(value: Double(points)))
                }
                Spacer()
                Text("home.points \(points)")
                    .font(Theme.mono(12, .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            LevelBar(progress: Progression.progress(for: points))
            HStack {
                Spacer()
                Text("profile.toNext \(Progression.toNextLevel(for: points))")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    // MARK: Cases

    private var cardsCell: some View {
        StatCell(value: garage.cardCount.formatted(), label: "home.stat.cards")
    }

    /// La valeur se touche pour savoir d'où elle vient : une somme de cotes devinées, dans
    /// une seule devise. L'explication ne tient pas dans la case, et elle compte.
    @ViewBuilder private var valueCell: some View {
        if let value = garage.estimatedValue {
            Button { explainingValue = true } label: {
                StatCell(value: PriceFormat.total(value), label: "home.stat.value", icon: "info.circle")
            }
            .buttonStyle(PressScaleStyle(scale: 0.97))
        } else {
            // Aucune carte cotée : un tiret plutôt qu'un « 0 € », qui dirait que la
            // collection ne vaut rien.
            StatCell(value: "—", label: "home.stat.value")
        }
    }

    private var streakCell: some View {
        StatCell(value: String(localized: "home.streak.short \(progress.currentStreak)"),
                 label: "stat.streak",
                 icon: progress.caughtToday ? "checkmark" : nil)
    }

    private var valueExplanation: String {
        var text = String(localized: "garage.value.note")
        if let others = garage.estimatedValue?.otherCurrencies, !others.isEmpty {
            text += "\n\n" + String(localized: "garage.value.others \(others.joined(separator: ", "))")
        }
        return text
    }

    // MARK: Spog Pro

    /// Scans restants du jour, et l'accès à Pro. Le prix n'est montré que si StoreKit l'a
    /// rendu : il n'est jamais inventé.
    @ViewBuilder private var proRow: some View {
        if subscriptions.hasAccess {
            HStack(spacing: 8) {
                proMark
                Spacer()
                Text("home.pro.active")
                    .font(Theme.label(10)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        } else {
            Button(action: onOpenPro) {
                HStack(spacing: 8) {
                    proMark
                    if let left = scansLeft {
                        Text("scan.todayLeft \(left)")
                            .font(Theme.mono(10))
                            .foregroundStyle(left == 0 ? Theme.warning : Theme.textMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if let price = subscriptions.monthly?.displayPrice {
                        Text(verbatim: price + String(localized: "paywall.perMonth"))
                            .font(Theme.mono(11, .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var proMark: some View {
        Text("paywall.wordmark")
            .font(Theme.label(11)).tracking(1.8)
            .foregroundStyle(Theme.textPrimary)
    }

    private var scansLeft: Int? {
        DailyAllowance.scansLeft(serverLeft: app.scansLeftToday, resetsAt: app.scansResetAt,
                                 everScanned: app.scansPerformed > 0,
                                 hasAccess: subscriptions.hasAccess)
    }

    // MARK: Filets

    private var hairline: some View {
        Rectangle().fill(Theme.stroke).frame(height: 1)
    }

    /// Hauteur fixe : un filet souple dans une pile horizontale, elle-même dans une vue
    /// défilante, ne sait pas à quelle hauteur s'arrêter.
    private var verticalHairline: some View {
        Rectangle().fill(Theme.stroke).frame(width: 1, height: 34)
    }
}

/// Une case du tableau de bord : un chiffre en monospace, un libellé en capitales.
private struct StatCell: View {
    let value: String
    let label: LocalizedStringKey
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: value)
                .font(Theme.mono(15, .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 4) {
                Text(label)
                    .font(Theme.label(9)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Jauge de niveau : un trait fin, le seul violet du tableau de bord.
private struct LevelBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceRaised)
                Capsule()
                    .fill(Theme.accent)
                    // Un minimum visible : un niveau tout juste entamé doit se voir.
                    .frame(width: max(progress > 0 ? 4 : 0, geo.size.width * progress))
            }
        }
        .frame(height: 4)
    }
}
