import Foundation

/// A crop a farm level uses. `count` is how many must be harvested (0 = it's on the field but isn't a goal).
struct CropGoal: Hashable {
    let kind: CropKind
    let count: Int
    let growTime: Int
}

enum FarmLayout: Equatable {
    /// Soil plots, rocks and ponds scattered around the drone.
    case scatter
    /// One soil tile right under the drone (the very first level).
    case onSoil
    /// A straight line of soil starting next to the drone.
    case row(Int)
    /// A rectangle of soil with the drone on one corner.
    case block(cols: Int, rows: Int)
    /// A line of crops that are already growing: `wheat` of them ripe wheat, the rest young pumpkins.
    case ripeRow(Int, wheat: Int)
}

/// How a level's 3-star tick limit is worked out for each generated map.
enum ParStyle: Equatable {
    /// What the simplest plot-by-plot solution takes.
    case straightforward
    /// Based on planting everything first, then harvesting, with some slack (for loop levels).
    case planned(slack: Double)
    /// A fixed number of ticks.
    case fixed(Int)
}

struct FarmParams {
    var layout: FarmLayout = .scatter
    var soilPlots = 0
    var rocks = 0
    var ponds = 0
    var crops: [CropGoal]
    /// The run ends if more unripe crops than this are harvested. nil = no limit.
    var maxLost: Int? = nil
    /// The field is re-rolled every time Run is pressed, so code can't memorize it.
    var rerollEachRun = false
    var par: ParStyle = .straightforward
}

/// A level's recipe. The actual map is generated from this plus a seed, so every attempt can differ.
struct LevelSpec: Identifiable, Hashable {
    let id: String
    let world: WorldKind
    let number: Int
    let title: String
    /// The idea this level teaches, shown as a tag (e.g. "for loops").
    let concept: String
    let brief: String
    let hint: String
    let width: Int
    let height: Int
    /// Commands this level unlocks (defined in the locked setup at the top of main.py).
    let commands: [String]
    let starterCode: String
    /// Bonus objective: solve it in this many lines of code or fewer.
    var tidyLines: Int? = nil
    var farm: FarmParams? = nil
    var warehouse: WarehouseParams? = nil

    static func == (a: LevelSpec, b: LevelSpec) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    // MARK: Goals

    /// Crops in play on a farm level (goals and non-goals).
    var crops: [CropGoal] { farm?.crops ?? [] }
    var cropGoals: [CropGoal] { crops.filter { $0.count > 0 } }

    /// Total number of things to harvest or ship.
    var goal: Int {
        switch world {
        case .farm: return cropGoals.reduce(0) { $0 + $1.count }
        case .warehouse: return warehouse?.crates ?? 0
        }
    }

    var goalNoun: String {
        switch world {
        case .farm: return cropGoals.count == 1 ? cropGoals[0].kind.rawValue : "crops"
        case .warehouse: return "crates shipped"
        }
    }

    var goalSummary: String {
        switch world {
        case .farm: return "Harvest " + cropGoals.map { "\($0.count) \($0.kind.rawValue)" }.joined(separator: " + ")
        case .warehouse: return "Ship \(goal) crate\(goal == 1 ? "" : "s")"
        }
    }

    var goalIcon: String { world == .farm ? "leaf.fill" : "shippingbox.fill" }
    var worldLabel: String { world == .farm ? "FARM" : "WAREHOUSE" }

    /// The map changes every time Run is pressed.
    var rerollsEachRun: Bool {
        (farm?.rerollEachRun ?? false) || (warehouse?.rerollColors ?? false) || (warehouse?.rerollPositions ?? false)
    }

    // MARK: Code

    var usesDirections: Bool { commands.contains("move") }

    /// The locked top of main.py: declares every variable and defines every command.
    var header: String {
        switch world {
        case .farm: return FarmSetup.source(for: self)
        case .warehouse: return WarehouseSetup.source(for: self)
        }
    }

