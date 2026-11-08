import Foundation

/// A compile or runtime error the editor can point at.
struct ScriptError: Error {
    let line: Int        // 1-based line in main.py
    let message: String
}

enum TokKind: Equatable {
    case name(String)
    case int(Int)
    case float(Double)
    case string(String)
    case op(String)
    case newline
    case indent
    case dedent
    case eof
}

struct Token {
    let kind: TokKind
    let line: Int
}

/// Turns Python source into tokens, including INDENT/DEDENT for blocks.
enum PyLexer {
    private static let ops3: Set<String> = ["**=", "//="]
    private static let ops2: Set<String> = ["==", "!=", "<=", ">=", "//", "**", "+=", "-=", "*=", "/=", "%=", "->"]
    private static let ops1: Set<Character> = ["+", "-", "*", "/", "%", "<", ">", "=", "(", ")", "[", "]", "{", "}", ",", ":", "."]

    static func tokenize(_ source: String, lineOffset: Int) throws -> [Token] {
        var tokens: [Token] = []
        var indents = [0]
        var depth = 0
        let lines = source.components(separatedBy: "\n")

        for (i, rawLine) in lines.enumerated() {
            let lineNo = i + 1 + lineOffset
            let chars = Array(rawLine)
            var p = 0

            if depth == 0 {
                // Measure indentation.
                var width = 0
                while p < chars.count, chars[p] == " " || chars[p] == "\t" {
                    width += chars[p] == "\t" ? 4 : 1
                    p += 1
                }
                // Blank or comment-only lines don't affect blocks.
                if p >= chars.count || chars[p] == "#" || chars[p] == "\r" { continue }
                if width > indents.last! {
                    indents.append(width)
                    tokens.append(Token(kind: .indent, line: lineNo))
                } else if width < indents.last! {
                    while width < indents.last! {
                        indents.removeLast()
                        tokens.append(Token(kind: .dedent, line: lineNo))
                    }
                    if width != indents.last! {
                        throw ScriptError(line: lineNo, message: "IndentationError: this line's indent doesn't line up with any block above it.")
                    }
                }
            }

            while p < chars.count {
                let c = chars[p]
                if c == " " || c == "\t" || c == "\r" { p += 1; continue }
                if c == "#" { break }

                if c.isNumber {
                    var s = ""
                    var isFloat = false
                    while p < chars.count, chars[p].isNumber || chars[p] == "_" || (chars[p] == "." && !isFloat) {
                        if chars[p] == "." {
                            // "3." followed by a name is an attribute, not a float
                            if p + 1 < chars.count, chars[p + 1].isLetter { break }
                            isFloat = true
                        }
                        if chars[p] != "_" { s.append(chars[p]) }
                        p += 1
                    }
                    if isFloat {
                        tokens.append(Token(kind: .float(Double(s) ?? 0), line: lineNo))
                    } else {
                        guard let v = Int(s) else { throw ScriptError(line: lineNo, message: "That number is too big.") }
                        tokens.append(Token(kind: .int(v), line: lineNo))
                    }
                    continue
                }

                if c.isLetter || c == "_" {
                    var s = ""
                    while p < chars.count, chars[p].isLetter || chars[p].isNumber || chars[p] == "_" {
                        s.append(chars[p]); p += 1
                    }
                    tokens.append(Token(kind: .name(s), line: lineNo))
                    continue
                }

                if c == "\"" || c == "'" {
                    let quote = c
                    p += 1
                    var s = ""
                    var closed = false
                    while p < chars.count {
                        let ch = chars[p]
                        if ch == "\\", p + 1 < chars.count {
                            let n = chars[p + 1]
                            switch n {
                            case "n": s.append("\n")
                            case "t": s.append("\t")
                            default: s.append(n)
                            }
                            p += 2
                            continue
                        }
                        if ch == quote { closed = true; p += 1; break }
                        s.append(ch)
                        p += 1
                    }
                    if !closed { throw ScriptError(line: lineNo, message: "SyntaxError: this string is missing its closing \(quote).") }
                    tokens.append(Token(kind: .string(s), line: lineNo))
                    continue
                }

                if c == "“" || c == "”" || c == "‘" || c == "’" {
                    throw ScriptError(line: lineNo, message: "SyntaxError: curly quotes aren't Python quotes. Use the straight \" key on the key row.")
                }

                if p + 2 < chars.count, ops3.contains(String(chars[p...(p + 2)])) {
                    tokens.append(Token(kind: .op(String(chars[p...(p + 2)])), line: lineNo))
                    p += 3
                    continue
                }
                if p + 1 < chars.count, ops2.contains(String(chars[p...(p + 1)])) {
                    tokens.append(Token(kind: .op(String(chars[p...(p + 1)])), line: lineNo))
                    p += 2
                    continue
                }
                if ops1.contains(c) {
                    if "([{".contains(c) { depth += 1 }
                    if ")]}".contains(c) { depth = max(0, depth - 1) }
                    tokens.append(Token(kind: .op(String(c)), line: lineNo))
                    p += 1
                    continue
                }
                if c == "!" {
                    throw ScriptError(line: lineNo, message: "SyntaxError: Python uses `not` instead of `!`, and `!=` for not-equal.")
                }
                if c == "&" || c == "|" {
                    throw ScriptError(line: lineNo, message: "SyntaxError: Python uses `and` / `or` instead of && and ||.")
                }
                throw ScriptError(line: lineNo, message: "SyntaxError: unexpected character `\(c)`.")
            }

            if depth == 0, let last = tokens.last, last.kind != .newline, last.kind != .indent, last.kind != .dedent {
                tokens.append(Token(kind: .newline, line: lineNo))
            } else if depth == 0, let last = tokens.last, last.kind == .indent || last.kind == .dedent {
                // A line that only produced indent/dedent tokens has content; it always ends in newline above.
            }
        }

        let endLine = lines.count + lineOffset
        if let last = tokens.last, last.kind != .newline, last.kind != .dedent {
            tokens.append(Token(kind: .newline, line: endLine))
        }
        while indents.count > 1 {
            indents.removeLast()
            tokens.append(Token(kind: .dedent, line: endLine))
        }
        tokens.append(Token(kind: .eof, line: endLine))
        return tokens
    }
}
