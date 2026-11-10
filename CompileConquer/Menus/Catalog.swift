import Foundation

/// A language campaign. Only Python is playable for now.
struct Campaign: Hashable, Identifiable {
    let id: String
    let name: String
    let tagline: String
    let symbol: String
    let available: Bool

    static let all: [Campaign] = [
        Campaign(id: "python", name: "Python", tagline: "Readable, powerful, everywhere. Start here.", symbol: "chevron.left.forwardslash.chevron.right", available: true),
        Campaign(id: "javascript", name: "JavaScript", tagline: "The language of the web.", symbol: "curlybraces", available: false),
        Campaign(id: "lua", name: "Lua", tagline: "Tiny and fast, loved by game makers.", symbol: "moon.stars", available: false),
        Campaign(id: "swift", name: "Swift", tagline: "The language this game is built in.", symbol: "swift", available: false),
    ]
}

/// A world (setting) inside a campaign, each with its own machine and commands.
struct WorldInfo: Hashable, Identifiable {
    let id: String
    let name: String
    let machine: String
    let blurb: String
    let symbol: String
    let available: Bool
    var kind: WorldKind? = nil

    var levels: [LevelSpec] {
        switch id {
        case "farm": return FarmChapter.levels
        case "warehouse": return WarehouseChapter.levels
        default: return []
        }
    }

    static func == (a: WorldInfo, b: WorldInfo) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    /// The world a level belongs to.
    static func containing(_ level: LevelSpec) -> WorldInfo? { all.first { $0.levels.contains(level) } }

    static let all: [WorldInfo] = [
        WorldInfo(id: "farm", name: "The Farm", machine: "Farm drone", blurb: "Till, plant, water and harvest from the sky.", symbol: "leaf.fill", available: true, kind: .farm),
        WorldInfo(id: "warehouse", name: "Warehouse", machine: "Forklift bot", blurb: "Pick, scan and ship crates to the right bays.", symbol: "shippingbox.fill", available: true, kind: .warehouse),
        WorldInfo(id: "mars", name: "Mars Mine", machine: "Rover", blurb: "Drill ore before your battery dies.", symbol: "globe.americas.fill", available: false),
        WorldInfo(id: "ocean", name: "Deep Ocean", machine: "Submarine", blurb: "Sonar, salvage, and watch your oxygen.", symbol: "water.waves", available: false),
        WorldInfo(id: "rail", name: "Rail Yard", machine: "Switch tower", blurb: "Route trains without a crash.", symbol: "tram.fill", available: false),
    ]
}
