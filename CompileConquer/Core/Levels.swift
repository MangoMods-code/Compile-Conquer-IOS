import Foundation

/// A level's recipe. The actual map is generated from this plus a seed, so every attempt can differ.
struct LevelSpec: Identifiable, Hashable {
    let id: String
    let number: Int
    let title: String
    let brief: String
    let hint: String
    let width: Int
    let height: Int
    let soilPlots: Int
    let rocks: Int
    let ponds: Int
    let growTime: Int
    let goal: Int
    /// Fallback tick limits for 3 and 2 stars, used only if a map can't be solved automatically.
    /// Normally the limits come from ParSolver for each generated map (see GameSession).
    let threeStarTicks: Int
    let twoStarTicks: Int
    /// Drone commands this level unlocks (defined in the locked setup at the top of main.py).
    let commands: [String]
    let starterCode: String

    func stars(forTicks t: Int) -> Int { t <= threeStarTicks ? 3 : (t <= twoStarTicks ? 2 : 1) }

    var usesDirections: Bool { commands.contains("move") }

    /// Names (besides commands) the setup declares that the player's code can use.
    var setupNames: [String] { (usesDirections ? ["North", "East", "South", "West"] : []) + ["Wheat"] }

    /// The locked top of main.py: declares every variable and defines every command.
    var header: String { FarmSetup.source(for: self) }

    /// Number of locked lines at the top of main.py (the header ends with a newline).
    var headerLines: Int { header.components(separatedBy: "\n").count - 1 }

    static func == (a: LevelSpec, b: LevelSpec) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum FarmChapter {
    static let levels: [LevelSpec] = [
        LevelSpec(
            id: "py.farm.1", number: 1, title: "First Flight",
            brief: "Harvest 1 Wheat. The drone is parked on soil. Scroll up through the setup to see what you can do.",
            hint: "Look at stock and GOAL in the setup. Which def adds to stock? Read its if-statement.",
            width: 3, height: 3, soilPlots: 1, rocks: 0, ponds: 0, growTime: 2, goal: 1,
            threeStarTicks: 4, twoStarTicks: 6,
            commands: ["plant", "wait", "harvest"],
            starterCode: """
            # Your code runs top to bottom. Each
            # command takes 1 tick (see tick() above).

            plant()
            wait()
            # The wheat is ripe now. Which def in the
            # setup adds 1 to stock? Call it here:

            """),
        LevelSpec(
            id: "py.farm.2", number: 2, title: "Getting Around",
            brief: "Harvest 2 Wheat. The soil isn't under the drone this time. A new def in the setup can help.",
            hint: "move(direction) changes drone.x or drone.y by 1. North is up, East is right.",
            width: 4, height: 4, soilPlots: 2, rocks: 0, ponds: 0, growTime: 2, goal: 2,
            threeStarTicks: 12, twoStarTicks: 18,
            commands: ["move", "plant", "wait", "harvest"],
            starterCode: """
            # New in the setup: directions and one new
            # command. Read how it changes drone.x and
            # drone.y, then fly to the soil.


            """),
        LevelSpec(
            id: "py.farm.3", number: 3, title: "Break New Ground",
            brief: "Harvest 2 Wheat. There's no soil anywhere. Look at plant(): what does it need?",
            hint: "till() turns grass into soil. Plant both tiles before waiting so they grow together.",
            width: 4, height: 4, soilPlots: 0, rocks: 1, ponds: 0, growTime: 2, goal: 2,
            threeStarTicks: 12, twoStarTicks: 18,
            commands: ["move", "till", "plant", "wait", "harvest"],
            starterCode: """
            # plant() only works when tile.ground is
            # "soil". Find the new def that sets it.


            """),
        LevelSpec(
            id: "py.farm.4", number: 4, title: "Water Works",
            brief: "Harvest 3 Wheat. GROW_TIME is high on this level. Read tick() to see what speeds crops up.",
            hint: "water() sets tile.wet, and tick() ages wet crops by 2. Plant, then water each tile.",
            width: 5, height: 5, soilPlots: 3, rocks: 1, ponds: 1, growTime: 4, goal: 3,
            threeStarTicks: 20, twoStarTicks: 30,
            commands: ["move", "till", "plant", "water", "wait", "harvest"],
            starterCode: """
            # Check GROW_TIME in the setup. Waiting
            # that long is slow. Look at tick(): what
            # makes a crop age faster?


            """),
        LevelSpec(
            id: "py.farm.5", number: 5, title: "Rocky Field",
            brief: "Harvest 4 Wheat on a rocky field. Plan a route around the rocks.",
            hint: "Rocks and ponds block the drone. Hit New Map if this layout is too nasty.",
            width: 6, height: 6, soilPlots: 4, rocks: 3, ponds: 1, growTime: 3, goal: 4,
            threeStarTicks: 30, twoStarTicks: 45,
            commands: ["move", "till", "plant", "water", "wait", "harvest"],
            starterCode: """
            # Four plots, rocks and a pond. Every
            # command is in the setup. Plan your route.


            """),
    ]
}

enum LevelGenerator {
    /// Builds a map from a spec and a seed. Every soil plot is guaranteed reachable.
    static func make(_ spec: LevelSpec, seed: UInt64) -> FarmWorld {
        for attempt in 0..<200 {
            var rng = SeededRNG(seed: seed &+ UInt64(attempt) &* 7919)
            if let w = tryMake(spec, rng: &rng) { return w }
        }
        // Fallback: an open field with soil around the drone.
        var w = FarmWorld(width: spec.width, height: spec.height, drone: Pos(x: 0, y: 0), growTime: spec.growTime)
        var placed = 0
        for y in 0..<spec.height { for x in 0..<spec.width where placed < spec.soilPlots { w.setGround(.soil, at: Pos(x: x, y: y)); placed += 1 } }
        return w
    }

