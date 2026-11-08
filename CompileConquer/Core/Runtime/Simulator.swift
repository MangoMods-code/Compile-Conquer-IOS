import Foundation

/// One recorded moment of a run, played back by the level screen.
struct TraceStep {
    enum Kind {
        case tick(WorldState, WorldAction, CommandOutcome)
        case print(String)
    }
    let line: Int
    let kind: Kind
}

enum SimEnding {
    case goal           // reached the goal
    case finished       // code ended before the goal
    case error(ScriptError)
    case outOfTicks
}

struct SimResult {
    var steps: [TraceStep]
    var ending: SimEnding
}

/// Runs the player's code start to finish against a copy of the world and records every step.
enum Simulator {
    static let maxTicks = 2000

    /// Parses only (for showing syntax errors before running).
    static func check(code: String, level: LevelSpec) -> ScriptError? {
        do { _ = try PyParser.parse(code, lineOffset: level.headerLines); return nil }
        catch let e as ScriptError { return e }
        catch { return ScriptError(line: level.headerLines + 1, message: "\(error)") }
    }

    static func run(code: String, level: LevelSpec, start: WorldState) -> SimResult {
        let program: [Stmt]
        do {
            program = try PyParser.parse(code, lineOffset: level.headerLines)
        } catch let e as ScriptError {
            return SimResult(steps: [], ending: .error(e))
        } catch {
            return SimResult(steps: [], ending: .error(ScriptError(line: level.headerLines + 1, message: "\(error)")))
        }

        let interp = PyInterpreter()
        let box = WorldBox(start)
        var steps: [TraceStep] = []
        var ending: SimEnding = .finished

        interp.onPrint = { [unowned interp] text in
            steps.append(TraceStep(line: interp.line, kind: .print(text)))
        }

        let act: (WorldAction) throws -> CommandOutcome = { [unowned interp] action in
            let outcome = box.perform(action)
            steps.append(TraceStep(line: interp.line, kind: .tick(box.state, action, outcome)))
            if box.state.goalCount >= level.goal {
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

        do {
            try interp.run(program)
        } catch is PyHalt {
            // ending already set
        } catch let e as ScriptError {
            ending = .error(e)
        } catch {
            ending = .error(ScriptError(line: interp.line, message: "\(error)"))
        }
        return SimResult(steps: steps, ending: ending)
    }
}

// MARK: - Shared helpers for world builtins

enum RuntimeHelpers {
    static func add(_ interp: PyInterpreter, _ name: String, _ f: @escaping ([Value], [String: Value]) throws -> Value) {
        interp.builtins[name] = .builtin(PyBuiltin(name, f))
    }

    static func direction(_ interp: PyInterpreter, _ args: [Value], _ kwargs: [String: Value]) throws -> Direction {
        let v = args.first ?? kwargs["direction"]
        guard let v else { throw interp.err("TypeError: move() needs a direction, like move(North).") }
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
        guard n >= 1 else { throw interp.err("wait(\(n)) wouldn't wait at all. Use 1 or more ticks.") }
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
}

// MARK: - Farm

enum FarmRuntime {
    static func install(_ interp: PyInterpreter, level: LevelSpec, box: WorldBox,
                        act: @escaping (WorldAction) throws -> CommandOutcome) {
        let has = Set(level.commands)
        func add(_ name: String, _ f: @escaping ([Value], [String: Value]) throws -> Value) {
            RuntimeHelpers.add(interp, name, f)
        }
        let stock = PyDict([(.str("Wheat"), .int(0))])
        let refreshStock = { stock.set(.str("Wheat"), .int(box.farm.count(of: .wheat))) }

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
                guard case .str(let s) = seed, let kind = CropKind(rawValue: s) else {
                    throw interp.err("There's no seed called \(seed.repr). Try plant() or plant(Wheat).")
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
                defer { refreshStock() }
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

        interp.builtins["Wheat"] = .str("Wheat")
        interp.builtins["GROW_TIME"] = .int(level.growTime)
        interp.builtins["GOAL"] = .int(level.goal)
        interp.builtins["stock"] = .dict(stock)

        interp.builtins["drone"] = .object(PyObject("Drone", attrs: ["x", "y"]) { name in
            switch name {
            case "x": return .int(box.farm.drone.x)
            case "y": return .int(box.farm.drone.y)
            default: return nil
            }
        })

        func tileObject(_ p: Pos) -> Value {
            .object(PyObject("Tile", attrs: ["x", "y", "ground", "crop", "wet"]) { name in
                let t = box.farm.tile(at: p)
                switch name {
                case "x": return .int(p.x)
                case "y": return .int(p.y)
                case "ground":
                    switch t.ground {
                    case .grass: return .str("grass")
                    case .soil: return .str("soil")
                    case .rock: return .str("rock")
                    case .water: return .str("water")
                    }
                case "wet": return .int(t.wetTicks)
                case "crop":
                    guard let c = box.farm.tile(at: p).crop else { return Value.none }
                    return .object(PyObject("Crop", attrs: ["kind", "age"]) { a in
                        switch a {
                        case "kind": return .str(c.kind.rawValue)
                        case "age": return .int(min(c.growth, c.growTime))
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
            case "tile_at":
                return .builtin(PyBuiltin("tile_at") { args, _ in
                    let p = try RuntimeHelpers.xy(interp, args, "field.tile_at")
                    guard box.farm.inBounds(p) else { throw interp.err("IndexError: (\(p.x), \(p.y)) is outside the field.") }
                    return tileObject(p)
                })
            case "is_open":
                return .builtin(PyBuiltin("is_open") { args, _ in
                    let p = try RuntimeHelpers.xy(interp, args, "field.is_open")
                    return .bool(box.farm.inBounds(p) && box.farm.tile(at: p).ground.walkable)
                })
            case "drone":
                return interp.builtins["drone"]
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

        func crateObject(_ c: Crate, at p: Pos?) -> Value {
            .object(PyObject("Crate", attrs: p == nil ? ["color"] : ["x", "y", "color"]) { name in
                switch name {
                case "x": return p.map { .int($0.x) }
                case "y": return p.map { .int($0.y) }
                case "color": return .str(c.visibleColor)
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

        func baysDict() -> Value {
            let d = PyDict()
            for (color, p) in box.warehouse.bays.sorted(by: { $0.key < $1.key }) {
                d.set(.str(color), .object(PyObject("Bay", attrs: ["x", "y", "color"]) { name in
                    switch name {
                    case "x": return .int(p.x)
                    case "y": return .int(p.y)
                    case "color": return .str(color)
                    default: return nil
                    }
                }))
            }
            return .dict(d)
        }
        let bays = baysDict()

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
            case "shipped": return .int(w.shipped)
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
                    if case .dict(let d) = bays, let b = d.get(.str(color)) { return b }
                    return Value.none
                })
            default: return nil
            }
        })
    }
}
