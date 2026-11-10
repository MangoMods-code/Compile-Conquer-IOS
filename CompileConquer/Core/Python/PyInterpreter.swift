import Foundation

/// Thrown by a world when the program should stop early (goal reached, or out of ticks).
struct PyHalt: Error {}

/// Tree-walking interpreter for the game's Python subset. It runs the whole program in one go
/// against a simulated world; the game then plays the recorded steps back with animation.
final class PyInterpreter {
    var globals: [String: Value] = [:]
    var builtins: [String: Value] = [:]
    /// The main.py line currently running (what the editor highlights).
    private(set) var line = 0
    var onPrint: (String) -> Void = { _ in }

    private var budget: Int
    private let maxBudget: Int
    private var depth = 0

    /// Names that exist in the game but not on this level, with the message to show instead of a NameError.
    var lockedNames: [String: String] = [:]
    /// Order in which the player's global variables were first assigned (for the Variables panel).
    private var globalOrder: [String] = []
    private var frameStack: [Frame] = []

    private final class Frame {
        let name: String
        var locals: [String: Value] = [:]
        var order: [String] = []
        var globalNames: Set<String> = []
        init(name: String) { self.name = name }
    }

    /// One row of the Variables panel.
    struct WatchVar: Equatable {
        let name: String
        let value: String
        /// nil for globals, otherwise the function the variable lives in.
        let scope: String?
    }

    /// The player's variables right now: globals first, then the locals of the function being run.
    func watch(limit: Int = 18) -> [WatchVar] {
        func short(_ v: Value) -> String {
            let r = v.repr
            return r.count > 46 ? String(r.prefix(45)) + "…" : r
        }
        var out: [WatchVar] = []
        for n in globalOrder {
            guard let v = globals[n] else { continue }
            if case .function = v { continue }
            out.append(WatchVar(name: n, value: short(v), scope: nil))
            if out.count >= limit { return out }
        }
        if let f = frameStack.last {
            for n in f.order {
                guard let v = f.locals[n] else { continue }
                if case .function = v { continue }
                out.append(WatchVar(name: n, value: short(v), scope: f.name))
                if out.count >= limit { break }
            }
        }
        return out
    }

    private enum Flow {
        case normal, brk, cont
        case ret(Value)
    }

    init(stepBudget: Int = 400_000) {
        budget = stepBudget
        maxBudget = stepBudget
        installStandardBuiltins()
    }

    func run(_ program: [Stmt]) throws {
        switch try exec(program, nil) {
        case .brk: throw err("SyntaxError: `break` can only be used inside a loop.")
        case .cont: throw err("SyntaxError: `continue` can only be used inside a loop.")
        case .ret: throw err("SyntaxError: `return` can only be used inside a def.")
        case .normal: break
        }
    }

    func err(_ message: String) -> ScriptError { ScriptError(line: line, message: message) }

    private func spend() throws {
        budget -= 1
        if budget <= 0 {
            throw err("Your code ran \(maxBudget.formatted()) steps without finishing. Is there a loop that never ends?")
        }
    }

    // MARK: Statements

