import Foundation
import TelemetryDeck

/// Analytics produit via TelemetryDeck, comme RepLock et Dunk It : des comptes anonymes,
/// aucun identifiant de personne, aucune demande de pistage (ATT).
///
/// Tout passe par ce fichier : le SDK n'est cité qu'ici, et le vocabulaire des événements
/// vit en un seul endroit. Les réponses de confidentialité App Store doivent déclarer
/// « Interaction avec le produit », collectée mais NON liée à l'identité.
enum Analytics {
    /// Identifiant de l'app dans TelemetryDeck (tableau de bord → app → Settings). Comme
    /// une clé publique, il est fait pour être embarqué : il ne permet que d'envoyer.
    /// Tant qu'il commence par REPLACE, rien ne part.
    ///
    /// ⚠️ Le renseigner rend fausse la phrase « aucun outil de mesure tiers » de la
    /// politique de confidentialité (`privacy.collect.body`) : la corriger dans le même
    /// commit, puis relancer `tools/export-legal.py`.
    static let appID = "REPLACE-WITH-TELEMETRYDECK-APP-ID"

    private static var enabled: Bool { !appID.hasPrefix("REPLACE") }

    /// À appeler une fois, le plus tôt possible.
    static func configure() {
        guard enabled else { return }
        TelemetryDeck.initialize(config: TelemetryDeck.Config(appID: appID))
    }

    static func track(_ event: Event, _ parameters: [String: String] = [:]) {
        guard enabled else { return }
        TelemetryDeck.signal(event.rawValue, parameters: parameters)
    }

    /// Le vocabulaire complet. Les noms pointés se regroupent dans le tableau de bord.
    enum Event: String {
        case appLaunched = "App.launched"

        // Tunnel d'onboarding : un signal par écran montré, puis la fin.
        case onboardingStep = "Onboarding.step"              // step
        case onboardingCompleted = "Onboarding.completed"

        // Boucle principale
        case scanStarted = "Scan.started"                    // freeLeft
        case scanIdentified = "Scan.identified"              // confidence, matched: catalog|learned|ask
        case scanFailed = "Scan.failed"                      // reason
        case cardCreated = "Card.created"                    // tier
        case cardShared = "Card.shared"                      // tier
        case cardDeveloped = "Card.developed"                // tier, from: detail|reveal

        // Argent
        case paywallShown = "Paywall.shown"                  // from: scan|settings|garage|server|studio
        case purchaseResult = "Purchase.result"              // plan, result: success|cancelled
        case restoreResult = "Purchase.restore"              // result
    }
}
