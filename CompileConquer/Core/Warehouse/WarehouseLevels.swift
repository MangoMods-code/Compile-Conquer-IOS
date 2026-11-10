import Foundation

/// Extra settings for warehouse levels.
struct WarehouseParams {
    enum Layout {
        /// Open floor: bays along the top, crates anywhere.
        case open
        /// Racks fill the middle rows, leaving aisles.
        case aisles
        /// One bay with crates lined up next to it.
        case line
        /// Crates lined up along the bottom wall, bays along the top.
        case dock
    }
    var layout: Layout
    var crates: Int
    var bayColors: [String]
    /// Labels show "?" until scanned.
    var hidden = false
    /// Crate colors are re-rolled every time Run is pressed, so code can't memorize them.
    var rerollColors = false
    /// Crate positions are re-rolled every time Run is pressed.
    var rerollPositions = false
    /// 3-star limit = the straightforward route's ticks times this.
    var parSlack = 1.0
}

enum WarehouseChapter {
    private static func level(_ key: String, _ n: Int, _ title: String, concept: String, brief: String, hint: String,
                              w: Int, h: Int, params: WarehouseParams, commands: [String], tidy: Int? = nil,
                              starter: String) -> LevelSpec {
        LevelSpec(id: "py.warehouse.\(key)", world: .warehouse, number: n, title: title, concept: concept, brief: brief, hint: hint,
                  width: w, height: h, commands: commands, starterCode: starter, tidyLines: tidy, warehouse: params)
    }