    /// Names the setup creates, for autocomplete.
    var setupNames: [String] {
        let dirs = usesDirections ? ["North", "East", "South", "West"] : []
        switch world {
        case .farm:
            var n = ["field", "drone", "stock", "GOAL", "GROW_TIME", "tick"] + crops.map { $0.kind.rawValue } + dirs
            if farm?.maxLost != nil { n += ["lost", "MAX_LOST"] }
            return n
        case .warehouse:
            return ["floor", "loader", "BAYS", "shipped", "GOAL", "tick"] + dirs
        }
    }

    /// Number of lines of the player's code that count toward the Tidy bonus (no blanks or comments).
    static func codeLines(_ code: String) -> Int {
        code.components(separatedBy: "\n").filter {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return !t.isEmpty && !t.hasPrefix("#")
        }.count
    }
}

enum FarmChapter {
    private static func level(_ n: Int, _ title: String, concept: String, brief: String, hint: String,
                              w: Int, h: Int, commands: [String], farm: FarmParams, tidy: Int? = nil,
                              starter: String) -> LevelSpec {
        LevelSpec(id: "py.farm.\(n)", world: .farm, number: n, title: title, concept: concept, brief: brief, hint: hint,
                  width: w, height: h, commands: commands, starterCode: starter, tidyLines: tidy, farm: farm)
    }

    private static func wheat(_ count: Int, grow: Int) -> [CropGoal] { [CropGoal(kind: .wheat, count: count, growTime: grow)] }

