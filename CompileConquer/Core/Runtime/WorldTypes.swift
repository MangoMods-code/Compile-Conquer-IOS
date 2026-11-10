import Foundation

enum WorldKind: String {
    case farm, warehouse
}

/// One goal counter for the HUD, e.g. Wheat 2/4.
struct GoalItem: Identifiable {
    let label: String
    let have: Int
    let need: Int
    var id: String { label }
    var done: Bool { have >= need }
}

/// What tapping a map tile shows: the code that reads it, and what it would return.
struct TileInfo: Equatable {
    let pos: Pos
    let code: String
    let rows: [Row]

    struct Row: Equatable {
        let name: String
        let value: String
    }
}

/// A snapshot of any world, so one level screen can run every kind of level.
enum WorldState {
    case farm(FarmWorld)
    case warehouse(WarehouseWorld)

    var ticks: Int {
        switch self {
        case .farm(let w): return w.ticks
        case .warehouse(let w): return w.ticks
        }
    }

    var width: Int {
        switch self {
        case .farm(let w): return w.width
        case .warehouse(let w): return w.width
        }
    }

    var height: Int {
        switch self {
        case .farm(let w): return w.height
        case .warehouse(let w): return w.height
        }
    }

    var farm: FarmWorld? { if case .farm(let w) = self { return w }; return nil }
    var warehouse: WarehouseWorld? { if case .warehouse(let w) = self { return w }; return nil }

    /// Progress toward the level's goal (crops harvested toward their targets, or crates shipped).
    func progress(_ level: LevelSpec) -> Int {
        switch self {
        case .farm(let w): return w.progress(level.cropGoals)
        case .warehouse(let w): return w.shipped
        }
    }

    /// The counters shown in the HUD.
    func goalItems(_ level: LevelSpec) -> [GoalItem] {
        switch self {
        case .farm(let w):
            return level.cropGoals.map { GoalItem(label: $0.kind.rawValue, have: min(w.count(of: $0.kind), $0.count), need: $0.count) }
        case .warehouse(let w):
            return [GoalItem(label: "Shipped", have: w.shipped, need: level.goal)]
        }
    }

    /// Builds a level's map from its recipe and a seed.
    static func make(_ level: LevelSpec, seed: UInt64) -> WorldState {
        switch level.world {
        case .farm: return .farm(LevelGenerator.make(level, seed: seed))
        case .warehouse: return .warehouse(WarehouseGenerator.make(level, seed: seed))
        }
    }

    /// The same map with its changing parts re-rolled (for levels that change on every Run).
    func rerolled(_ level: LevelSpec, seed: UInt64) -> WorldState {
        switch self {
        case .farm(let w): return .farm(LevelGenerator.reroll(w, spec: level, seed: seed))
        case .warehouse(let w): return .warehouse(WarehouseGenerator.reroll(w, level: level, seed: seed))
        }
    }

    /// The 3-star tick limit for this map.
    func par(_ level: LevelSpec) -> Int? {
        switch self {
        case .farm(let w): return ParSolver.par(w, spec: level)
        case .warehouse(let w): return WarehouseGenerator.par(w, level: level)
        }
    }

    /// What a tile holds, described the way code would read it.
    func inspect(_ p: Pos) -> TileInfo? {
        switch self {
        case .farm(let w):
            guard w.inBounds(p) else { return nil }
            let t = w.tile(at: p)
            var rows = [TileInfo.Row(name: ".ground", value: "\"\(t.ground.name)\"")]
            if let c = t.crop {
                rows.append(.init(name: ".crop.kind", value: c.kind.rawValue))
                rows.append(.init(name: ".crop.age", value: "\(min(c.growth, c.growTime)) (ripe at \(c.growTime))"))
                rows.append(.init(name: ".crop.ripe", value: c.ripe ? "True" : "False"))
            } else {
                rows.append(.init(name: ".crop", value: "None"))
            }
            rows.append(.init(name: ".wet", value: "\(t.wetTicks)"))
            if w.drone == p { rows.append(.init(name: "drone", value: "is here")) }
            return TileInfo(pos: p, code: "field.tile_at(\(p.x), \(p.y))", rows: rows)

        case .warehouse(let w):
            guard w.inBounds(p) else { return nil }
            var rows: [TileInfo.Row] = []
            switch w.tile(at: p) {
            case .floor: rows.append(.init(name: "floor.is_open", value: "True"))
            case .rack: rows.append(.init(name: "floor.is_open", value: "False (rack)"))
            case .bay(let c):
                rows.append(.init(name: "floor.is_open", value: "True"))
                rows.append(.init(name: "bay", value: "BAYS[\"\(c)\"]"))
            }
            if let c = w.crates[p] {
                rows.append(.init(name: "crate.color", value: "\"\(c.visibleColor)\""))
            } else {
                rows.append(.init(name: "floor.crate_at", value: "None"))
            }
            if w.loader == p {
                rows.append(.init(name: "loader", value: w.carrying == nil ? "is here" : "is here, carrying a crate"))
            }
            return TileInfo(pos: p, code: "x = \(p.x), y = \(p.y)", rows: rows)
        }
    }
}

enum WorldAction {
    case farm(DroneCommand)
    case warehouse(LoaderCommand)

    var isMove: Bool {
        switch self {
        case .farm(.move), .warehouse(.move): return true
        default: return false
        }
    }
}

/// Mutable holder the game commands act on while a program is simulated.
final class WorldBox {
    var state: WorldState
    init(_ state: WorldState) { self.state = state }

    var farm: FarmWorld { state.farm! }
    var warehouse: WarehouseWorld { state.warehouse! }

    func perform(_ action: WorldAction) -> CommandOutcome {
        switch (state, action) {
        case (.farm(var w), .farm(let c)):
            let o = w.perform(c)
            state = .farm(w)
            return o
        case (.warehouse(var w), .warehouse(let c)):
            let o = w.perform(c)
            state = .warehouse(w)
            return o
        default:
            return .warning("That command doesn't work here.")
        }
    }
}
