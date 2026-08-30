import Foundation

/// Décompte des prises offertes.
///
/// Cette règle décide seule quand le paywall s'interpose : c'est la frontière entre
/// ce que le joueur obtient gratuitement et ce qu'il paie. Elle vivait dans une
/// propriété calculée de `ScannerView`, où aucun test ne pouvait l'atteindre — pour
/// la règle de l'app qui touche le plus directement à l'argent, c'était l'endroit
/// le moins défendable.
enum ScanAllowance {

    /// Prises restantes avant le paywall. Nil quand l'abonné n'a pas de plafond.
    static func remaining(performed: Int, hasAccess: Bool,
                          free: Int = SubscriptionStore.freeScans) -> Int? {
        guard !hasAccess else { return nil }
        // Le maximum protège d'un compteur qui aurait dépassé le quota — un ancien
        // joueur dont l'abonnement expire ne doit pas voir un nombre négatif.
        return max(0, free - performed)
    }

    /// Le paywall doit-il s'interposer avant cette prise ?
    static func mustPay(performed: Int, hasAccess: Bool,
                        free: Int = SubscriptionStore.freeScans) -> Bool {
        remaining(performed: performed, hasAccess: hasAccess, free: free) == 0
    }
}