    static let levels: [LevelSpec] = [
        level(1, "First Flight", concept: "Calling commands",
              brief: "The drone is parked on soil. Scroll up through the setup to see every command you have, then harvest 1 Wheat.",
              hint: "Look at stock and GOAL in the setup. Which def adds to stock? Read its if-statement.",
              w: 3, h: 3, commands: ["plant", "wait", "harvest"],
              farm: FarmParams(layout: .onSoil, crops: wheat(1, grow: 2)),
              starter: """
              # Your code runs top to bottom. Each
              # command takes 1 tick (see tick() above).

              plant()
              wait()
              # The wheat is ripe now. Which def in the
              # setup adds 1 to stock? Call it here:

              """),
        level(2, "Getting Around", concept: "Arguments",
              brief: "The soil isn't under the drone this time. A new command in the setup takes a direction.",
              hint: "move(direction) changes drone.x or drone.y by 1. North is up, East is right. Tap a tile on the map to see its x and y.",
              w: 4, h: 4, commands: ["move", "plant", "wait", "harvest"],
              farm: FarmParams(layout: .scatter, soilPlots: 2, crops: wheat(2, grow: 2)),
              starter: """
              # New in the setup: directions and one new
              # command. Read how it changes drone.x and
              # drone.y, then fly to the soil.


              """),
        level(3, "Break New Ground", concept: "Order matters",
              brief: "There's no soil anywhere. Look at plant() in the setup: what does it need before it works?",
              hint: "till() turns grass into soil. Then plant(), wait for it to ripen, and harvest().",
              w: 4, h: 4, commands: ["move", "till", "plant", "wait", "harvest"],
              farm: FarmParams(layout: .scatter, soilPlots: 0, rocks: 1, crops: wheat(2, grow: 2)),
              starter: """
              # plant() only works when tile.ground is
              # "soil". Find the new def that sets it.


              """),
        level(4, "Water Works", concept: "Reading the rules",
              brief: "GROW_TIME is higher here, so waiting is slow. Read tick() in the setup to find what speeds crops up.",
              hint: "water() sets tile.wet, and tick() ages crops on wet soil by 2. Plant, then water.",
              w: 5, h: 5, commands: ["move", "till", "plant", "water", "wait", "harvest"],
              farm: FarmParams(layout: .scatter, soilPlots: 3, rocks: 1, ponds: 1, crops: wheat(3, grow: 4)),
              starter: """
              # Check GROW_TIME in the setup. Waiting
              # that long is slow. Look at tick(): what
              # makes a crop age faster?


              """),
        level(5, "Rocky Field", concept: "Planning a route",
              brief: "Four plots on a rocky field. Rocks and ponds block the drone, so plan your route.",
              hint: "Tap tiles on the map to check their x and y. Bumping into a rock wastes a tick but doesn't crash.",
              w: 6, h: 6, commands: ["move", "till", "plant", "water", "wait", "harvest"],
              farm: FarmParams(layout: .scatter, soilPlots: 4, rocks: 3, ponds: 1, crops: wheat(4, grow: 3)),
              starter: """
              # Four plots, rocks and a pond. Every
              # command is in the setup. Plan your route.


              """),
        level(6, "Row by Row", concept: "for loops",
              brief: "Five soil tiles in a line. Writing every move by hand works, but a loop does it in two lines.",
              hint: "Plant all five in one loop. wait() until the last one is ripe, then use a second loop to harvest on the way back.",
              w: 7, h: 3, commands: ["move", "plant", "water", "wait", "harvest"],
              farm: FarmParams(layout: .row(5), crops: wheat(5, grow: 6), par: .planned(slack: 1.25)),
              tidy: 8,
              starter: """
              # A for loop repeats the indented lines.
              # This runs move and plant 5 times:
              #
              #     for i in range(5):
              #         move(East)
              #         plant()
              #
              # Check which way the soil runs first!


              """),
        level(7, "Market Garden", concept: "Loops inside loops",
              brief: "A 4 x 3 block of soil: 12 tiles. One loop handles a row. Put it inside another loop to handle every row.",
              hint: "After each row, a loop of 4 moves flies back to the row's start, then one move goes to the next row. Make a second pass with harvest().",
              w: 6, h: 5, commands: ["move", "plant", "water", "wait", "harvest"],
              farm: FarmParams(layout: .block(cols: 4, rows: 3), crops: wheat(12, grow: 10), par: .planned(slack: 1.75)),
              tidy: 16,
              starter: """
              # 4 tiles per row, 3 rows. A loop can go
              # inside another loop:
              #
              #     for row in range(3):
              #         for col in range(4):
              #             plant()
              #             move(East)
              #         # ...fly back to the start of
              #         # the row, then to the next row
              #
              # Check which way the block runs first!


              """),
        level(8, "Pick of the Crop", concept: "if statements",
              brief: "Six crops are already growing, but only the wheat is ripe, and which tiles hold wheat changes every Run. Harvest an unripe crop and the run ends.",
              hint: "tile = field.tile_at(drone.x, drone.y) gets the tile under the drone. Then: if tile.crop.ripe: harvest()",
              w: 8, h: 3, commands: ["move", "harvest", "wait"],
              farm: FarmParams(layout: .ripeRow(6, wheat: 3),
                               crops: [CropGoal(kind: .wheat, count: 3, growTime: 2), CropGoal(kind: .pumpkin, count: 0, growTime: 30)],
                               maxLost: 0, rerollEachRun: true, par: .fixed(9)),
              tidy: 6,
              starter: """
              # The wheat moves every Run, so you can't
              # hard-code it. An if runs its indented
              # lines only when something is true:
              #
              #     tile = field.tile_at(drone.x, drone.y)
              #     if tile.crop.ripe:
              #         harvest()
              #
              # Check the level rule in the setup too.


              """),
        level(9, "Crop Rotation", concept: "Lists",
              brief: "Two crops, four tiles: harvest 4 Wheat and 4 Carrot. plant() takes the seed to plant, and a list can hold both seeds.",
              hint: "for seed in [Wheat, Carrot]: runs its block once per seed. GROW_TIME[seed] tells you how long each one takes.",
              w: 6, h: 3, commands: ["move", "plant", "water", "wait", "harvest"],
              farm: FarmParams(layout: .row(4),
                               crops: [CropGoal(kind: .wheat, count: 4, growTime: 2), CropGoal(kind: .carrot, count: 4, growTime: 5)],
                               par: .planned(slack: 1.5)),
              tidy: 10,
              starter: """
              # GROW_TIME, stock and GOAL are now
              # dictionaries: GROW_TIME[Carrot] is 5.
              # A list holds several values in order,
              # and a for loop can walk through it:
              #
              #     for seed in [Wheat, Carrot]:
              #         plant(seed)
              #         ...


              """),
        level(10, "Harvest Festival", concept: "Your own functions",
              brief: "Three crops on one big field. Use def to bundle steps into your own command, then call it again and again.",
              hint: "def grow(seed): plant(seed), water(), wait until it's ripe, harvest(). Then loop: for i in range(4): grow(Wheat)",
              w: 7, h: 6, commands: ["move", "till", "plant", "water", "wait", "harvest"],
              farm: FarmParams(layout: .scatter, soilPlots: 5, rocks: 4, ponds: 1,
                               crops: [CropGoal(kind: .wheat, count: 4, growTime: 3), CropGoal(kind: .carrot, count: 3, growTime: 5),
                                       CropGoal(kind: .pumpkin, count: 2, growTime: 8)],
                               par: .planned(slack: 1.4)),
              tidy: 14,
              starter: """
              # The big one. A def makes your own
              # command, just like the ones in the setup:
              #
              #     def grow(seed):
              #         plant(seed)
              #         water()
              #         wait(GROW_TIME[seed] // 2)
              #         harvest()
              #
              # Then call it: grow(Carrot)


              """),
    ]
}

