import Foundation
import Observation

/// Accord du joueur pour confier ses photos à l'entraînement du classifieur embarqué
/// (REFONTE.md, phase 3).
///
/// Désactivé tant que le joueur n'a pas dit oui : un accord par défaut ne vaut rien,
/// ni pour le RGPD ni pour la règle 5.1.2 de l'App Store. La question n'est posée
/// qu'une fois, après la première carte — quand le joueur a vu ce qu'il aide à faire —,
/// et le réglage reste modifiable ensuite.
@Observable
final class TrainingConsent {

    var granted: Bool {
        didSet {
            UserDefaults.standard.set(granted, forKey: Keys.granted)
            // Retirer son accord efface tout ce qui a déjà été confié, pas seulement la suite.
            if oldValue && !granted { Task { await IdentifyService.forgetTrainingSamples() } }
        }
    }

    /// La question a-t-elle déjà été posée ?
    private(set) var asked: Bool {
        didSet { UserDefaults.standard.set(asked, forKey: Keys.asked) }
    }

    private enum Keys {
        static let granted = "training.granted"
        static let asked = "training.asked"
    }

    init() {
        granted = UserDefaults.standard.bool(forKey: Keys.granted)
        asked = UserDefaults.standard.bool(forKey: Keys.asked)
    }

    func answer(_ accepted: Bool) {
        asked = true
        granted = accepted
    }
}