    private func exec(_ body: [Stmt], _ frame: Frame?) throws -> Flow {
        for s in body {
            line = s.line
            try spend()
            switch s.kind {
            case .expr(let e):
                let v = try eval(e, frame)
                if case .name(let n) = e {
                    switch v {
                    case .builtin, .function:
                        throw err("`\(n)` is a function. Add brackets to call it: \(n)()")
                    default:
                        break
                    }
                }

            case .assign(let target, let valueExpr):
                try assign(target, try eval(valueExpr, frame), frame)

            case .augAssign(let target, let op, let valueExpr):
                let current = try eval(target, frame)
                let rhs = try eval(valueExpr, frame)
                if op == "+", case .list(let l) = current, case .list(let r) = rhs {
                    l.items += r.items
                } else {
                    try assign(target, try binary(op, current, rhs), frame)
                }

            case .ifs(let branches, let elseBody):
                var taken = false
                for (cond, block) in branches {
                    guard try eval(cond, frame).truthy else { continue }
                    taken = true
                    let f = try exec(block, frame)
                    if case .normal = f {} else { return f }
                    break
                }
                if !taken, let elseBody {
                    let f = try exec(elseBody, frame)
                    if case .normal = f {} else { return f }
                }

            case .whileLoop(let cond, let block):
                loop: while true {
                    line = s.line
                    try spend()
                    guard try eval(cond, frame).truthy else { break }
                    switch try exec(block, frame) {
                    case .brk: break loop
                    case .cont, .normal: continue loop
                    case .ret(let v): return .ret(v)
                    }
                }

            case .forLoop(let target, let iterExpr, let block):
                let items = try iterate(try eval(iterExpr, frame))
                loop: for item in items {
                    line = s.line
                    try spend()
                    try assign(target, item, frame)
                    switch try exec(block, frame) {
                    case .brk: break loop
                    case .cont, .normal: continue loop
                    case .ret(let v): return .ret(v)
                    }
                }

            case .def(let name, let params, let body):
                let fn = PyFunction(name: name, params: params, body: body)
                fn.defaults = try params.map { p in try p.defaultValue.map { try eval($0, frame) } }
                try assign(.name(name), .function(fn), frame)

            case .ret(let e):
                guard frame != nil else { throw err("SyntaxError: `return` can only be used inside a def.") }
                let value: Value = try e.map { try eval($0, frame) } ?? Value.none
                return .ret(value)

            case .brk: return .brk
            case .cont: return .cont
            case .pass: break
            case .global(let names):
                frame?.globalNames.formUnion(names)
            }
        }
        return .normal
    }

    private func assign(_ target: Expr, _ value: Value, _ frame: Frame?) throws {
        switch target {
        case .name(let n):
            if let frame, !frame.globalNames.contains(n) {
                if frame.locals[n] == nil { frame.order.append(n) }
                frame.locals[n] = value
            } else {
                if globals[n] == nil { globalOrder.append(n) }
                globals[n] = value
            }
        case .attr(let objExpr, let name):
            let obj = try eval(objExpr, frame)
            if case .object(let o) = obj {
                throw err("\(o.typeName).\(name) is read-only. Only the commands can change the world.")
            }
            throw err("AttributeError: can't set .\(name) on a \(obj.typeName).")
        case .index(let containerExpr, let indexExpr):
            let container = try eval(containerExpr, frame)
            let idx = try eval(indexExpr, frame)
            switch container {
            case .list(let l):
                l.items[try listIndex(idx, count: l.items.count)] = value
            case .dict(let d):
                d.set(idx, value)
            default:
                throw err("TypeError: a \(container.typeName) can't be changed with [ ].")
            }
        case .tuple(let targets):
            let items = try iterate(value)
            guard items.count == targets.count else {
                throw err("ValueError: expected \(targets.count) values to unpack, got \(items.count).")
            }
            for (t, v) in zip(targets, items) { try assign(t, v, frame) }
        default:
            throw err("SyntaxError: can't assign to that.")
        }
    }

    // MARK: Expressions

    private func lookup(_ n: String, _ frame: Frame?) throws -> Value {
        if let frame, let v = frame.locals[n] { return v }
        if let v = globals[n] { return v }
        if let v = builtins[n] { return v }
        if let msg = lockedNames[n] { throw err(msg) }
        if let close = suggestion(for: n, frame) {
            throw err("NameError: `\(n)` isn't defined. Did you mean `\(close)`?")
        }
        throw err("NameError: `\(n)` isn't defined. Check the spelling, or give it a value before using it.")
    }