    private static func tryMake(_ spec: LevelSpec, rng: inout SeededRNG) -> FarmWorld? {
        var all: [Pos] = []
        for y in 0..<spec.height { for x in 0..<spec.width { all.append(Pos(x: x, y: y)) } }
        all.shuffle(using: &rng)

        let drone = all.removeLast()
        var w = FarmWorld(width: spec.width, height: spec.height, drone: drone, growTime: spec.growTime)

        // Soil: level 1 puts it right under the drone; otherwise a small cluster near the drone.
        var soil: [Pos] = []
        if spec.number == 1 {
            soil = [drone]
        } else if spec.soilPlots > 0 {
            let near = all.sorted { dist($0, drone) < dist($1, drone) }
            let pool = Array(near.prefix(max(spec.soilPlots + 3, spec.soilPlots * 2)))
            soil = Array(pool.shuffled(using: &rng).prefix(spec.soilPlots))
        }
        for p in soil { w.setGround(.soil, at: p) }
        all.removeAll { soil.contains($0) }

        // Blockers, never directly next to the drone so level starts aren't boxed in.
        var free = all.filter { dist($0, drone) > 1 }
        free.shuffle(using: &rng)
        for _ in 0..<spec.rocks { if let p = free.popLast() { w.setGround(.rock, at: p) } }
        for _ in 0..<spec.ponds { if let p = free.popLast() { w.setGround(.water, at: p) } }

        // Every walkable tile must be reachable, and there must be enough room to till when there's no soil.
        let reach = reachable(w)
        let walkable = (0..<spec.height).flatMap { y in (0..<spec.width).map { Pos(x: $0, y: y) } }.filter { w.tile(at: $0).ground.walkable }
        guard walkable.allSatisfy({ reach.contains($0) }) else { return nil }
        guard walkable.count >= spec.goal + 1 else { return nil }
        return w
    }

    private static func dist(_ a: Pos, _ b: Pos) -> Int { abs(a.x - b.x) + abs(a.y - b.y) }

    private static func reachable(_ w: FarmWorld) -> Set<Pos> {
        var seen: Set<Pos> = [w.drone]
        var queue = [w.drone]
        while let p = queue.popLast() {
            for d in Direction.allCases {
                let n = p.moved(d)
                if w.inBounds(n), w.tile(at: n).ground.walkable, !seen.contains(n) {
                    seen.insert(n)
                    queue.append(n)
                }
            }
        }
        return seen
    }
}