enum LevelGenerator {
    /// Builds a farm map from a spec and a seed.
    static func make(_ spec: LevelSpec, seed: UInt64) -> FarmWorld {
        let params = spec.farm ?? FarmParams(crops: [CropGoal(kind: .wheat, count: 1, growTime: 2)])
        let growTimes = Dictionary(uniqueKeysWithValues: params.crops.map { ($0.kind, $0.growTime) })
        for attempt in 0..<200 {
            var rng = SeededRNG(seed: seed &+ UInt64(attempt) &* 7919)
            if let w = tryMake(spec, params, growTimes, rng: &rng) { return w }
        }
        // Fallback: an open field with soil in the bottom row.
        var w = FarmWorld(width: spec.width, height: spec.height, drone: Pos(x: 0, y: 0), growTimes: growTimes)
        for x in 0..<min(spec.width, max(1, params.soilPlots)) { w.setGround(.soil, at: Pos(x: x, y: 0)) }
        return w
    }

    private static func tryMake(_ spec: LevelSpec, _ p: FarmParams, _ growTimes: [CropKind: Int], rng: inout SeededRNG) -> FarmWorld? {
        let W = spec.width, H = spec.height
        switch p.layout {
        case .onSoil, .scatter:
            var all: [Pos] = []
            for y in 0..<H { for x in 0..<W { all.append(Pos(x: x, y: y)) } }
            all.shuffle(using: &rng)
            let drone = all.removeLast()
            var w = FarmWorld(width: W, height: H, drone: drone, growTimes: growTimes)

            var soil: [Pos] = []
            if p.layout == .onSoil {
                soil = [drone]
            } else if p.soilPlots > 0 {
                let near = all.sorted { dist($0, drone) < dist($1, drone) }
                let pool = Array(near.prefix(max(p.soilPlots + 3, p.soilPlots * 2)))
                soil = Array(pool.shuffled(using: &rng).prefix(p.soilPlots))
            }
            for s in soil { w.setGround(.soil, at: s) }
            all.removeAll { soil.contains($0) }

            // Blockers, never directly next to the drone so level starts aren't boxed in.
            var free = all.filter { dist($0, drone) > 1 }
            free.shuffle(using: &rng)
            for _ in 0..<p.rocks { if let q = free.popLast() { w.setGround(.rock, at: q) } }
            for _ in 0..<p.ponds { if let q = free.popLast() { w.setGround(.water, at: q) } }

            let reach = reachable(w)
            let walkable = w.allPositions.filter { w.tile(at: $0).ground.walkable }
            guard walkable.allSatisfy({ reach.contains($0) }) else { return nil }
            guard walkable.count >= 3 else { return nil }
            return w

        case .row(let n), .ripeRow(let n, _):
            // The row runs along the middle; the drone waits at one end.
            let y = H / 2
            let fromLeft = Bool.random(using: &rng)
            let drone = Pos(x: fromLeft ? 0 : n + 1, y: y)
            var w = FarmWorld(width: W, height: H, drone: drone, growTimes: growTimes)
            for x in 1...n { w.setGround(.soil, at: Pos(x: x, y: y)) }
            decorate(&w, keepClear: { $0.y == y }, rocks: 2, ponds: 1, rng: &rng)
            if case .ripeRow(_, let wheat) = p.layout { plantRipeRow(&w, n: n, wheat: wheat, rng: &rng) }
            return w

        case .block(let cols, let rows):
            let x0 = 1, y0 = 1
            let corners = [Pos(x: x0, y: y0), Pos(x: x0 + cols - 1, y: y0), Pos(x: x0, y: y0 + rows - 1), Pos(x: x0 + cols - 1, y: y0 + rows - 1)]
            let drone = corners.randomElement(using: &rng) ?? corners[0]
            var w = FarmWorld(width: W, height: H, drone: drone, growTimes: growTimes)
            for y in y0..<(y0 + rows) { for x in x0..<(x0 + cols) { w.setGround(.soil, at: Pos(x: x, y: y)) } }
            return w
        }
    }