    /// The closest known name to a misspelled one (wrong capitals, or one or two letters off).
    private func suggestion(for n: String, _ frame: Frame?) -> String? {
        var names = Array(globals.keys) + Array(builtins.keys)
        if let frame { names += Array(frame.locals.keys) }
        if let exact = names.first(where: { $0.lowercased() == n.lowercased() }) { return exact }
        guard n.count >= 3 else { return nil }
        var best: (String, Int)?
        for c in names where abs(c.count - n.count) <= 2 {
            let d = PyInterpreter.editDistance(c.lowercased(), n.lowercased())
            if d <= (n.count >= 4 ? 2 : 1), d < (best?.1 ?? 99) { best = (c, d) }
        }
        return best?.0
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }

    private func eval(_ e: Expr, _ frame: Frame?) throws -> Value {
        switch e {
        case .int(let v): return .int(v)
        case .float(let v): return .float(v)
        case .str(let s): return .str(s)
        case .bool(let b): return .bool(b)
        case .none: return .none
        case .name(let n): return try lookup(n, frame)
        case .list(let items): return .list(PyList(try items.map { try eval($0, frame) }))
        case .tuple(let items): return .tuple(try items.map { try eval($0, frame) })
        case .dict(let pairs):
            let d = PyDict()
            for (k, v) in pairs { d.set(try eval(k, frame), try eval(v, frame)) }
            return .dict(d)
        case .unary(let op, let x):
            let v = try eval(x, frame)
            switch op {
            case "not": return .bool(!v.truthy)
            case "-":
                switch v {
                case .int(let i): return .int(-i)
                case .float(let f): return .float(-f)
                case .bool(let b): return .int(b ? -1 : 0)
                default: throw err("TypeError: can't make a \(v.typeName) negative.")
                }
            default: return v
            }
        case .binary(let op, let a, let b):
            return try binary(op, try eval(a, frame), try eval(b, frame))
        case .compare(let first, let rest):
            var left = try eval(first, frame)
            for (op, rightExpr) in rest {
                let right = try eval(rightExpr, frame)
                if !(try compare(op, left, right)) { return .bool(false) }
                left = right
            }
            return .bool(true)
        case .boolOp(let op, let a, let b):
            let l = try eval(a, frame)
            if op == "and" { return l.truthy ? try eval(b, frame) : l }
            return l.truthy ? l : try eval(b, frame)
        case .ifExp(let cond, let a, let b):
            return try eval(cond, frame).truthy ? try eval(a, frame) : try eval(b, frame)
        case .fstring(let parts):
            var out = ""
            for part in parts {
                switch part {
                case .text(let t): out += t
                case .expr(let e, let decimals):
                    let v = try eval(e, frame)
                    if let decimals, let n = v.number { out += String(format: "%.\(decimals)f", n) } else { out += v.text }
                }
            }
            return .str(out)
        case .listComp(let element, let target, let iterExpr, let cond):
            var out: [Value] = []
            for item in try iterate(try eval(iterExpr, frame)) {
                try spend()
                try assign(target, item, frame)
                if let cond, !(try eval(cond, frame).truthy) { continue }
                out.append(try eval(element, frame))
            }
            return .list(PyList(out))
        case .slice(let valueExpr, let startExpr, let stopExpr, let stepExpr):
            let v = try eval(valueExpr, frame)
            func bound(_ e: Expr?) throws -> Int? {
                guard let e else { return nil }
                let b = try eval(e, frame)
                if case .none = b { return nil }
                guard let i = intValue(b) else { throw err("TypeError: slice positions must be whole numbers.") }
                return i
            }
            let step = try bound(stepExpr) ?? 1
            guard step != 0 else { throw err("ValueError: slice step can't be 0.") }
            func pick<T>(_ items: [T]) throws -> [T] {
                let n = items.count
                func clamp(_ i: Int, _ lo: Int, _ hi: Int) -> Int { min(max(i < 0 ? i + n : i, lo), hi) }
                var out: [T] = []
                if step > 0 {
                    let a = try bound(startExpr).map { clamp($0, 0, n) } ?? 0
                    let b = try bound(stopExpr).map { clamp($0, 0, n) } ?? n
                    var i = a
                    while i < b { out.append(items[i]); i += step }
                } else {
                    let a = try bound(startExpr).map { clamp($0, -1, n - 1) } ?? n - 1
                    let b = try bound(stopExpr).map { clamp($0, -1, n - 1) } ?? -1
                    var i = a
                    while i > b { out.append(items[i]); i += step }
                }
                return out
            }
            switch v {
            case .list(let l): return .list(PyList(try pick(l.items)))
            case .tuple(let t): return .tuple(try pick(t))
            case .str(let str): return .str(String(try pick(Array(str))))
            default: throw err("TypeError: a \(v.typeName) can't be sliced.")
            }
        case .call(let fnExpr, let argExprs, let kwExprs):
            let fn = try eval(fnExpr, frame)
            let args = try argExprs.map { try eval($0, frame) }
            var kwargs: [String: Value] = [:]
            for (k, v) in kwExprs { kwargs[k] = try eval(v, frame) }
            return try call(fn, args, kwargs)
        case .attr(let objExpr, let name):
            return try attribute(try eval(objExpr, frame), name)
        case .index(let cExpr, let iExpr):
            let c = try eval(cExpr, frame)
            let idx = try eval(iExpr, frame)
            switch c {
            case .list(let l): return l.items[try listIndex(idx, count: l.items.count)]
            case .tuple(let t): return t[try listIndex(idx, count: t.count)]
            case .str(let s):
                let chars = Array(s)
                return .str(String(chars[try listIndex(idx, count: chars.count)]))
            case .dict(let d):
                guard let v = d.get(idx) else { throw err("KeyError: \(idx.repr) isn't in this dictionary.") }
                return v
            default:
                throw err("TypeError: a \(c.typeName) can't be indexed with [ ].")
            }
        }
    }