    static let levels: [LevelSpec] = [
        level("1", 1, "First Shift", concept: "A new machine",
              brief: "New place, new machine. Scroll up and read the warehouse setup, then ship 1 crate.",
              hint: "Drive onto the crate, lift it with pick(), drive onto the striped bay, then drop() it.",
              w: 4, h: 3, params: WarehouseParams(layout: .open, crates: 1, bayColors: ["red"]),
              commands: ["move", "pick", "drop", "wait"],
              starter: """
              # A new machine with its own setup. Read
              # what pick() and drop() do to
              # loader.carrying and shipped.


              """),
        level("2", 2, "Color Coded", concept: "Matching values",
              brief: "Two crates, two bays. Read drop() closely: what does a bay check before it accepts a crate?",
              hint: "Each crate's color is on its label. Deliver it to the bay with the same color.",
              w: 5, h: 4, params: WarehouseParams(layout: .open, crates: 2, bayColors: ["red", "blue"], parSlack: 1.15),
              commands: ["move", "pick", "drop", "wait"],
              starter: """
              # Two crates, two bays. Match the colors.


              """),
        level("3", 3, "Aisle Way", concept: "Loops for routes",
              brief: "Racks block the loader, so every trip goes around through the aisles. Ship 3 crates.",
              hint: "The top and bottom rows are always open. Loops shorten long drives: for i in range(3): move(North)",
              w: 6, h: 5, params: WarehouseParams(layout: .aisles, crates: 3, bayColors: ["red", "blue"], parSlack: 1.2),
              commands: ["move", "pick", "drop", "wait"],
              starter: """
              # Racks fill the middle rows. A loop
              # saves typing on long drives:
              #
              #     for i in range(3):
              #         move(North)


              """),
        level("4", 4, "Mystery Boxes", concept: "if / else",
              brief: "The labels are hidden, and the colors change every time you press Run. Read scan() in the setup.",
              hint: "color = scan() stores what scan() returns. Then: if color == \"red\": drive to the red bay, else: the blue one.",
              w: 5, h: 4, params: WarehouseParams(layout: .open, crates: 2, bayColors: ["red", "blue"],
                                                 hidden: true, rerollColors: true, parSlack: 1.15),
              commands: ["move", "pick", "drop", "scan", "wait"],
              starter: """
              # The colors change every Run, so you
              # can't memorize them. scan() returns a
              # value: save it in a variable, then let
              # an if decide where to go.
              #
              #     color = scan()
              #     if color == "red":
              #         ...
              #     else:
              #         ...


              """),
        level("5", 5, "Assembly Line", concept: "Loops with math",
              brief: "Four crates lined up next to the bay. Each trip is one tile longer than the last.",
              hint: "for i in range(4): is one trip per crate. Trip i needs i + 1 moves each way: a loop inside a loop.",
              w: 6, h: 3, params: WarehouseParams(layout: .line, crates: 4, bayColors: ["red"]),
              commands: ["move", "pick", "drop", "wait"], tidy: 9,
              starter: """
              # Writing every move works, but it's long.
              # The loop counter can set how far to go:
              #
              #     for i in range(4):
              #         for j in range(i + 1):
              #             move(East)
              #         ...


              """),
        level("sort", 6, "Sorting Office", concept: "Functions with inputs",
              brief: "Five hidden crates, three bays, new colors every Run. Write one function that drives anywhere, and BAYS will tell you where each color goes.",
              hint: "def go_to(x, y): use while loader.x < x: move(East), and the same for the other three directions. Then go_to(BAYS[color].x, BAYS[color].y).",
              w: 7, h: 4, params: WarehouseParams(layout: .dock, crates: 5, bayColors: ["red", "blue", "green"],
                                                 hidden: true, rerollColors: true, parSlack: 1.3),
              commands: ["move", "pick", "drop", "scan", "wait"], tidy: 16,
              starter: """
              # A def can take inputs, like move() does.
              # while repeats as long as something
              # is true:
              #
              #     def go_to(x, y):
              #         while loader.x < x:
              #             move(East)
              #         ...
              #
              # BAYS[color] is the bay for a color.


              """),
        level("stock", 7, "Stock Take", concept: "Lists of objects",
              brief: "Four crates that land somewhere new every Run. floor.crates is a list of them, and each crate knows its own x, y and color.",
              hint: "for crate in floor.crates: go to crate.x, crate.y, pick(), go to BAYS[crate.color], drop().",
              w: 6, h: 5, params: WarehouseParams(layout: .open, crates: 4, bayColors: ["red", "blue"],
                                                 rerollColors: true, rerollPositions: true, parSlack: 1.5),
              commands: ["move", "pick", "drop", "wait"], tidy: 16,
              starter: """
              # The crates move every Run, so let the
              # data drive your code:
              #
              #     for crate in floor.crates:
              #         print(crate.x, crate.y, crate.color)
              #
              # You'll want your go_to(x, y) again.


              """),
        level("6", 8, "Night Shift", concept: "Putting it together",
              brief: "Hidden crates, three colors, and racks in the way. Write code that works for any colors.",
              hint: "With racks, drive along the bottom or top row first: go down or up the aisle, then across, then along the next aisle.",
              w: 7, h: 6, params: WarehouseParams(layout: .aisles, crates: 4, bayColors: ["red", "blue", "green"],
                                                 hidden: true, rerollColors: true, parSlack: 1.6),
              commands: ["move", "pick", "drop", "scan", "wait"],
              starter: """
              # Everything you've learned. The racks
              # mean go_to needs a smarter route:
              # floor.is_open(x, y) tells you whether
              # a tile can be driven on.


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
        let p = level.warehouse ?? WarehouseParams(layout: .open, crates: 1, bayColors: ["red"])
        for (i, c) in p.bayColors.enumerated() { w.setTile(.bay(c), at: Pos(x: min(i, level.width - 1), y: level.height - 1)) }
        for i in 0..<p.crates {
            w.putCrate(Crate(color: p.bayColors[i % p.bayColors.count], hidden: p.hidden), at: Pos(x: (i + 1) % level.width, y: 0))
        }
        return w
    }

    private static func tryMake(_ level: LevelSpec, rng: inout SeededRNG) -> WarehouseWorld? {
        guard let p = level.warehouse else { return nil }
        let W = level.width, H = level.height

        switch p.layout {
        case .line:
            var w = WarehouseWorld(width: W, height: H, loader: Pos(x: 0, y: 1))
            w.setTile(.bay(p.bayColors[0]), at: Pos(x: 0, y: 1))
            for i in 0..<p.crates {
                w.putCrate(Crate(color: p.bayColors[i % p.bayColors.count], hidden: p.hidden), at: Pos(x: 1 + i, y: 1))
            }
            return w

        case .dock:
            var w = WarehouseWorld(width: W, height: H, loader: Pos(x: 0, y: 0))
            var top = (0..<W).map { Pos(x: $0, y: H - 1) }
            top.shuffle(using: &rng)
            for (i, c) in p.bayColors.enumerated() { w.setTile(.bay(c), at: top[i]) }
            let colors = crateColors(p, count: p.crates, rng: &rng)
            for i in 0..<p.crates { w.putCrate(Crate(color: colors[i], hidden: p.hidden), at: Pos(x: 1 + i, y: 0)) }
            return w

        case .open, .aisles:
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

            var placed = WarehouseWorld(width: W, height: H, loader: start)
            for q in w.allPositions { placed.setTile(w.tile(at: q), at: q) }
            guard scatterCrates(&placed, p, rng: &rng) else { return nil }

            // Everything must be reachable.
            let reach = reachable(placed)
            guard placed.crates.keys.allSatisfy({ reach.contains($0) }), placed.bays.values.allSatisfy({ reach.contains($0) }) else { return nil }
            return placed
        }
    }

    /// Puts the level's crates on random open floor tiles below the bay row.
    private static func scatterCrates(_ w: inout WarehouseWorld, _ p: WarehouseParams, rng: inout SeededRNG) -> Bool {
        var spots = w.allPositions.filter { $0.y < w.height - 1 && w.tile(at: $0) == .floor && $0 != w.loader }
        spots.shuffle(using: &rng)
        guard spots.count >= p.crates else { return false }
        let colors = crateColors(p, count: p.crates, rng: &rng)
        for i in 0..<p.crates { w.putCrate(Crate(color: colors[i], hidden: p.hidden), at: spots[i]) }
        return true
    }

    /// Every bay color appears at least once when there are enough crates.
    private static func crateColors(_ p: WarehouseParams, count: Int, rng: inout SeededRNG) -> [String] {
        var colors = count >= p.bayColors.count ? p.bayColors : []
        while colors.count < count { colors.append(p.bayColors.randomElement(using: &rng) ?? "red") }
        colors.shuffle(using: &rng)
        return Array(colors.prefix(count))
    }

    /// A fresh version of the same floor for levels that change on every Run.
    static func reroll(_ world: WarehouseWorld, level: LevelSpec, seed: UInt64) -> WarehouseWorld {
        guard let p = level.warehouse else { return world }
        var rng = SeededRNG(seed: seed)
        var w = world
        if p.rerollPositions {
            let count = w.crates.count
            w.removeAllCrates()
            var q = p
            q.crates = count
            if !scatterCrates(&w, q, rng: &rng) { return world }
        } else if p.rerollColors {
            let positions = w.crates.keys.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            let colors = crateColors(p, count: positions.count, rng: &rng)
            for (i, pos) in positions.enumerated() { w.recolor(pos, to: colors[i]) }
        }
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

    /// 3-star limit: nearest crate, (scan,) pick, drive to its bay, drop; times the level's slack.
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
        let slack = level.warehouse?.parSlack ?? 1
        return Int((Double(w.ticks) * slack).rounded(.up))
    }
}
