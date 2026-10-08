import Foundation
import Testing
@testable import Spog

/// Le miroir des quotas du jour : ce que l'app affiche et quand elle présente Pro.
///
/// Une erreur d'un cran ici se paie deux fois. Trop généreuse, elle laisse photographier
/// une voiture que le serveur refusera d'identifier — une prise perdue. Trop stricte, elle
/// présente Pro à un joueur qui avait encore droit à un scan, et celui-là ne revient pas.
struct DailyAllowanceTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Un nouveau joueur a dix scans le premier jour")
    func firstDayGetsTen() {
        #expect(DailyAllowance.scansLeft(serverLeft: nil, resetsAt: nil, now: now,
                                         everScanned: false, hasAccess: false) == 10)
    }

    @Test("Sans décompte du serveur, un joueur qui a déjà scanné en a trois")
    func laterDaysGetThree() {
        #expect(DailyAllowance.scansLeft(serverLeft: nil, resetsAt: nil, now: now,
                                         everScanned: true, hasAccess: false) == 3)
    }

    @Test("Le décompte du serveur fait foi tant qu'il n'a pas expiré")
    func serverCountWins() {
        let later = now.addingTimeInterval(3_600)
        #expect(DailyAllowance.scansLeft(serverLeft: 1, resetsAt: later, now: now,
                                         everScanned: true, hasAccess: false) == 1)
        #expect(DailyAllowance.mustWait(serverLeft: 0, resetsAt: later, now: now,
                                        everScanned: true, hasAccess: false))
    }

    @Test("À minuit, un décompte épuisé redonne trois scans")
    func newDayResets() {
        let past = now.addingTimeInterval(-1)
        #expect(DailyAllowance.scansLeft(serverLeft: 0, resetsAt: past, now: now,
                                         everScanned: true, hasAccess: false) == 3)
        #expect(!DailyAllowance.mustWait(serverLeft: 0, resetsAt: past, now: now,
                                         everScanned: true, hasAccess: false))
    }

    @Test("Un abonné n'a pas de quota")
    func subscriberHasNoLimit() {
        #expect(DailyAllowance.scansLeft(serverLeft: 0, resetsAt: now.addingTimeInterval(60), now: now,
                                         everScanned: true, hasAccess: true) == nil)
        #expect(!DailyAllowance.mustWait(serverLeft: 0, resetsAt: now.addingTimeInterval(60), now: now,
                                         everScanned: true, hasAccess: true))
    }

    @Test("Un décompte négatif venu d'une ancienne version ne s'affiche jamais")
    func neverNegative() {
        #expect(DailyAllowance.scansLeft(serverLeft: -2, resetsAt: now.addingTimeInterval(60), now: now,
                                         everScanned: true, hasAccess: false) == 0)
    }

    @Test("Le rendu studio du jour : un par défaut, le serveur fait foi, minuit le rend")
    func studioAllowance() {
        let later = now.addingTimeInterval(3_600), past = now.addingTimeInterval(-1)
        #expect(DailyAllowance.developsLeft(serverLeft: nil, resetsAt: nil, now: now, hasAccess: false) == 1)
        #expect(DailyAllowance.developsLeft(serverLeft: 0, resetsAt: later, now: now, hasAccess: false) == 0)
        #expect(DailyAllowance.developsLeft(serverLeft: 0, resetsAt: past, now: now, hasAccess: false) == 1)
        #expect(DailyAllowance.developsLeft(serverLeft: 0, resetsAt: later, now: now, hasAccess: true) == nil)
    }

    @Test("Les quotas annoncés sont ceux du serveur")
    func matchesServer() {
        // FREE_ALLOWANCE dans backend/functions/identify/handler.ts : les deux listes
        // vivent dans deux fichiers que rien d'autre ne relie.
        #expect(DailyAllowance.firstDayScans == 10)
        #expect(DailyAllowance.dailyScans == 3)
        #expect(DailyAllowance.dailyDevelops == 1)
    }
}
