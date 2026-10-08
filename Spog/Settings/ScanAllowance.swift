import Foundation

/// Quotas du joueur gratuit, tels que l'app les affiche.
///
/// Le serveur en est l'autorité (`allowance_left`, voir backend/functions/identify/handler.ts) :
/// 10 scans le premier jour, puis 3 par jour, et 1 rendu par jour. L'app n'en garde qu'un
/// miroir, pour afficher ce qui reste et présenter Pro *avant* que le joueur photographie
/// une voiture pour rien. Le miroir peut se tromper (autre appareil, réinstallation) : le
/// serveur tranche alors, et le miroir se recale sur sa réponse.
enum DailyAllowance {

    static let firstDayScans = 10
    static let dailyScans = 3
    static let dailyDevelops = 1

    /// Scans restants aujourd'hui. Nil pour un abonné, qui n'a pas de quota.
    /// - Parameters:
    ///   - serverLeft: dernier décompte du serveur, et l'heure à laquelle il expire.
    ///   - everScanned: le joueur a-t-il déjà fait un scan ? Sans décompte du serveur,
    ///     c'est ce qui distingue le premier jour (10) des suivants (3).
    static func scansLeft(serverLeft: Int?, resetsAt: Date?, now: Date = Date(),
                          everScanned: Bool, hasAccess: Bool) -> Int? {
        guard !hasAccess else { return nil }
        if let serverLeft, let resetsAt, now < resetsAt { return max(0, serverLeft) }
        // Le décompte connu est périmé : un nouveau jour a commencé.
        if resetsAt != nil { return dailyScans }
        return everScanned ? dailyScans : firstDayScans
    }

    /// Faut-il présenter Pro avant même la photo ?
    static func mustWait(serverLeft: Int?, resetsAt: Date?, now: Date = Date(),
                         everScanned: Bool, hasAccess: Bool) -> Bool {
        scansLeft(serverLeft: serverLeft, resetsAt: resetsAt, now: now,
                  everScanned: everScanned, hasAccess: hasAccess) == 0
    }
}
