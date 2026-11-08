import Foundation

enum WorldKind: String {
    case farm, warehouse
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

    /// Progress toward the goal: Wheat harvested or crates shipped.
    var goalCount: Int {
        switch self {
        case .farm(let w): return w.count(of: .wheat)
        case .warehouse(let w): return w.shipped
        }
    }

    var farm: FarmWorld? { if case .farm(let w) = self { return w }; return nil }
    var warehouse: WarehouseWorld? { if case .warehouse(let w) = self { return w }; return nil }

    /// Builds a level's map from its recipe and a seed.
    static func make(_ level: LevelSpec, seed: UInt64) -> WorldState {
        switch level.world {
        case .farm: return .farm(LevelGenerator.make(level, seed: seed))
        case .warehouse: return .warehouse(WarehouseGenerator.make(level, seed: seed))
        }
    }

    /// The 3-star tick limit for this map (the straightforward solution's ticks).
    func par(_ level: LevelSpec) -> Int? {
        switch self {
        case .farm(let w): return ParSolver.straightforwardTicks(w, spec: level)
        case .warehouse(let w): return WarehouseGenerator.par(w, level: level)
        }
    }
}

enum WorldAction {
    case farm(DroneCommand)
    case warehouse(LoaderCommand)
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
