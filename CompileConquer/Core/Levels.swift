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
    /// Ticks needed for 3 and 2 stars. Finishing at all is 1 star.
    let threeStarTicks: Int
    let twoStarTicks: Int
    let starterCode: String

    func stars(forTicks t: Int) -> Int { t <= threeStarTicks ? 3 : (t <= twoStarTicks ? 2 : 1) }

    static func == (a: LevelSpec, b: LevelSpec) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum FarmChapter {
    static let levels: [LevelSpec] = [
        LevelSpec(
            id: "py.farm.1", number: 1, title: "First Flight",
            brief: "Harvest 1 Wheat. The drone is parked on soil. Plant, wait for it to ripen, harvest.",
            hint: "Each line runs one command and takes one tick. Wheat here needs 2 ticks to ripen.",
            width: 3, height: 3, soilPlots: 1, rocks: 0, ponds: 0, growTime: 2, goal: 1,
            threeStarTicks: 4, twoStarTicks: 6,
            starterCode: """
            # Welcome, operator. Each line is one command.
            # The drone is sitting on soil. Plant a seed:
            plant()
            # Let it grow:
            wait()
            # Now harvest it!
            """),
        LevelSpec(
            id: "py.farm.2", number: 2, title: "Getting Around",
            brief: "Harvest 2 Wheat. The soil is nearby; fly there with move(North), move(East)...",
            hint: "North is up on the map. Bumping into the edge wastes a tick but doesn't crash.",
            width: 4, height: 4, soilPlots: 2, rocks: 0, ponds: 0, growTime: 3, goal: 2,
            threeStarTicks: 10, twoStarTicks: 14,
            starterCode: """
            # Directions: North, East, South, West
            move(North)
            """),
        LevelSpec(
            id: "py.farm.3", number: 3, title: "Break New Ground",
            brief: "Harvest 2 Wheat. There's no soil yet. till() turns grass under the drone into soil.",
            hint: "till(), then plant(). Plant both tiles before waiting so they grow at the same time.",
            width: 4, height: 4, soilPlots: 0, rocks: 1, ponds: 0, growTime: 3, goal: 2,
            threeStarTicks: 9, twoStarTicks: 13,
            starterCode: """
            till()
            plant()
            """),
        LevelSpec(
            id: "py.farm.4", number: 4, title: "Water Works",
            brief: "Harvest 3 Wheat. Wheat grows slowly here. water() makes a tile grow twice as fast.",
            hint: "Plant, then water each tile. Watered wheat ripens in half the time.",
            width: 5, height: 5, soilPlots: 3, rocks: 2, ponds: 1, growTime: 6, goal: 3,
            threeStarTicks: 18, twoStarTicks: 26,
            starterCode: """
            # Try: plant() then water()
            """),
        LevelSpec(
            id: "py.farm.5", number: 5, title: "Rocky Field",
            brief: "Harvest 4 Wheat on a rocky field. Plan a route around the rocks.",
            hint: "Rocks and ponds block the drone. Hit New Map if this layout is too nasty.",
            width: 6, height: 6, soilPlots: 4, rocks: 5, ponds: 1, growTime: 5, goal: 4,
            threeStarTicks: 24, twoStarTicks: 32,
            starterCode: """
            # Four plots, four harvests. Good luck, operator.
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
