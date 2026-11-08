import Foundation

/// A compile error the editor can point at.
struct ScriptError: Error {
    let line: Int        // 1-based
    let message: String
}

/// Anything that can feed the drone one command at a time. The full Python interpreter
/// (loops, if, variables, functions) will be another implementation of this.
protocol DroneProgram {
    /// The next command and the source line it came from, or nil when the program has ended.
    mutating func next() throws -> (line: Int, command: DroneCommand)?
}

/// Milestone 1 language: one drone command per line, Python syntax, comments allowed.
struct LineScript: DroneProgram {
    private let steps: [(line: Int, command: DroneCommand)]
    private var index = 0

    static let commandNames = ["move", "till", "plant", "water", "harvest", "wait"]
    private static let blockKeywords = ["for", "while", "if", "elif", "else", "def", "return", "break", "continue"]

    init(source: String) throws {
        var out: [(line: Int, command: DroneCommand)] = []
        var imported: Set<String> = []
        for (i, raw) in source.components(separatedBy: "\n").enumerated() {
            let lineNo = i + 1
            var text = raw
            if let hash = text.firstIndex(of: "#") { text = String(text[..<hash]) }
            text = text.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            if raw.first == " " || raw.first == "\t" {
                throw ScriptError(line: lineNo, message: "Unexpected indent. Lines only need indenting inside loops, which unlock soon.")
            }
            if text.hasPrefix("from ") || text.hasPrefix("import ") {
                imported.formUnion(try LineScript.parseImport(text, line: lineNo))
                continue
            }
            let cmd = try LineScript.parse(text, line: lineNo, imported: imported)
            out.append((line: lineNo, command: cmd))
        }
        steps = out
    }

    mutating func next() throws -> (line: Int, command: DroneCommand)? {
        guard index < steps.count else { return nil }
        defer { index += 1 }
        return steps[index]
    }

    var isEmpty: Bool { steps.isEmpty }

    /// `from drone import plant, harvest` -> ["plant", "harvest"]
    private static func parseImport(_ text: String, line: Int) throws -> Set<String> {
        let parts = text.split(separator: " ", maxSplits: 3).map(String.init)
        guard parts.count == 4, parts[0] == "from", parts[2] == "import" else {
            throw ScriptError(line: line, message: "Imports look like: from drone import move, plant")
        }
        guard let available = DroneLibrary.modules[parts[1]] else {
            throw ScriptError(line: line, message: "There's no module called `\(parts[1])`. Use drone or farm.")
        }
        var names: Set<String> = []
        for n in parts[3].split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            guard available.contains(n) else {
                throw ScriptError(line: line, message: "`\(n)` isn't in \(parts[1]).py.")
            }
            names.insert(n)
        }
        return names
    }

    private static func parse(_ text: String, line: Int, imported: Set<String>) throws -> DroneCommand {
        let firstWord = text.prefix { $0.isLetter || $0 == "_" }
        if blockKeywords.contains(String(firstWord)) {
            throw ScriptError(line: line, message: "`\(firstWord)` isn't unlocked yet. Loops and if-statements arrive in the next chapter update.")
        }
        guard let open = text.firstIndex(of: "("), text.hasSuffix(")") else {
            if commandNames.contains(text) {
                throw ScriptError(line: line, message: "Add brackets to run a command: \(text)()")
            }
            throw ScriptError(line: line, message: "I don't understand `\(text)`. Commands look like move(North) or harvest().")
        }
        let name = text[..<open].trimmingCharacters(in: .whitespaces)
        let arg = text[text.index(after: open)..<text.index(before: text.endIndex)].trimmingCharacters(in: .whitespaces)

        if commandNames.contains(name), !imported.contains(name) {
            throw ScriptError(line: line, message: "`\(name)` isn't imported, so Python doesn't know it yet. It unlocks in a later level.")
        }
        func checkName(_ n: String) throws {
            if DroneLibrary.modules["farm"]!.contains(n), !imported.contains(n) {
                throw ScriptError(line: line, message: "`\(n)` isn't imported from farm.py on this level.")
            }
        }

        func noArgs(_ cmd: DroneCommand) throws -> DroneCommand {
            guard arg.isEmpty else { throw ScriptError(line: line, message: "\(name)() doesn't take anything inside the brackets.") }
            return cmd
        }

        switch name {
        case "move":
            guard !arg.isEmpty else { throw ScriptError(line: line, message: "move() needs a direction, like move(North).") }
            guard let d = Direction(rawValue: arg) else {
                if let d = Direction(name: arg) {
                    throw ScriptError(line: line, message: "Python cares about capitals: write \(d.rawValue), not \(arg).")
                }
                throw ScriptError(line: line, message: "`\(arg)` isn't a direction. Use North, East, South or West.")
            }
            try checkName(arg)
            return .move(d)
        case "plant":
            if arg.isEmpty { return .plant(.wheat) }
            guard let kind = CropKind(rawValue: arg) else {
                throw ScriptError(line: line, message: "There's no seed called `\(arg)` yet. Try plant() or plant(Wheat).")
            }
            try checkName(arg)
            return .plant(kind)
        case "till": return try noArgs(.till)
        case "water": return try noArgs(.water)
        case "harvest": return try noArgs(.harvest)
        case "wait": return try noArgs(.wait)
        default:
            let suggestion = commandNames.min { editDistance($0, name) < editDistance($1, name) } ?? "move"
            let hint = editDistance(suggestion, name) <= 2 ? " Did you mean \(suggestion)()?" : ""
            throw ScriptError(line: line, message: "`\(name)()` isn't a drone command.\(hint)")
        }
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
}
