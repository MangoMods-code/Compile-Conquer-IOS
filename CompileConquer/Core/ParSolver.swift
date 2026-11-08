import Foundation

/// Works out a fair 3-star tick limit for one generated map by actually playing it the
/// straightforward way: fly to the nearest plot, (till,) plant, (water,) wait until ripe,
/// harvest, then go to the next plot. Clever tricks like planting everything before
/// waiting beat this limit, but they aren't required for 3 stars.
enum ParSolver {
    static func straightforwardTicks(_ start: FarmWorld, spec: LevelSpec) -> Int? {
        let canWater = spec.commands.contains("water")
        var best: Int?
        for useWater in canWater ? [false, true] : [false] {
            if let t = simulate(start, spec: spec, useWater: useWater) {
                best = min(best ?? t, t)
            }
        }
        return best
    }

    private static func simulate(_ start: FarmWorld, spec: LevelSpec, useWater: Bool) -> Int? {
        var w = start
        let canTill = spec.commands.contains("till")
        var soil: Set<Pos> = []
        var grass: Set<Pos> = []
        for y in 0..<w.height {
            for x in 0..<w.width {
                let p = Pos(x: x, y: y)
                switch w.tile(at: p).ground {
                case .soil: soil.insert(p)
                case .grass: grass.insert(p)
                default: break
                }
            }
        }

        while w.count(of: .wheat) < spec.goal {
            // Prefer existing soil; fall back to tilling grass when allowed.
            var pool = soil
            if pool.isEmpty, canTill { pool = grass }
            guard let found = nearest(from: w.drone, in: w, targets: pool) else { return nil }
            let target = found.0
            let path = found.1
            soil.remove(target)
            grass.remove(target)

            for d in path { _ = w.perform(.move(d)) }
            if w.tile(at: target).ground == .grass {
                guard canTill else { return nil }
                _ = w.perform(.till)
            }
            _ = w.perform(.plant(.wheat))
            if useWater { _ = w.perform(.water) }
            var waits = 0
            while !(w.tile(at: target).crop?.ripe ?? false) {
                _ = w.perform(.wait)
                waits += 1
                if waits > 200 { return nil }
            }
            _ = w.perform(.harvest)
            if w.ticks > 2000 { return nil }
        }
        return w.ticks
    }

    /// Closest reachable target by walking distance, with the moves to get there.
    private static func nearest(from start: Pos, in w: FarmWorld, targets: Set<Pos>) -> (Pos, [Direction])? {
        guard !targets.isEmpty else { return nil }
        if targets.contains(start) { return (start, []) }
        var came: [Pos: (Pos, Direction)] = [:]
        var seen: Set<Pos> = [start]
        var queue = [start]
        var head = 0
        while head < queue.count {
            let p = queue[head]
            head += 1
            for d in Direction.allCases {
                let n = p.moved(d)
                guard w.inBounds(n), w.tile(at: n).ground.walkable, !seen.contains(n) else { continue }
                seen.insert(n)
                came[n] = (p, d)
                if targets.contains(n) {
                    var path: [Direction] = []
                    var cur = n
                    while let step = came[cur] {
                        path.append(step.1)
                        cur = step.0
                    }
                    return (n, path.reversed())
                }
                queue.append(n)
            }
        }
        return nil
    }
}
