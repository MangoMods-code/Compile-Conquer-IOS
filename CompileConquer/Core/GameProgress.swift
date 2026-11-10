import Foundation
import Combine

/// A title earned from total stars, shown on the title screen.
struct Rank {
    let title: String
    let stars: Int
    /// Stars needed for the next rank, or nil at the top.
    let next: Int?

    private static let ladder: [(Int, String)] = [
        (0, "Trainee"), (6, "Operator"), (15, "Technician"), (27, "Engineer"), (40, "Architect"), (54, "Conqueror"),
    ]

    static func forStars(_ s: Int) -> Rank {
        var title = ladder[0].1
        var next: Int? = nil
        for (i, step) in ladder.enumerated() where s >= step.0 {
            title = step.1
            next = i + 1 < ladder.count ? ladder[i + 1].0 : nil
        }
        return Rank(title: title, stars: s, next: next)
    }
}

/// Stars, bonus badges, saved code and saved maps, kept on the device.
final class GameProgress: ObservableObject {
    static let shared = GameProgress()

    @Published private(set) var starMap: [String: Int]
    /// Levels solved within their Tidy line limit.
    @Published private(set) var tidySet: Set<String>
    @Published private(set) var bestTicks: [String: Int]
    private let defaults = UserDefaults.standard

    /// Screenshot/UI tests launch with `-uitest.allStars N` to see every level as cleared.
    private let testStars = UserDefaults.standard.integer(forKey: "uitest.allStars")

    private init() {
        let d = UserDefaults.standard
        starMap = (d.dictionary(forKey: "cc.stars") as? [String: Int]) ?? [:]
        tidySet = Set(d.stringArray(forKey: "cc.tidy") ?? [])
        bestTicks = (d.dictionary(forKey: "cc.best") as? [String: Int]) ?? [:]
    }

    // MARK: Stars

    func stars(for id: String) -> Int { testStars > 0 ? testStars : (starMap[id] ?? 0) }
    func isTidy(_ id: String) -> Bool { tidySet.contains(id) }

    /// Saves a win. Returns true when it beat the level's previous best star count.
    @discardableResult
    func record(stars s: Int, ticks: Int, tidy: Bool, for id: String) -> Bool {
        let improved = s > (starMap[id] ?? 0)
        if improved {
            starMap[id] = s
            defaults.set(starMap, forKey: "cc.stars")
        }
        if ticks < (bestTicks[id] ?? Int.max) {
            bestTicks[id] = ticks
            defaults.set(bestTicks, forKey: "cc.best")
        }
        if tidy, !tidySet.contains(id) {
            tidySet.insert(id)
            defaults.set(Array(tidySet), forKey: "cc.tidy")
        }
        return improved
    }

    func isUnlocked(_ level: LevelSpec, in chapter: [LevelSpec]) -> Bool {
        guard let i = chapter.firstIndex(of: level), i > 0 else { return true }
        return stars(for: chapter[i - 1].id) > 0
    }

    func totalStars(_ chapter: [LevelSpec]) -> Int { chapter.reduce(0) { $0 + stars(for: $1.id) } }

    var allStars: Int { WorldInfo.all.reduce(0) { $0 + totalStars($1.levels) } }
    var rank: Rank { Rank.forStars(allStars) }

    /// Every level in a chapter has at least 1 star.
    func isComplete(_ chapter: [LevelSpec]) -> Bool { !chapter.isEmpty && chapter.allSatisfy { stars(for: $0.id) > 0 } }

    /// Worlds open in order: the first is always open, each next one opens when the previous is finished.
    /// The owner's "Play any campaign" switch opens every built world.
    func isUnlocked(_ world: WorldInfo) -> Bool {
        guard world.available else { return false }
        if AppSettings.shared.playAnyCampaign { return true }
        guard let i = WorldInfo.all.firstIndex(of: world), i > 0 else { return true }
        return isComplete(WorldInfo.all[i - 1].levels)
    }

    /// The first open level that hasn't been beaten yet (for the Continue button).
    func nextLevel() -> LevelSpec? {
        for world in WorldInfo.all where isUnlocked(world) {
            for level in world.levels where isUnlocked(level, in: world.levels) && stars(for: level.id) == 0 {
                return level
            }
        }
        return nil
    }

    /// Clears stars, badges, saved code and saved maps.
    func resetAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("cc.") {
            defaults.removeObject(forKey: key)
        }
        starMap = [:]
        tidySet = []
        bestTicks = [:]
    }

    // MARK: Saved code

    func code(for level: LevelSpec) -> String {
        // UI tests can pass a solution as base64 with `-uitest.code.<level id> <base64>`.
        if let b64 = defaults.string(forKey: "uitest.code.\(level.id)"), let data = Data(base64Encoded: b64),
           let code = String(data: data, encoding: .utf8) {
            return code
        }
        return defaults.string(forKey: "cc.code.\(level.id)") ?? level.starterCode
    }

    func hasSavedCode(for level: LevelSpec) -> Bool { defaults.string(forKey: "cc.code.\(level.id)") != nil }
    func saveCode(_ code: String, for level: LevelSpec) { defaults.set(code, forKey: "cc.code.\(level.id)") }

    // MARK: Saved maps

    /// The map a level is currently showing. It stays the same until the level is beaten or "New map" is tapped,
    /// so code written for it still fits when the player comes back.
    func seed(for level: LevelSpec) -> UInt64? {
        guard let s = defaults.string(forKey: "cc.seed.\(level.id)") else { return nil }
        return UInt64(s)
    }

    func saveSeed(_ seed: UInt64, for level: LevelSpec) { defaults.set(String(seed), forKey: "cc.seed.\(level.id)") }
    func clearSeed(for level: LevelSpec) { defaults.removeObject(forKey: "cc.seed.\(level.id)") }

    // MARK: Intro cards

    func hasSeenIntro(_ level: LevelSpec) -> Bool { defaults.bool(forKey: "cc.intro.\(level.id)") }
    func markIntroSeen(_ level: LevelSpec) { defaults.set(true, forKey: "cc.intro.\(level.id)") }
}
