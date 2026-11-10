import Foundation

/// One recorded moment of a run, played back by the level screen.
struct TraceStep {
    enum Kind {
        case tick(WorldState, WorldAction, CommandOutcome)
        case print(String)
    }
    let line: Int
    let kind: Kind
    /// The player's variables right after this step (ticks only).
    let vars: [PyInterpreter.WatchVar]
}

enum SimEnding {
    case goal                 // reached the goal
    case finished             // code ended before the goal
    case error(ScriptError)   // the code hit an error
    case failed(String)       // a level rule was broken
    case outOfTicks
}

struct SimResult {
    var steps: [TraceStep]
    var ending: SimEnding
    /// Variables when the program stopped.
    var finalVars: [PyInterpreter.WatchVar] = []
}

/// Runs the player's code start to finish against a copy of the world and records every step.
enum Simulator {
    static let maxTicks = 2000

    static func run(code: String, level: LevelSpec, start: WorldState, headerLines: Int? = nil) -> SimResult {
        let offset = headerLines ?? (level.header.components(separatedBy: "\n").count - 1)
        let program: [Stmt]
        do {
            program = try PyParser.parse(code, lineOffset: offset)
        } catch let e as ScriptError {
            return SimResult(steps: [], ending: .error(e))
        } catch {
            return SimResult(steps: [], ending: .error(ScriptError(line: offset + 1, message: "\(error)")))
        }

        let interp = PyInterpreter()
        let box = WorldBox(start)
        var steps: [TraceStep] = []
        var ending: SimEnding = .finished

        interp.onPrint = { [unowned interp] text in
            steps.append(TraceStep(line: interp.line, kind: .print(text), vars: []))
        }

        let act: (WorldAction) throws -> CommandOutcome = { [unowned interp] action in
            let outcome = box.perform(action)
            steps.append(TraceStep(line: interp.line, kind: .tick(box.state, action, outcome), vars: interp.watch()))
            if case .farm(let fw) = box.state, let maxLost = level.farm?.maxLost, fw.lost > maxLost {
                ending = .failed("An unripe crop was harvested. On this level that ends the run (MAX_LOST is \(maxLost)).")
                throw PyHalt()
            }
            if box.state.progress(level) >= level.goal {
                ending = .goal
                throw PyHalt()
            }
            if box.state.ticks >= maxTicks {
                ending = .outOfTicks
                throw PyHalt()
            }
            return outcome
        }

        switch level.world {
        case .farm: FarmRuntime.install(interp, level: level, box: box, act: act)
        case .warehouse: WarehouseRuntime.install(interp, level: level, box: box, act: act)
        }
        interp.lockedNames["input"] = "input() isn't available here: levels don't take typed input."

        do {
            try interp.run(program)
        } catch is PyHalt {
            // ending already set
        } catch let e as ScriptError {
            ending = .error(e)
        } catch {
            ending = .error(ScriptError(line: interp.line, message: "\(error)"))
        }
        let finalVars = interp.watch()
        // The commands hold on to the interpreter and it holds on to them; let both go.
        interp.builtins.removeAll()
        interp.globals.removeAll()
        interp.onPrint = { _ in }
        return SimResult(steps: steps, ending: ending, finalVars: finalVars)
    }
}

// MARK: - Shared helpers for world builtins

enum RuntimeHelpers {
    static func add(_ interp: PyInterpreter, _ name: String, _ f: @escaping ([Value], [String: Value]) throws -> Value) {
        interp.builtins[name] = .builtin(PyBuiltin(name, f))
    }

    /// Commands that exist in this world but aren't unlocked on this level get a clear message.
    static func lock(_ interp: PyInterpreter, all: [String], unlocked: [String]) {
        for name in all where !unlocked.contains(name) {
            interp.lockedNames[name] = "NameError: `\(name)` isn't defined in this level's setup. It unlocks in a later level."
        }
    }

    static func direction(_ interp: PyInterpreter, _ args: [Value], _ kwargs: [String: Value]) throws -> Direction {
        guard let v = args.first ?? kwargs["direction"] else {
            throw interp.err("TypeError: move() needs a direction, like move(North).")
        }
        guard case .str(let s) = v, let d = Direction(rawValue: s) else {
            if case .str(let s) = v, let d = Direction(name: s) {
                throw interp.err("Python cares about capitals: use \(d.rawValue), not \(s).")
            }
            throw interp.err("TypeError: move() needs North, East, South or West, not \(v.repr).")
        }
        return d
    }

