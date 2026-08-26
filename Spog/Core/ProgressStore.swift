import Foundation

/// Niveaux et experience. Une seule source de verite pour toute l'app.
enum Progression {
    private static func threshold(_ level: Int) -> Int { Int(pow(Double(level - 1), 2) * 60) }

    static func level(for points: Int) -> Int { 1 + Int((Double(points) / 60).squareRoot()) }

    static func progress(for points: Int) -> Double {
        let level = level(for: points)
        let floorPoints = threshold(level), nextPoints = threshold(level + 1)
        guard nextPoints > floorPoints else { return 0 }
        return min(1, Double(points - floorPoints) / Double(nextPoints - floorPoints))
    }

    static func toNextLevel(for points: Int) -> Int {
        max(0, threshold(level(for: points) + 1) - points)
    }
}

/// Series, quetes accomplies et points bonus. Persiste dans les reglages de l'app :
/// les donnees sont minuscules, un fichier serait de la ceremonie inutile.
@Observable
final class ProgressStore {

    private(set) var streak: Int = 0
    private(set) var bestStreak: Int = 0
    private(set) var lastCatchDay: Date?
    private(set) var completedQuests: Set<String> = []
    private(set) var bonusPoints: Int = 0

    private static let key = "progress.v1"

    init() { load() }

    // MARK: Lecture

    /// La serie n'est vivante que si la derniere prise date d'aujourd'hui ou d'hier.
    var currentStreak: Int {
        guard let last = lastCatchDay else { return 0 }
        let days = Calendar.current.dateComponents([.day],
                                                   from: Calendar.current.startOfDay(for: last),
                                                   to: Calendar.current.startOfDay(for: Date())).day ?? 0
        return days <= 1 ? streak : 0
    }

    /// La prise du jour est-elle deja faite ? Sert a montrer la serie comme acquise.
    var caughtToday: Bool {
        guard let last = lastCatchDay else { return false }
        return Calendar.current.isDateInToday(last)
    }

    func isDone(_ quest: DailyQuest) -> Bool { completedQuests.contains(quest.id) }

    // MARK: Ecriture

    /// A appeler apres chaque prise. Met la serie a jour et valide la quete si elle est remplie.
    /// - Returns: les points bonus gagnes, zero si rien de neuf.
    @discardableResult
    func register(satisfies quest: DailyQuest?, satisfied: Bool) -> Int {
        let today = Calendar.current.startOfDay(for: Date())

        if let last = lastCatchDay {
            let days = Calendar.current.dateComponents([.day],
                                                       from: Calendar.current.startOfDay(for: last),
                                                       to: today).day ?? 0
            if days == 1 { streak += 1 }          // journee consecutive
            else if days > 1 { streak = 1 }       // serie rompue, on repart
        } else {
            streak = 1
        }
        lastCatchDay = today
        bestStreak = max(bestStreak, streak)

        var gained = 0
        if let quest, satisfied, !completedQuests.contains(quest.id) {
            completedQuests.insert(quest.id)
            bonusPoints += quest.reward
            gained = quest.reward
        }
        save()
        return gained
    }

    // MARK: Persistance

    private struct Snapshot: Codable {
        var streak: Int, bestStreak: Int, bonusPoints: Int
        var lastCatchDay: Date?
        var completedQuests: [String]
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        streak = snapshot.streak
        bestStreak = snapshot.bestStreak
        bonusPoints = snapshot.bonusPoints
        lastCatchDay = snapshot.lastCatchDay
        completedQuests = Set(snapshot.completedQuests)
    }

    private func save() {
        let snapshot = Snapshot(streak: streak, bestStreak: bestStreak,
                                bonusPoints: bonusPoints, lastCatchDay: lastCatchDay,
                                completedQuests: Array(completedQuests))
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
