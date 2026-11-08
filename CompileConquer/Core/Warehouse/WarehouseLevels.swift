import Foundation

/// Extra settings for warehouse levels.
struct WarehouseParams {
    enum Layout { case open, aisles, line }
    var layout: Layout
    var crates: Int
    var bayColors: [String]
    /// Labels show "?" until scanned.
    var hidden = false
    /// Crate colors are re-rolled every time Run is pressed, so code can't just memorize them.
    var reshuffleEachRun = false
}

enum WarehouseChapter {
    private static func level(_ n: Int, _ title: String, brief: String, hint: String, w: Int, h: Int,
                              params: WarehouseParams, commands: [String], starter: String) -> LevelSpec {
        LevelSpec(id: "py.warehouse.\(n)", number: n, title: title, brief: brief, hint: hint,
                  width: w, height: h, soilPlots: 0, rocks: 0, ponds: 0, growTime: 0, goal: params.crates,
                  threeStarTicks: 40, twoStarTicks: 60, commands: commands, starterCode: starter,
                  world: .warehouse, warehouse: params)
    }

    static let levels: [LevelSpec] = [
        level(1, "First Shift",
              brief: "Ship 1 crate. New place, new machine: scroll up and read the warehouse setup first.",
              hint: "Fly onto the crate, lift it with pick(), fly to the striped bay, then drop() it.",
              w: 4, h: 3, params: WarehouseParams(layout: .open, crates: 1, bayColors: ["red"]),
              commands: ["move", "pick", "drop", "wait"],
              starter: """
              # A new machine with its own setup. Read
              # what pick() and drop() do to
              # loader.carrying and shipped.


              """),
        level(2, "Color Coded",
              brief: "Ship 2 crates. Read drop() closely: what does a bay check before it accepts a crate?",
              hint: "Each crate's color is painted on it. Deliver it to the bay with the same color.",
              w: 5, h: 4, params: WarehouseParams(layout: .open, crates: 2, bayColors: ["red", "blue"]),
              commands: ["move", "pick", "drop", "wait"],
              starter: """
              # Two crates, two bays. Match the colors.


              """),
        level(3, "Aisle Way",
              brief: "Ship 3 crates through the aisles. Racks block the loader, so plan your route.",
              hint: "The top and bottom rows are open. Loops help here: for i in range(3): move(North)",
              w: 6, h: 5, params: WarehouseParams(layout: .aisles, crates: 3, bayColors: ["red", "blue"]),
              commands: ["move", "pick", "drop", "wait"],
              starter: """
              # Racks fill the middle rows. Real Python
              # works now: a for loop repeats lines.
              #     for i in range(3):
              #         move(North)


              """),
        level(4, "Mystery Boxes",
              brief: "Ship 2 crates. Their labels are hidden AND change every time you press Run. Read scan().",
              hint: "color = scan() stores what scan() returns. Then: if color == \"red\": ... else: ...",
              w: 5, h: 4, params: WarehouseParams(layout: .open, crates: 2, bayColors: ["red", "blue"],
                                                 hidden: true, reshuffleEachRun: true),
              commands: ["move", "pick", "drop", "scan", "wait"],
              starter: """
              # The colors change every run, so you
              # can't memorize them. scan() returns a
              # value: save it in a variable, then let
              # an if decide where to go.


              """),
        level(5, "Assembly Line",
              brief: "Ship 4 crates lined up in a row. Each trip is a bit longer than the last.",
              hint: "for i in range(4): is one trip per crate. Trip i needs i + 1 moves each way: a loop inside a loop.",
              w: 6, h: 3, params: WarehouseParams(layout: .line, crates: 4, bayColors: ["red"]),
              commands: ["move", "pick", "drop", "wait"],
              starter: """
              # Writing every move works, but it's long.
              # Try a loop inside a loop:
              #     for i in range(4):
              #         for j in range(i + 1):
              #             ...


              """),
        level(6, "Night Shift",
              brief: "Ship 4 hidden crates across the aisles. Write code that works for any colors.",
              hint: "Travel along the top row: go North, then East/West, then South. floor.crates and BAYS tell you where.",
              w: 7, h: 6, params: WarehouseParams(layout: .aisles, crates: 4, bayColors: ["red", "blue", "green"],
                                                 hidden: true, reshuffleEachRun: true),
              commands: ["move", "pick", "drop", "scan", "wait"],
              starter: """
              # Everything you've learned. A def that
              # drives to any (x, y) will save a lot of
              # lines. floor.crates lists every crate.


              """),
    ]
}

enum WarehouseGenerator {
    static func make(_ level: LevelSpec, seed: UInt64) -> WarehouseWorld {
        for attempt in 0..<300 {
            var rng = SeededRNG(seed: seed &+ UInt64(attempt) &* 104_729)
            if let w = tryMake(level, rng: &rng) { return w }
        }
        // Fallback: open floor, everything in a row.
        var w = WarehouseWorld(width: level.width, height: level.height, loader: Pos(x: 0, y: 0))
        let p = level.warehouse!
        for (i, c) in p.bayColors.enumerated() { w.setTile(.bay(c), at: Pos(x: min(i, level.width - 1), y: level.height - 1)) }
        for i in 0..<p.crates { w.putCrate(Crate(color: p.bayColors[i % p.bayColors.count], hidden: p.hidden), at: Pos(x: (i + 1) % level.width, y: 0)) }
        return w
    }