    private func listIndex(_ v: Value, count: Int) throws -> Int {
        guard case .int(var i) = v else { throw err("TypeError: list positions must be whole numbers, not \(v.typeName).") }
        if i < 0 { i += count }
        guard i >= 0, i < count else { throw err("IndexError: position \(i) is outside the list (it has \(count) items).") }
        return i
    }

    func iterate(_ v: Value) throws -> [Value] {
        switch v {
        case .list(let l): return l.items
        case .tuple(let t): return t
        case .str(let s): return s.map { .str(String($0)) }
        case .dict(let d): return d.keys
        default: throw err("TypeError: can't loop over a \(v.typeName).")
        }
    }

    func call(_ fn: Value, _ args: [Value], _ kwargs: [String: Value]) throws -> Value {
        switch fn {
        case .builtin(let b):
            return try b.call(args, kwargs)
        case .function(let f):
            depth += 1
            defer { depth -= 1 }
            guard depth < 150 else { throw err("RecursionError: too many functions calling each other.") }
            let frame = Frame(name: f.name)
            frameStack.append(frame)
            defer { frameStack.removeLast() }
            guard args.count <= f.params.count else {
                throw err("TypeError: \(f.name)() takes \(f.params.count) argument\(f.params.count == 1 ? "" : "s") but got \(args.count).")
            }
            for (i, p) in f.params.enumerated() {
                frame.order.append(p.name)
                if i < args.count { frame.locals[p.name] = args[i] }
                else if let v = kwargs[p.name] { frame.locals[p.name] = v }
                else if i < f.defaults.count, let d = f.defaults[i] { frame.locals[p.name] = d }
                else { throw err("TypeError: \(f.name)() is missing the `\(p.name)` argument.") }
            }
            for k in kwargs.keys where !f.params.contains(where: { $0.name == k }) {
                throw err("TypeError: \(f.name)() has no parameter called `\(k)`.")
            }
            let callerLine = line
            let flow = try exec(f.body, frame)
            line = callerLine
            if case .ret(let v) = flow { return v }
            return .none
        default:
            throw err("TypeError: a \(fn.typeName) can't be called like a function.")
        }
    }