    /// A few rocks or a pond away from the working area, just for looks.
    private static func decorate(_ w: inout FarmWorld, keepClear: (Pos) -> Bool, rocks: Int, ponds: Int, rng: inout SeededRNG) {
        var free = w.allPositions.filter { !keepClear($0) && w.tile(at: $0).ground == .grass && $0 != w.drone }
        free.shuffle(using: &rng)
        for _ in 0..<rocks { if let q = free.popLast() { w.setGround(.rock, at: q) } }
        for _ in 0..<ponds { if let q = free.popLast() { w.setGround(.water, at: q) } }
    }

    /// Fills the row with crops: ripe wheat on `wheat` random tiles, young pumpkins on the rest.
    private static func plantRipeRow(_ w: inout FarmWorld, n: Int, wheat: Int, rng: inout SeededRNG) {
        let y = w.drone.y
        var xs = Array(1...n)
        xs.shuffle(using: &rng)
        let wheatXs = Set(xs.prefix(wheat))
        for x in 1...n {
            if wheatXs.contains(x) {
                let g = w.growTime(.wheat)
                w.setCrop(Crop(kind: .wheat, growth: g, growTime: g), at: Pos(x: x, y: y))
            } else {
                // Well on their way, but nowhere near ripe.
                let g = w.growTime(.pumpkin)
                w.setCrop(Crop(kind: .pumpkin, growth: g * 45 / 100, growTime: g), at: Pos(x: x, y: y))
            }
        }
    }

    /// A fresh version of the same map for levels that change on every Run.
    static func reroll(_ world: FarmWorld, spec: LevelSpec, seed: UInt64) -> FarmWorld {
        guard let p = spec.farm, case .ripeRow(let n, let wheat) = p.layout else { return world }
        var rng = SeededRNG(seed: seed)
        var w = world
        plantRipeRow(&w, n: n, wheat: wheat, rng: &rng)
        return w
    }

    private static func dist(_ a: Pos, _ b: Pos) -> Int { abs(a.x - b.x) + abs(a.y - b.y) }

    private static func reachable(_ w: FarmWorld) -> Set<Pos> {
        var seen: Set<Pos> = [w.drone]
        var queue = [w.drone]
        while let p = queue.popLast() {
            for d in Direction.allCases {
                let n = p.moved(d)
                if w.isOpen(n), !seen.contains(n) {
                    seen.insert(n)
                    queue.append(n)
                }
            }
        }
        return seen
    }
}