    private static func tryMake(_ level: LevelSpec, rng: inout SeededRNG) -> WarehouseWorld? {
        guard let p = level.warehouse else { return nil }
        let W = level.width, H = level.height

        if p.layout == .line {
            var w = WarehouseWorld(width: W, height: H, loader: Pos(x: 0, y: 1))
            w.setTile(.bay(p.bayColors[0]), at: Pos(x: 0, y: 1))
            for i in 0..<p.crates {
                w.putCrate(Crate(color: p.bayColors[i % p.bayColors.count], hidden: p.hidden), at: Pos(x: 1 + i, y: 1))
            }
            return w
        }

        var w = WarehouseWorld(width: W, height: H, loader: Pos(x: 0, y: 0))
        if p.layout == .aisles {
            for x in stride(from: 1, to: W - 1, by: 2) {
                for y in 1..<(H - 1) { w.setTile(.rack, at: Pos(x: x, y: y)) }
            }
        }

        // Bays along the top row.
        var top = (0..<W).map { Pos(x: $0, y: H - 1) }.filter { w.tile(at: $0) == .floor }
        top.shuffle(using: &rng)
        guard top.count >= p.bayColors.count else { return nil }
        for (i, c) in p.bayColors.enumerated() { w.setTile(.bay(c), at: top[i]) }

        // Loader starts on the bottom row.
        let bottom = (0..<W).map { Pos(x: $0, y: 0) }.filter { w.tile(at: $0) == .floor }
        guard let start = bottom.randomElement(using: &rng) else { return nil }

        // Crates anywhere open below the bay row.
        var spots: [Pos] = []
        for y in 0..<(H - 1) { for x in 0..<W where w.tile(at: Pos(x: x, y: y)) == .floor && Pos(x: x, y: y) != start { spots.append(Pos(x: x, y: y)) } }
        spots.shuffle(using: &rng)
        guard spots.count >= p.crates else { return nil }
        let colors = crateColors(p, rng: &rng)
        for i in 0..<p.crates { w.putCrate(Crate(color: colors[i], hidden: p.hidden), at: spots[i]) }

        var placed = WarehouseWorld(width: W, height: H, loader: start)
        for y in 0..<H { for x in 0..<W { placed.setTile(w.tile(at: Pos(x: x, y: y)), at: Pos(x: x, y: y)) } }
        for (pos, c) in w.crates { placed.putCrate(c, at: pos) }

        // Everything must be reachable.
        let reach = reachable(placed)
        guard placed.crates.keys.allSatisfy({ reach.contains($0) }), placed.bays.values.allSatisfy({ reach.contains($0) }) else { return nil }
        return placed
    }

    /// Every bay color appears at least once when there are enough crates.
    private static func crateColors(_ p: WarehouseParams, rng: inout SeededRNG) -> [String] {
        var colors = p.crates >= p.bayColors.count ? p.bayColors : []
        while colors.count < p.crates { colors.append(p.bayColors.randomElement(using: &rng)!) }
        colors.shuffle(using: &rng)
        return colors
    }

    /// New colors for the same crates (used by levels that re-roll every run).
    static func reshuffle(_ world: WarehouseWorld, level: LevelSpec, seed: UInt64) -> WarehouseWorld {
        guard let p = level.warehouse, p.layout != .line else { return world }
        var rng = SeededRNG(seed: seed)
        var w = world
        let positions = w.crates.keys.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        let colors = crateColors(WarehouseParams(layout: p.layout, crates: positions.count, bayColors: p.bayColors), rng: &rng)
        for (i, pos) in positions.enumerated() { w.recolor(pos, to: colors[i]) }
        return w
    }

    private static func reachable(_ w: WarehouseWorld) -> Set<Pos> {
        var seen: Set<Pos> = [w.loader]
        var queue = [w.loader]
        while let p = queue.popLast() {
            for d in Direction.allCases {
                let n = p.moved(d)
                if w.isOpen(n), !seen.contains(n) { seen.insert(n); queue.append(n) }
            }
        }
        return seen
    }

    static func path(_ w: WarehouseWorld, from start: Pos, to goals: Set<Pos>) -> (Pos, [Direction])? {
        if goals.contains(start) { return (start, []) }
        var came: [Pos: (Pos, Direction)] = [:]
        var seen: Set<Pos> = [start]
        var queue = [start]
        var head = 0
        while head < queue.count {
            let p = queue[head]
            head += 1
            for d in Direction.allCases {
                let n = p.moved(d)
                guard w.isOpen(n), !seen.contains(n) else { continue }
                seen.insert(n)
                came[n] = (p, d)
                if goals.contains(n) {
                    var dirs: [Direction] = []
                    var cur = n
                    while let step = came[cur] { dirs.append(step.1); cur = step.0 }
                    return (n, dirs.reversed())
                }
                queue.append(n)
            }
        }
        return nil
    }

    /// Ticks for the straightforward solution: nearest crate, (scan,) pick, drive to its bay, drop.
    static func par(_ start: WarehouseWorld, level: LevelSpec) -> Int? {
        var w = start
        let scans = level.commands.contains("scan") && (level.warehouse?.hidden ?? false)
        while w.shipped < level.goal {
            guard let toCrate = path(w, from: w.loader, to: Set(w.crates.keys)) else { return nil }
            for d in toCrate.1 { _ = w.perform(.move(d)) }
            if scans { _ = w.perform(.scan) }
            _ = w.perform(.pick)
            guard let color = w.carrying?.color, let bay = w.bays[color],
                  let toBay = path(w, from: w.loader, to: [bay]) else { return nil }
            for d in toBay.1 { _ = w.perform(.move(d)) }
            _ = w.perform(.drop)
            if w.ticks > 2000 { return nil }
        }
        return w.ticks
    }
}