    // MARK: Operators

    func intValue(_ v: Value) -> Int? {
        switch v {
        case .int(let i): return i
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }

    func binary(_ op: String, _ a: Value, _ b: Value) throws -> Value {
        if let x = intValue(a), let y = intValue(b) {
            switch op {
            case "+": let r = x.addingReportingOverflow(y); if r.overflow { throw err("OverflowError: that number got too big.") }; return .int(r.partialValue)
            case "-": let r = x.subtractingReportingOverflow(y); if r.overflow { throw err("OverflowError: that number got too big.") }; return .int(r.partialValue)
            case "*": let r = x.multipliedReportingOverflow(by: y); if r.overflow { throw err("OverflowError: that number got too big.") }; return .int(r.partialValue)
            case "/": guard y != 0 else { throw err("ZeroDivisionError: can't divide by zero.") }; return .float(Double(x) / Double(y))
            case "//":
                guard y != 0 else { throw err("ZeroDivisionError: can't divide by zero.") }
                var q = x / y
                if (x % y != 0) && ((x < 0) != (y < 0)) { q -= 1 }
                return .int(q)
            case "%":
                guard y != 0 else { throw err("ZeroDivisionError: can't divide by zero.") }
                let m = x % y
                return .int(m != 0 && (m < 0) != (y < 0) ? m + y : m)
            case "**":
                if y >= 0 {
                    var result = 1
                    for _ in 0..<min(y, 64) {
                        let r = result.multipliedReportingOverflow(by: x)
                        if r.overflow { throw err("OverflowError: that number got too big.") }
                        result = r.partialValue
                    }
                    return .int(result)
                }
                return .float(pow(Double(x), Double(y)))
            default: break
            }
        }
        if let x = a.number, let y = b.number {
            switch op {
            case "+": return .float(x + y)
            case "-": return .float(x - y)
            case "*": return .float(x * y)
            case "/": guard y != 0 else { throw err("ZeroDivisionError: can't divide by zero.") }; return .float(x / y)
            case "//": guard y != 0 else { throw err("ZeroDivisionError: can't divide by zero.") }; return .float((x / y).rounded(.down))
            case "%":
                guard y != 0 else { throw err("ZeroDivisionError: can't divide by zero.") }
                let m = x.truncatingRemainder(dividingBy: y)
                return .float(m != 0 && (m < 0) != (y < 0) ? m + y : m)
            case "**": return .float(pow(x, y))
            default: break
            }
        }
        switch (op, a, b) {
        case ("+", .str(let x), .str(let y)): return .str(x + y)
        case ("+", .list(let x), .list(let y)): return .list(PyList(x.items + y.items))
        case ("+", .tuple(let x), .tuple(let y)): return .tuple(x + y)
        case ("*", .str(let s), .int(let n)), ("*", .int(let n), .str(let s)):
            guard n <= 10_000 else { throw err("That string would be too long.") }
            return .str(String(repeating: s, count: max(0, n)))
        case ("*", .list(let l), .int(let n)), ("*", .int(let n), .list(let l)):
            guard n * l.items.count <= 100_000 else { throw err("That list would be too long.") }
            return .list(PyList(Array([[Value]](repeating: l.items, count: max(0, n)).joined())))
        case ("+", .str, _), ("+", _, .str):
            throw err("TypeError: can't add \(a.typeName) and \(b.typeName). Use str(x) to turn a number into text first.")
        default:
            throw err("TypeError: can't use \(op) with \(a.typeName) and \(b.typeName).")
        }
    }

    private func compare(_ op: String, _ a: Value, _ b: Value) throws -> Bool {
        switch op {
        case "==": return a.equals(b)
        case "!=": return !a.equals(b)
        case "in", "not in":
            let found: Bool
            switch b {
            case .list(let l): found = l.items.contains { $0.equals(a) }
            case .tuple(let t): found = t.contains { $0.equals(a) }
            case .dict(let d): found = d.index(of: a) != nil
            case .str(let s):
                guard case .str(let sub) = a else { throw err("TypeError: `in` with text needs text on the left.") }
                found = s.contains(sub)
            default: throw err("TypeError: can't use `in` with a \(b.typeName).")
            }
            return op == "in" ? found : !found
        case "is", "is not":
            let same: Bool
            switch (a, b) {
            case (.none, .none): same = true
            case (.bool(let x), .bool(let y)): same = x == y
            case (.list(let x), .list(let y)): same = x === y
            case (.dict(let x), .dict(let y)): same = x === y
            case (.object(let x), .object(let y)): same = x === y
            default: same = false
            }
            return op == "is" ? same : !same
        default:
            break
        }
        if let x = a.number, let y = b.number {
            switch op {
            case "<": return x < y
            case ">": return x > y
            case "<=": return x <= y
            case ">=": return x >= y
            default: break
            }
        }
        if case .str(let x) = a, case .str(let y) = b {
            switch op {
            case "<": return x < y
            case ">": return x > y
            case "<=": return x <= y
            case ">=": return x >= y
            default: break
            }
        }
        if case .none = a { throw err("TypeError: can't compare None with \(op). Check for None first with `is None`.") }
        if case .none = b { throw err("TypeError: can't compare with None using \(op). Check for None first with `is None`.") }
        throw err("TypeError: can't compare \(a.typeName) and \(b.typeName) with \(op).")
    }

    // MARK: Attributes & methods

    private func attribute(_ v: Value, _ name: String) throws -> Value {
        switch v {
        case .object(let o):
            if let a = o.get(name) { return a }
            throw err("AttributeError: \(o.typeName) has no `.\(name)`. It has: \(o.attrs.joined(separator: ", ")).")
        case .list(let l):
            switch name {
            case "append": return method(name) { args in try self.need(args, 1, "append"); l.items.append(args[0]); return .none }
            case "pop": return method(name) { args in
                guard !l.items.isEmpty else { throw self.err("IndexError: can't pop from an empty list.") }
                if let a = args.first { return l.items.remove(at: try self.listIndex(a, count: l.items.count)) }
                return l.items.removeLast()
            }
            case "insert": return method(name) { args in
                try self.need(args, 2, "insert")
                guard case .int(var i) = args[0] else { throw self.err("TypeError: insert() needs a whole-number position.") }
                if i < 0 { i += l.items.count }
                l.items.insert(args[1], at: min(max(0, i), l.items.count)); return .none
            }
            case "remove": return method(name) { args in
                try self.need(args, 1, "remove")
                guard let i = l.items.firstIndex(where: { $0.equals(args[0]) }) else { throw self.err("ValueError: \(args[0].repr) isn't in the list.") }
                l.items.remove(at: i); return .none
            }
            case "index": return method(name) { args in
                try self.need(args, 1, "index")
                guard let i = l.items.firstIndex(where: { $0.equals(args[0]) }) else { throw self.err("ValueError: \(args[0].repr) isn't in the list.") }
                return .int(i)
            }
            case "count": return method(name) { args in try self.need(args, 1, "count"); return .int(l.items.filter { $0.equals(args[0]) }.count) }
            case "extend": return method(name) { args in
                try self.need(args, 1, "extend")
                l.items += try self.iterate(args[0]); return .none
            }
            case "copy": return method(name) { _ in .list(PyList(l.items)) }
            case "reverse": return method(name) { _ in l.items.reverse(); return .none }
            case "clear": return method(name) { _ in l.items.removeAll(); return .none }
            case "sort": return method(name) { _ in l.items = try self.sorted(l.items); return .none }
            default: break
            }
        case .dict(let d):
            switch name {
            case "get": return method(name) { args in
                guard let k = args.first else { throw self.err("TypeError: get() needs a key.") }
                return d.get(k) ?? (args.count > 1 ? args[1] : Value.none)
            }
            case "keys": return method(name) { _ in .list(PyList(d.keys)) }
            case "values": return method(name) { _ in .list(PyList(d.values)) }
            case "items": return method(name) { _ in .list(PyList(zip(d.keys, d.values).map { .tuple([$0, $1]) })) }
            default: break
            }
        case .str(let s):
            switch name {
            case "join": return method(name) { args in
                try self.need(args, 1, "join")
                return .str(try self.iterate(args[0]).map(\.text).joined(separator: s))
            }
            case "upper": return method(name) { _ in .str(s.uppercased()) }
            case "lower": return method(name) { _ in .str(s.lowercased()) }
            case "strip": return method(name) { _ in .str(s.trimmingCharacters(in: .whitespaces)) }
            case "startswith": return method(name) { args in
                guard case .str(let p)? = args.first else { throw self.err("TypeError: startswith() needs text.") }
                return .bool(s.hasPrefix(p))
            }
            case "endswith": return method(name) { args in
                guard case .str(let p)? = args.first else { throw self.err("TypeError: endswith() needs text.") }
                return .bool(s.hasSuffix(p))
            }
            case "replace": return method(name) { args in
                guard args.count == 2, case .str(let a) = args[0], case .str(let b) = args[1] else { throw self.err("TypeError: replace() needs two pieces of text.") }
                return .str(s.replacingOccurrences(of: a, with: b))
            }
            case "split": return method(name) { args in
                if case .str(let sep)? = args.first { return .list(PyList(s.components(separatedBy: sep).map { .str($0) })) }
                return .list(PyList(s.split(separator: " ").map { .str(String($0)) }))
            }
            default: break
            }
        default:
            break
        }
        throw err("AttributeError: a \(v.typeName) has no `.\(name)`.")
    }

    private func method(_ name: String, _ body: @escaping ([Value]) throws -> Value) -> Value {
        .builtin(PyBuiltin(name) { args, _ in try body(args) })
    }

    func need(_ args: [Value], _ n: Int, _ name: String) throws {
        guard args.count == n else { throw err("TypeError: \(name)() takes \(n) argument\(n == 1 ? "" : "s") but got \(args.count).") }
    }

    private func sorted(_ items: [Value]) throws -> [Value] {
        var failure: ScriptError?
        let out = items.sorted { a, b in
            do { return try compare("<", a, b) } catch { failure = error as? ScriptError; return false }
        }
        if let failure { throw failure }
        return out
    }

    // MARK: Standard builtins

    private func installStandardBuiltins() {
        func add(_ name: String, _ f: @escaping ([Value], [String: Value]) throws -> Value) {
            builtins[name] = .builtin(PyBuiltin(name, f))
        }
        add("print") { [unowned self] args, kw in
            let sep = kw["sep"]?.text ?? " "
            self.onPrint(args.map(\.text).joined(separator: sep))
            return .none
        }
        add("len") { [unowned self] args, _ in
            try self.need(args, 1, "len")
            switch args[0] {
            case .str(let s): return .int(s.count)
            case .list(let l): return .int(l.items.count)
            case .tuple(let t): return .int(t.count)
            case .dict(let d): return .int(d.keys.count)
            default: throw self.err("TypeError: a \(args[0].typeName) has no length.")
            }
        }
        add("range") { [unowned self] args, _ in
            let ints = try args.map { v -> Int in
                guard let i = self.intValue(v) else { throw self.err("TypeError: range() needs whole numbers, not \(v.typeName).") }
                return i
            }
            var start = 0, stop = 0, step = 1
            switch ints.count {
            case 1: stop = ints[0]
            case 2: start = ints[0]; stop = ints[1]
            case 3: start = ints[0]; stop = ints[1]; step = ints[2]
            default: throw self.err("TypeError: range() takes 1 to 3 numbers.")
            }
            guard step != 0 else { throw self.err("ValueError: range() step can't be 0.") }
            let count = step > 0 ? max(0, (stop - start + step - 1) / step) : max(0, (start - stop - step - 1) / -step)
            guard count <= 1_000_000 else { throw self.err("That range is too big (over a million numbers).") }
            return .list(PyList(stride(from: start, to: stop, by: step).map { .int($0) }))
        }
        add("abs") { [unowned self] args, _ in
            try self.need(args, 1, "abs")
            switch args[0] {
            case .int(let i): return .int(abs(i))
            case .float(let f): return .float(abs(f))
            default: throw self.err("TypeError: abs() needs a number.")
            }
        }
        add("min") { [unowned self] args, _ in try self.extreme(args, "min", less: true) }
        add("max") { [unowned self] args, _ in try self.extreme(args, "max", less: false) }
        add("sum") { [unowned self] args, _ in
            try self.need(args, 1, "sum")
            return try self.iterate(args[0]).reduce(Value.int(0)) { try self.binary("+", $0, $1) }
        }
        add("int") { [unowned self] args, _ in
            guard let v = args.first else { return .int(0) }
            switch v {
            case .int: return v
            case .bool(let b): return .int(b ? 1 : 0)
            case .float(let f): return .int(Int(f))
            case .str(let s):
                guard let i = Int(s.trimmingCharacters(in: .whitespaces)) else { throw self.err("ValueError: \(v.repr) isn't a whole number.") }
                return .int(i)
            default: throw self.err("TypeError: can't turn a \(v.typeName) into an int.")
            }
        }
        add("float") { [unowned self] args, _ in
            guard let v = args.first else { return .float(0) }
            if let n = v.number { return .float(n) }
            if case .str(let s) = v, let d = Double(s) { return .float(d) }
            throw self.err("ValueError: can't turn \(v.repr) into a float.")
        }
        add("str") { args, _ in .str(args.first?.text ?? "") }
        add("bool") { args, _ in .bool(args.first?.truthy ?? false) }
        add("list") { [unowned self] args, _ in .list(PyList(try args.first.map { try self.iterate($0) } ?? [])) }
        add("sorted") { [unowned self] args, _ in
            try self.need(args, 1, "sorted")
            return .list(PyList(try self.sorted(try self.iterate(args[0]))))
        }
        add("enumerate") { [unowned self] args, _ in
            guard let first = args.first else { throw self.err("TypeError: enumerate() needs a list.") }
            var start = 0
            if args.count > 1, let s = self.intValue(args[1]) { start = s }
            return .list(PyList(try self.iterate(first).enumerated().map { .tuple([.int($0.offset + start), $0.element]) }))
        }
        add("zip") { [unowned self] args, _ in
            let lists = try args.map { try self.iterate($0) }
            let n = lists.map(\.count).min() ?? 0
            return .list(PyList((0..<n).map { i in .tuple(lists.map { $0[i] }) }))
        }
        add("reversed") { [unowned self] args, _ in
            try self.need(args, 1, "reversed")
            return .list(PyList(try self.iterate(args[0]).reversed()))
        }
        add("any") { [unowned self] args, _ in
            try self.need(args, 1, "any")
            return .bool(try self.iterate(args[0]).contains { $0.truthy })
        }
        add("all") { [unowned self] args, _ in
            try self.need(args, 1, "all")
            return .bool(try self.iterate(args[0]).allSatisfy { $0.truthy })
        }
        add("round") { [unowned self] args, _ in
            guard let n = args.first?.number else { throw self.err("TypeError: round() needs a number.") }
            return .int(Int(n.rounded()))
        }
    }

    private func extreme(_ args: [Value], _ name: String, less: Bool) throws -> Value {
        let items = args.count == 1 ? try iterate(args[0]) : args
        guard var best = items.first else { throw err("ValueError: \(name)() of nothing.") }
        for v in items.dropFirst() {
            if try compare(less ? "<" : ">", v, best) { best = v }
        }
        return best
    }
}
