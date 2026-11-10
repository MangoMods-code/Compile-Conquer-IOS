import Foundation

/// Works out a fair 3-star tick limit for one generated farm map by actually playing it.
///
/// - straightforward: go to the nearest plot, (till,) plant, (water,) wait until ripe, harvest, repeat.
/// - planned: plant every plot first, then harvest them (what loop levels are teaching), with slack.
///
/// Clever play beats these limits, but it's never required for 3 stars.
enum ParSolver {
    static func par(_ start: FarmWorld, spec: LevelSpec) -> Int? {
        guard let p = spec.farm else { return nil }
        switch p.par {
        case .fixed(let n):
            return n
        case .straightforward:
            return straightforward(start, spec)
        case .planned(let slack):
            let options = [straightforward(start, spec), planned(start, spec)].compactMap { $0 }
            guard let base = options.min() else { return nil }
            return Int((Double(base) * slack).rounded(.up))
        }
    }

    static func straightforward(_ start: FarmWorld, _ spec: LevelSpec) -> Int? {
        let canWater = spec.commands.contains("water")
        var best: Int?
        for useWater in canWater ? [false, true] : [false] {
            if let t = plotByPlot(start, spec, useWater: useWater) { best = min(best ?? t, t) }
        }
        return best
    }

    // MARK: Strategies

    private static func neededKinds(_ w: FarmWorld, _ spec: LevelSpec) -> [CropKind] {
        spec.cropGoals.filter { w.count(of: $0.kind) < $0.count }.map { $0.kind }
    }

    private static func plotByPlot(_ start: FarmWorld, _ spec: LevelSpec, useWater: Bool) -> Int? {
        var w = start
        let goals = spec.cropGoals
        let canTill = spec.commands.contains("till")
        let canPlant = spec.commands.contains("plant")
        var rounds = 0

        while w.progress(goals) < spec.goal {
            rounds += 1
            if rounds > 400 || w.ticks > 3000 { return nil }
            let needed = neededKinds(w, spec)

            // A needed crop that's already ripe somewhere? Go and pick it.
            let ripe = Set(w.allPositions.filter { p in
                guard let c = w.tile(at: p).crop else { return false }
                return c.ripe && needed.contains(c.kind)
            })
            if !ripe.isEmpty {
                guard let found = nearest(from: w.drone, in: w, targets: ripe) else { return nil }
                for d in found.1 { _ = w.perform(.move(d)) }
                _ = w.perform(.harvest)
                continue
            }

            guard canPlant, let seed = needed.first else { return nil }
            guard let target = goToPlot(&w, canTill: canTill) else { return nil }
            _ = w.perform(.plant(seed))
            if useWater { _ = w.perform(.water) }
            guard waitUntilRipe(&w, at: target) else { return nil }
            _ = w.perform(.harvest)
        }
        return w.ticks
    }

    private static func planned(_ start: FarmWorld, _ spec: LevelSpec) -> Int? {
        guard spec.commands.contains("plant") else { return nil }
        var w = start
        let goals = spec.cropGoals
        let canTill = spec.commands.contains("till")
        var rounds = 0

        while w.progress(goals) < spec.goal {
            rounds += 1
            if rounds > 60 || w.ticks > 3000 { return nil }

            // Every seed still needed, in goal order.
            var seeds: [CropKind] = []
            for g in goals {
                let missing = g.count - w.count(of: g.kind)
                if missing > 0 { seeds += Array(repeating: g.kind, count: missing) }
            }

            // Planting pass.
            var planted: [Pos] = []
            for seed in seeds {
                guard let target = goToPlot(&w, canTill: canTill) else { break }
                _ = w.perform(.plant(seed))
                planted.append(target)
            }
            if planted.isEmpty { return nil }

            // Harvest pass, nearest first.
            var remaining = Set(planted)
            while !remaining.isEmpty {
                guard let found = nearest(from: w.drone, in: w, targets: remaining) else { return nil }
                for d in found.1 { _ = w.perform(.move(d)) }
                guard waitUntilRipe(&w, at: found.0) else { return nil }
                _ = w.perform(.harvest)
                remaining.remove(found.0)
            }
        }
        return w.ticks
    }

    // MARK: Helpers

    /// Flies to the nearest empty soil (tilling grass if there's none and tilling is allowed).
    private static func goToPlot(_ w: inout FarmWorld, canTill: Bool) -> Pos? {
        var pool = Set(w.allPositions.filter { w.tile(at: $0).ground == .soil && w.tile(at: $0).crop == nil })
        if pool.isEmpty, canTill { pool = Set(w.allPositions.filter { w.tile(at: $0).ground == .grass }) }
        guard let found = nearest(from: w.drone, in: w, targets: pool) else { return nil }
        for d in found.1 { _ = w.perform(.move(d)) }
        if w.tile(at: found.0).ground == .grass {
            guard canTill else { return nil }
            _ = w.perform(.till)
        }
        return found.0
    }

    private static func waitUntilRipe(_ w: inout FarmWorld, at p: Pos) -> Bool {
        var waits = 0
        while let c = w.tile(at: p).crop, !c.ripe {
            _ = w.perform(.wait)
            waits += 1
            if waits > 300 { return false }
        }
        return w.tile(at: p).crop != nil
    }

    /// Closest reachable target by flying distance, with the moves to get there.
    static func nearest(from start: Pos, in w: FarmWorld, targets: Set<Pos>) -> (Pos, [Direction])? {
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
                guard w.isOpen(n), !seen.contains(n) else { continue }
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
