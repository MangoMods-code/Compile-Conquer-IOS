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

    /// - Parameters:
    ///   - source: the player's part of main.py (below the locked setup).
    ///   - lineOffset: how many setup lines come before it, so errors point at the right line.
    ///   - defined: every command and name the setup declares on this level.
    init(source: String, lineOffset: Int = 0, defined: Set<String>) throws {
        var out: [(line: Int, command: DroneCommand)] = []
        for (i, raw) in source.components(separatedBy: "\n").enumerated() {
            let lineNo = i + 1 + lineOffset
            var text = raw
            if let hash = text.firstIndex(of: "#") { text = String(text[..<hash]) }
            text = text.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            if raw.first == " " || raw.first == "\t" {
                throw ScriptError(line: lineNo, message: "Unexpected indent. Lines only need indenting inside loops, which unlock soon.")
            }
            // wait(3) runs three one-tick waits from the same line.
            if let ticks = try LineScript.waitTicks(text, line: lineNo, defined: defined) {
                for _ in 0..<ticks { out.append((line: lineNo, command: .wait)) }
                continue
            }
            let cmd = try LineScript.parse(text, line: lineNo, defined: defined)
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

    /// `wait()` -> 1, `wait(3)` -> 3, anything else -> nil (not a wait call).
    private static func waitTicks(_ text: String, line: Int, defined: Set<String>) throws -> Int? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard compact.hasPrefix("wait("), compact.hasSuffix(")"), defined.contains("wait") else { return nil }
        var arg = String(compact.dropFirst(5).dropLast())
        if arg.hasPrefix("ticks=") { arg = String(arg.dropFirst(6)) }
        if arg.isEmpty { return 1 }
        guard let n = Int(arg) else {
            throw ScriptError(line: line, message: "wait() takes a whole number of ticks, like wait(3).")
        }
        guard n >= 1 else { throw ScriptError(line: line, message: "wait(\(n)) wouldn't wait at all. Use 1 or more ticks.") }
        guard n <= 100 else { throw ScriptError(line: line, message: "wait(\(n)) is a long nap. Keep it to 100 ticks or less.") }
        return n
    }

    private static func parse(_ text: String, line: Int, defined: Set<String>) throws -> DroneCommand {
        let firstWord = text.prefix { $0.isLetter || $0 == "_" }
        if blockKeywords.contains(String(firstWord)) {
            throw ScriptError(line: line, message: "`\(firstWord)` isn't unlocked yet. Loops and if-statements arrive in the next chapter update.")
        }
        if text.hasPrefix("from ") || text.hasPrefix("import ") {
            throw ScriptError(line: line, message: "No imports needed: everything is already defined in the setup above.")
        }
        if text.contains("="), !text.contains("==") {
            throw ScriptError(line: line, message: "Making your own variables unlocks in the next update. For now, call the commands defined in the setup.")
        }
        guard let open = text.firstIndex(of: "("), text.hasSuffix(")") else {
            if defined.contains(text), commandNames.contains(text) {
                throw ScriptError(line: line, message: "`\(text)` is a function. Add brackets to call it: \(text)()")
            }
            if defined.contains(text) || ["field", "drone", "stock", "GOAL", "GROW_TIME"].contains(text) {
                throw ScriptError(line: line, message: "`\(text)` is a variable from the setup. On its own line it doesn't do anything.")
            }
            throw ScriptError(line: line, message: "I don't understand `\(text)`. Calls look like name() or name(something).")
        }
        let name = text[..<open].trimmingCharacters(in: .whitespaces)
        let arg = text[text.index(after: open)..<text.index(before: text.endIndex)].trimmingCharacters(in: .whitespaces)

        if commandNames.contains(name), !defined.contains(name) {
            throw ScriptError(line: line, message: "NameError: `\(name)` isn't defined in this level's setup.")
        }
        func checkName(_ n: String) throws {
            if !defined.contains(n) {
                throw ScriptError(line: line, message: "NameError: `\(n)` isn't defined in this level's setup.")
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
            let known = commandNames.filter { defined.contains($0) }
            let suggestion = known.min { editDistance($0, name) < editDistance($1, name) }
            let hint = suggestion.map { editDistance($0, name) <= 2 ? " Did you mean \($0)()?" : "" } ?? ""
            throw ScriptError(line: line, message: "NameError: `\(name)` isn't defined in the setup.\(hint)")
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
