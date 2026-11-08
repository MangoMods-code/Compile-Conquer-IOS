import Foundation

final class PyList { var items: [Value]; init(_ items: [Value]) { self.items = items } }

final class PyDict {
    var keys: [Value] = []
    var values: [Value] = []
    init(_ pairs: [(Value, Value)] = []) { for (k, v) in pairs { set(k, v) } }
    func index(of key: Value) -> Int? { keys.firstIndex { $0.equals(key) } }
    func get(_ key: Value) -> Value? { index(of: key).map { values[$0] } }
    func set(_ key: Value, _ value: Value) {
        if let i = index(of: key) { values[i] = value } else { keys.append(key); values.append(value) }
    }
}

final class PyFunction {
    let name: String
    let params: [Param]
    let body: [Stmt]
    var defaults: [Value?] = []
    init(name: String, params: [Param], body: [Stmt]) { self.name = name; self.params = params; self.body = body }
}

/// A function implemented in Swift (game commands, print, len...).
final class PyBuiltin {
    let name: String
    let call: ([Value], [String: Value]) throws -> Value
    init(_ name: String, _ call: @escaping ([Value], [String: Value]) throws -> Value) { self.name = name; self.call = call }
}

/// A read-only game object like `drone` or `tile`, whose attributes are read live.
final class PyObject {
    let typeName: String
    let attrs: [String]
    let get: (String) -> Value?
    init(_ typeName: String, attrs: [String], get: @escaping (String) -> Value?) {
        self.typeName = typeName; self.attrs = attrs; self.get = get
    }
}

enum Value {
    case int(Int)
    case float(Double)
    case str(String)
    case bool(Bool)
    case none
    case list(PyList)
    case tuple([Value])
    case dict(PyDict)
    case function(PyFunction)
    case builtin(PyBuiltin)
    case object(PyObject)

    var typeName: String {
        switch self {
        case .int: return "int"
        case .float: return "float"
        case .str: return "str"
        case .bool: return "bool"
        case .none: return "NoneType"
        case .list: return "list"
        case .tuple: return "tuple"
        case .dict: return "dict"
        case .function, .builtin: return "function"
        case .object(let o): return o.typeName
        }
    }

    var truthy: Bool {
        switch self {
        case .int(let v): return v != 0
        case .float(let v): return v != 0
        case .str(let s): return !s.isEmpty
        case .bool(let b): return b
        case .none: return false
        case .list(let l): return !l.items.isEmpty
        case .tuple(let t): return !t.isEmpty
        case .dict(let d): return !d.keys.isEmpty
        default: return true
        }
    }

    var number: Double? {
        switch self {
        case .int(let v): return Double(v)
        case .float(let v): return v
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }

    func equals(_ other: Value) -> Bool {
        switch (self, other) {
        case (.str(let a), .str(let b)): return a == b
        case (.none, .none): return true
        case (.list(let a), .list(let b)): return a.items.count == b.items.count && zip(a.items, b.items).allSatisfy { $0.equals($1) }
        case (.tuple(let a), .tuple(let b)): return a.count == b.count && zip(a, b).allSatisfy { $0.equals($1) }
        case (.dict(let a), .dict(let b)): return a === b
        case (.object(let a), .object(let b)): return a === b
        case (.function(let a), .function(let b)): return a === b
        case (.builtin(let a), .builtin(let b)): return a === b
        default:
            if let x = number, let y = other.number { return x == y }
            return false
        }
    }

    /// Text for print() and str().
    var text: String {
        switch self {
        case .str(let s): return s
        default: return repr
        }
    }

    /// Text inside lists and in the console, Python-style.
    var repr: String {
        switch self {
        case .int(let v): return String(v)
        case .float(let v):
            if v.isFinite, v == v.rounded(), abs(v) < 1e15 { return String(format: "%.1f", v) }
            return String(v)
        case .str(let s): return "'" + s + "'"
        case .bool(let b): return b ? "True" : "False"
        case .none: return "None"
        case .list(let l): return "[" + l.items.map(\.repr).joined(separator: ", ") + "]"
        case .tuple(let t): return t.count == 1 ? "(" + t[0].repr + ",)" : "(" + t.map(\.repr).joined(separator: ", ") + ")"
        case .dict(let d): return "{" + zip(d.keys, d.values).map { $0.repr + ": " + $1.repr }.joined(separator: ", ") + "}"
        case .function(let f): return "<function \(f.name)>"
        case .builtin(let b): return "<function \(b.name)>"
        case .object(let o):
            let parts = o.attrs.compactMap { name in o.get(name).map { "\(name)=\($0.repr)" } }
            return "\(o.typeName)(" + parts.joined(separator: ", ") + ")"
        }
    }
}