    static func ticks(_ interp: PyInterpreter, _ args: [Value], _ kwargs: [String: Value]) throws -> Int {
        let v = args.first ?? kwargs["ticks"] ?? .int(1)
        guard case .int(let n) = v else { throw interp.err("TypeError: wait() takes a whole number of ticks, like wait(3).") }
        guard n >= 0 else { throw interp.err("wait(\(n)) can't go back in time. Use 0 or more ticks.") }
        return n
    }

    static func xy(_ interp: PyInterpreter, _ args: [Value], _ name: String) throws -> Pos {
        guard args.count == 2, case .int(let x) = args[0], case .int(let y) = args[1] else {
            throw interp.err("TypeError: \(name)(x, y) needs two whole numbers.")
        }
        return Pos(x: x, y: y)
    }

    static func noArgs(_ interp: PyInterpreter, _ args: [Value], _ name: String) throws {
        guard args.isEmpty else { throw interp.err("TypeError: \(name)() doesn't take anything inside the brackets.") }
    }

    static func dict(_ pairs: [(String, Int)]) -> PyDict {
        PyDict(pairs.map { (Value.str($0.0), Value.int($0.1)) })
    }
}

// MARK: - Farm

enum FarmRuntime {
    static func install(_ interp: PyInterpreter, level: LevelSpec, box: WorldBox,
                        act: @escaping (WorldAction) throws -> CommandOutcome) {
        let has = Set(level.commands)
        func add(_ name: String, _ f: @escaping ([Value], [String: Value]) throws -> Value) {
            RuntimeHelpers.add(interp, name, f)
        }
        RuntimeHelpers.lock(interp, all: FarmSetup.commandOrder, unlocked: level.commands)

        let crops = level.crops
        let simple = crops.count == 1
        let stock = RuntimeHelpers.dict(crops.map { ($0.kind.rawValue, 0) })
        let countsLost = level.farm?.maxLost != nil
        let refresh = {
            for c in crops { stock.set(.str(c.kind.rawValue), .int(box.farm.count(of: c.kind))) }
            if countsLost { interp.builtins["lost"] = .int(box.farm.lost) }
        }

        if has.contains("move") {
            add("move") { args, kw in _ = try act(.farm(.move(try RuntimeHelpers.direction(interp, args, kw)))); return .none }
            for d in Direction.allCases { interp.builtins[d.rawValue] = .str(d.rawValue) }
        }
        if has.contains("till") {
            add("till") { args, _ in try RuntimeHelpers.noArgs(interp, args, "till"); _ = try act(.farm(.till)); return .none }
        }
        if has.contains("plant") {
            add("plant") { args, kw in
                let seed = args.first ?? kw["seed"] ?? .str("Wheat")
                guard case .str(let s) = seed, let kind = CropKind(rawValue: s), crops.contains(where: { $0.kind == kind }) else {
                    let names = crops.map { $0.kind.rawValue }.joined(separator: ", ")
                    throw interp.err("There's no seed \(seed.repr) on this level. Seeds here: \(names).")
                }
                _ = try act(.farm(.plant(kind)))
                return .none
            }
        }
        if has.contains("water") {
            add("water") { args, _ in try RuntimeHelpers.noArgs(interp, args, "water"); _ = try act(.farm(.water)); return .none }
        }
        if has.contains("harvest") {
            add("harvest") { args, _ in
                try RuntimeHelpers.noArgs(interp, args, "harvest")
                defer { refresh() }
                _ = try act(.farm(.harvest))
                return .none
            }
        }
        if has.contains("wait") {
            add("wait") { args, kw in
                let n = try RuntimeHelpers.ticks(interp, args, kw)
                for _ in 0..<n { _ = try act(.farm(.wait)) }
                return .none
            }
        }
        add("tick") { args, _ in try RuntimeHelpers.noArgs(interp, args, "tick"); _ = try act(.farm(.wait)); return .none }

        for c in crops { interp.builtins[c.kind.rawValue] = .str(c.kind.rawValue) }
        if simple {
            interp.builtins["GROW_TIME"] = .int(crops.first?.growTime ?? 2)
            interp.builtins["GOAL"] = .int(level.goal)
        } else {
            interp.builtins["GROW_TIME"] = .dict(RuntimeHelpers.dict(crops.map { ($0.kind.rawValue, $0.growTime) }))
            interp.builtins["GOAL"] = .dict(RuntimeHelpers.dict(level.cropGoals.map { ($0.kind.rawValue, $0.count) }))
        }
        interp.builtins["stock"] = .dict(stock)
        if let maxLost = level.farm?.maxLost {
            interp.builtins["lost"] = .int(0)
            interp.builtins["MAX_LOST"] = .int(maxLost)
        }

        let drone = Value.object(PyObject("Drone", attrs: ["x", "y"]) { name in
            switch name {
            case "x": return .int(box.farm.drone.x)
            case "y": return .int(box.farm.drone.y)
            default: return nil
            }
        })
        interp.builtins["drone"] = drone

        func tileObject(_ p: Pos) -> Value {
            .object(PyObject("Tile", attrs: ["x", "y", "ground", "crop", "wet"]) { name in
                let t = box.farm.tile(at: p)
                switch name {
                case "x": return .int(p.x)
                case "y": return .int(p.y)
                case "ground": return .str(t.ground.name)
                case "wet": return .int(t.wetTicks)
                case "crop":
                    guard t.crop != nil else { return Value.none }
                    // Reads the live crop, so a crop saved in a variable keeps ageing.
                    return .object(PyObject("Crop", attrs: ["kind", "age", "ripe"]) { a in
                        guard let c = box.farm.tile(at: p).crop else {
                            // The crop was harvested since this object was read.
                            switch a {
                            case "ripe": return .bool(false)
                            case "age": return .int(0)
                            case "kind": return Value.none
                            default: return nil
                            }
                        }
                        switch a {
                        case "kind": return .str(c.kind.rawValue)
                        case "age": return .int(min(c.growth, c.growTime))
                        case "ripe": return .bool(c.ripe)
                        default: return nil
                        }
                    })
                default: return nil
                }
            })
        }

        interp.builtins["field"] = .object(PyObject("Field", attrs: ["width", "height"]) { name in
            switch name {
            case "width": return .int(box.farm.width)
            case "height": return .int(box.farm.height)
            case "drone": return drone
            case "tiles": return .list(PyList(box.farm.allPositions.map { tileObject($0) }))
            case "tile_at":
                return .builtin(PyBuiltin("tile_at") { args, _ in
                    let p = try RuntimeHelpers.xy(interp, args, "field.tile_at")
                    guard box.farm.inBounds(p) else {
                        throw interp.err("IndexError: (\(p.x), \(p.y)) is outside the field. x goes 0 to \(box.farm.width - 1), y goes 0 to \(box.farm.height - 1).")
                    }
                    return tileObject(p)
                })
            case "is_open":
                return .builtin(PyBuiltin("is_open") { args, _ in
                    let p = try RuntimeHelpers.xy(interp, args, "field.is_open")
                    return .bool(box.farm.isOpen(p))
                })
            default: return nil
            }
        })
    }
}

