import Foundation
import Combine

/// Stars and saved code, kept on the device.
final class GameProgress: ObservableObject {
    static let shared = GameProgress()

    @Published private(set) var starMap: [String: Int]
    private let defaults = UserDefaults.standard

    private init() {
        starMap = (UserDefaults.standard.dictionary(forKey: "cc.stars") as? [String: Int]) ?? [:]
    }

    func stars(for id: String) -> Int { starMap[id] ?? 0 }

    func record(stars s: Int, for id: String) {
        guard s > stars(for: id) else { return }
        starMap[id] = s
        defaults.set(starMap, forKey: "cc.stars")
    }

    func isUnlocked(_ level: LevelSpec, in chapter: [LevelSpec]) -> Bool {
        guard let i = chapter.firstIndex(of: level), i > 0 else { return true }
        return stars(for: chapter[i - 1].id) > 0
    }

    func totalStars(_ chapter: [LevelSpec]) -> Int { chapter.reduce(0) { $0 + stars(for: $1.id) } }

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

    /// Clears stars and saved code.
    func resetAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("cc.") {
            defaults.removeObject(forKey: key)
        }
        starMap = [:]
    }

    func code(for level: LevelSpec) -> String {
        defaults.string(forKey: "cc.code.\(level.id)") ?? level.starterCode
    }

    func hasSavedCode(for level: LevelSpec) -> Bool {
        defaults.string(forKey: "cc.code.\(level.id)") != nil
    }

    func saveCode(_ code: String, for level: LevelSpec) {
        defaults.set(code, forKey: "cc.code.\(level.id)")
    }
}