// MARK: - Warehouse

enum WarehouseRuntime {
    static func install(_ interp: PyInterpreter, level: LevelSpec, box: WorldBox,
                        act: @escaping (WorldAction) throws -> CommandOutcome) {
        let has = Set(level.commands)
        func add(_ name: String, _ f: @escaping ([Value], [String: Value]) throws -> Value) {
            RuntimeHelpers.add(interp, name, f)
        }
        RuntimeHelpers.lock(interp, all: WarehouseSetup.commandOrder, unlocked: level.commands)

        func crateObject(_ c: Crate, at p: Pos?) -> Value {
            .object(PyObject("Crate", attrs: p == nil ? ["color"] : ["x", "y", "color"]) { name in
                switch name {
                case "x": return p.map { .int($0.x) }
                case "y": return p.map { .int($0.y) }
                case "color":
                    // A hidden label becomes readable once the crate has been scanned.
                    if let p, let live = box.warehouse.crates[p] { return .str(live.visibleColor) }
                    if p == nil, let live = box.warehouse.carrying { return .str(live.visibleColor) }
                    return .str(c.visibleColor)
                default: return nil
                }
            })
        }

        if has.contains("move") {
            add("move") { args, kw in _ = try act(.warehouse(.move(try RuntimeHelpers.direction(interp, args, kw)))); return .none }
        }
        for d in Direction.allCases { interp.builtins[d.rawValue] = .str(d.rawValue) }
        if has.contains("pick") {
            add("pick") { args, _ in try RuntimeHelpers.noArgs(interp, args, "pick"); _ = try act(.warehouse(.pick)); return .none }
        }
        if has.contains("drop") {
            add("drop") { args, _ in
                try RuntimeHelpers.noArgs(interp, args, "drop")
                defer { interp.builtins["shipped"] = .int(box.warehouse.shipped) }
                _ = try act(.warehouse(.drop))
                return .none
            }
        }
        if has.contains("scan") {
            add("scan") { args, _ in
                try RuntimeHelpers.noArgs(interp, args, "scan")
                _ = try act(.warehouse(.scan))
                if let c = box.warehouse.scannedColor { return .str(c) }
                return .none
            }
        }
        if has.contains("wait") {
            add("wait") { args, kw in
                let n = try RuntimeHelpers.ticks(interp, args, kw)
                for _ in 0..<n { _ = try act(.warehouse(.wait)) }
                return .none
            }
        }
        add("tick") { args, _ in try RuntimeHelpers.noArgs(interp, args, "tick"); _ = try act(.warehouse(.wait)); return .none }

        let loader = Value.object(PyObject("Loader", attrs: ["x", "y", "carrying"]) { name in
            let w = box.warehouse
            switch name {
            case "x": return .int(w.loader.x)
            case "y": return .int(w.loader.y)
            case "carrying": return w.carrying.map { crateObject($0, at: nil) } ?? Value.none
            default: return nil
            }
        })

        let bayDict = PyDict()
        for (color, p) in box.warehouse.bays.sorted(by: { $0.key < $1.key }) {
            bayDict.set(.str(color), .object(PyObject("Bay", attrs: ["x", "y", "color"]) { name in
                switch name {
                case "x": return .int(p.x)
                case "y": return .int(p.y)
                case "color": return .str(color)
                default: return nil
                }
            }))
        }
        let bays = Value.dict(bayDict)

        interp.builtins["loader"] = loader
        interp.builtins["BAYS"] = bays
        interp.builtins["GOAL"] = .int(level.goal)
        interp.builtins["shipped"] = .int(0)

        interp.builtins["floor"] = .object(PyObject("Floor", attrs: ["width", "height", "crates"]) { name in
            let w = box.warehouse
            switch name {
            case "width": return .int(w.width)
            case "height": return .int(w.height)
            case "loader": return loader
            case "bays": return bays
            case "time": return .int(w.ticks)
            case "crates":
                let sorted = w.crates.sorted { ($0.key.y, $0.key.x) < ($1.key.y, $1.key.x) }
                return .list(PyList(sorted.map { crateObject($0.value, at: $0.key) }))
            case "is_open":
                return .builtin(PyBuiltin("is_open") { args, _ in
                    let p = try RuntimeHelpers.xy(interp, args, "floor.is_open")
                    return .bool(box.warehouse.isOpen(p))
                })
            case "crate_at":
                return .builtin(PyBuiltin("crate_at") { args, _ in
                    let p = try RuntimeHelpers.xy(interp, args, "floor.crate_at")
                    guard let c = box.warehouse.crates[p] else { return Value.none }
                    return crateObject(c, at: p)
                })
            case "bay_at":
                return .builtin(PyBuiltin("bay_at") { args, _ in
                    let p = try RuntimeHelpers.xy(interp, args, "floor.bay_at")
                    guard box.warehouse.inBounds(p), case .bay(let color) = box.warehouse.tile(at: p) else { return Value.none }
                    return bayDict.get(.str(color)) ?? Value.none
                })
            default: return nil
            }
        })
    }
}
