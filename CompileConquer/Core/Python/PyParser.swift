import Foundation

indirect enum Expr {
    case int(Int)
    case float(Double)
    case str(String)
    case bool(Bool)
    case none
    case name(String)
    case list([Expr])
    case tuple([Expr])
    case dict([(Expr, Expr)])
    case unary(String, Expr)
    case binary(String, Expr, Expr)
    case compare(Expr, [(String, Expr)])
    case boolOp(String, Expr, Expr)
    case call(Expr, [Expr], [(String, Expr)])
    case attr(Expr, String)
    case index(Expr, Expr)
    case ifExp(Expr, Expr, Expr)   // cond, then, else
}

struct Param {
    let name: String
    let defaultValue: Expr?
}

indirect enum StmtKind {
    case expr(Expr)
    case assign(Expr, Expr)
    case augAssign(Expr, String, Expr)
    case ifs([(Expr, [Stmt])], [Stmt]?)
    case whileLoop(Expr, [Stmt])
    case forLoop(Expr, Expr, [Stmt])
    case def(String, [Param], [Stmt])
    case ret(Expr?)
    case brk
    case cont
    case pass
    case global([String])
}

struct Stmt {
    let line: Int
    let kind: StmtKind
}

/// Recursive-descent parser for the Python subset the game supports.
struct PyParser {
    private let toks: [Token]
    private var i = 0

    init(_ tokens: [Token]) { toks = tokens }

    static func parse(_ source: String, lineOffset: Int) throws -> [Stmt] {
        var p = PyParser(try PyLexer.tokenize(source, lineOffset: lineOffset))
        return try p.file()
    }

    // MARK: Helpers

    private var tok: Token { toks[i] }
    private var line: Int { toks[i].line }

    private func isOp(_ s: String) -> Bool { if case .op(let o) = tok.kind { return o == s }; return false }
    private func isName(_ s: String) -> Bool { if case .name(let n) = tok.kind { return n == s }; return false }

    private mutating func advance() { if i < toks.count - 1 { i += 1 } }

    private mutating func expectOp(_ s: String, _ what: String) throws {
        guard isOp(s) else { throw err("SyntaxError: expected \(what).") }
        advance()
    }

    private mutating func expectName() throws -> String {
        guard case .name(let n) = tok.kind, !PyParser.keywords.contains(n) else { throw err("SyntaxError: expected a name here.") }
        advance()
        return n
    }

    private func err(_ msg: String) -> ScriptError { ScriptError(line: line, message: msg) }

    static let keywords: Set<String> = ["if", "elif", "else", "while", "for", "in", "def", "return", "break", "continue",
                                        "pass", "and", "or", "not", "is", "True", "False", "None", "global", "import", "from",
                                        "class", "lambda", "try", "except", "with", "as", "yield", "del", "nonlocal", "raise"]

    // MARK: Statements

    private mutating func file() throws -> [Stmt] {
        var out: [Stmt] = []
        while tok.kind != .eof {
            if tok.kind == .newline { advance(); continue }
            if tok.kind == .indent { throw err("IndentationError: unexpected indent. Only lines inside a block (after a `:`) are indented.") }
            if tok.kind == .dedent { advance(); continue }
            out.append(try statement())
        }
        return out
    }

    private mutating func block() throws -> [Stmt] {
        try expectOp(":", "a `:` at the end of this line")
        if tok.kind != .newline {
            // one-liner: `if x: move(North)`
            return [try simpleStatement()]
        }
        advance()
        guard tok.kind == .indent else { throw err("IndentationError: expected an indented block after the `:`.") }
        advance()
        var out: [Stmt] = []
        while tok.kind != .dedent && tok.kind != .eof {
            if tok.kind == .newline { advance(); continue }
            out.append(try statement())
        }
        if tok.kind == .dedent { advance() }
        return out
    }

    private mutating func statement() throws -> Stmt {
        let ln = line
        if case .name(let n) = tok.kind {
            switch n {
            case "if":
                advance()
                var branches: [(Expr, [Stmt])] = []
                let cond = try expression()
                branches.append((cond, try block()))
                var elseBody: [Stmt]?
                while true {
                    if isName("elif") {
                        advance()
                        let c = try expression()
                        branches.append((c, try block()))
                    } else if isName("else") {
                        advance()
                        elseBody = try block()
                        break
                    } else { break }
                }
                return Stmt(line: ln, kind: .ifs(branches, elseBody))
            case "elif", "else":
                throw err("SyntaxError: `\(n)` needs to come right after an `if` block at the same indent.")
            case "while":
                advance()
                let cond = try expression()
                return Stmt(line: ln, kind: .whileLoop(cond, try block()))
            case "for":
                advance()
                let target = try targetList()
                guard isName("in") else { throw err("SyntaxError: a for loop looks like: for i in range(5):") }
                advance()
                let iter = try exprList()
                return Stmt(line: ln, kind: .forLoop(target, iter, try block()))
            case "def":
                advance()
                let fname = try expectName()
                try expectOp("(", "`(` after the function name")
                var params: [Param] = []
                while !isOp(")") {
                    let pname = try expectName()
                    var def: Expr?
                    if isOp("=") { advance(); def = try expression() }
                    params.append(Param(name: pname, defaultValue: def))
                    if isOp(",") { advance() } else { break }
                }
                try expectOp(")", "`)` to close the parameter list")
                return Stmt(line: ln, kind: .def(fname, params, try block()))
            case "class", "try", "with", "lambda", "yield":
                throw err("`\(n)` isn't part of this game's Python yet.")
            default:
                break
            }
        }
        let s = try simpleStatement()
        return s
    }

    private mutating func simpleStatement() throws -> Stmt {
        let ln = line
        var result: Stmt
        if case .name(let n) = tok.kind {
            switch n {
            case "return":
                advance()
                if tok.kind == .newline || tok.kind == .eof { result = Stmt(line: ln, kind: .ret(nil)) }
                else { result = Stmt(line: ln, kind: .ret(try exprList())) }
                try endOfLine()
                return result
            case "pass": advance(); try endOfLine(); return Stmt(line: ln, kind: .pass)
            case "break": advance(); try endOfLine(); return Stmt(line: ln, kind: .brk)
            case "continue": advance(); try endOfLine(); return Stmt(line: ln, kind: .cont)
            case "global":
                advance()
                var names = [try expectName()]
                while isOp(",") { advance(); names.append(try expectName()) }
                try endOfLine()
                return Stmt(line: ln, kind: .global(names))
            case "import", "from":
                throw err("No imports needed: everything you can use is already defined in the setup above.")
            default: break
            }
        }

        let first = try exprList()
        if isOp("=") {
            advance()
            let value = try exprList()
            if isOp("=") { throw err("Chained assignment (a = b = 1) isn't supported. Assign one at a time.") }
            try checkTarget(first)
            result = Stmt(line: ln, kind: .assign(first, value))
        } else if case .op(let o) = tok.kind, ["+=", "-=", "*=", "/=", "//=", "%=", "**="].contains(o) {
            advance()
            let value = try expression()
            try checkTarget(first)
            result = Stmt(line: ln, kind: .augAssign(first, String(o.dropLast()), value))
        } else {
            result = Stmt(line: ln, kind: .expr(first))
        }
        try endOfLine()
        return result
    }

    private func checkTarget(_ e: Expr) throws {
        switch e {
        case .name, .attr, .index: return
        case .tuple(let items): for item in items { try checkTarget(item) }
        default: throw err("SyntaxError: you can only assign to a variable name, like x = 5.")
        }
    }

    private mutating func endOfLine() throws {
        if tok.kind == .newline { advance(); return }
        if tok.kind == .eof || tok.kind == .dedent { return }
        if isOp("=") { throw err("SyntaxError: use == to compare, = to assign.") }
        throw err("SyntaxError: unexpected text at the end of this line.")
    }

    private mutating func targetList() throws -> Expr {
        var items = [Expr.name(try expectName())]
        while isOp(",") { advance(); items.append(.name(try expectName())) }
        return items.count == 1 ? items[0] : .tuple(items)
    }

    // MARK: Expressions

    private mutating func exprList() throws -> Expr {
        let first = try expression()
        guard isOp(",") else { return first }
        var items = [first]
        while isOp(",") {
            advance()
            if tok.kind == .newline || isOp("=") || isOp(")") { break }
            items.append(try expression())
        }
        return .tuple(items)
    }

    private mutating func expression() throws -> Expr {
        let value = try orExpr()
        if isName("if") {
            advance()
            let cond = try orExpr()
            guard isName("else") else { throw err("SyntaxError: a one-line if needs an else: a if cond else b") }
            advance()
            let other = try expression()
            return .ifExp(cond, value, other)
        }
        return value
    }

    private mutating func orExpr() throws -> Expr {
        var left = try andExpr()
        while isName("or") { advance(); left = .boolOp("or", left, try andExpr()) }
        return left
    }

    private mutating func andExpr() throws -> Expr {
        var left = try notExpr()
        while isName("and") { advance(); left = .boolOp("and", left, try notExpr()) }
        return left
    }

    private mutating func notExpr() throws -> Expr {
        if isName("not") { advance(); return .unary("not", try notExpr()) }
        return try comparison()
    }

    private mutating func comparison() throws -> Expr {
        let left = try arith()
        var ops: [(String, Expr)] = []
        while true {
            var op: String?
            if case .op(let o) = tok.kind, ["==", "!=", "<", ">", "<=", ">="].contains(o) { op = o; advance() }
            else if isName("in") { op = "in"; advance() }
            else if isName("not") {
                advance()
                guard isName("in") else { throw err("SyntaxError: did you mean `not in`?") }
                advance(); op = "not in"
            } else if isName("is") {
                advance()
                if isName("not") { advance(); op = "is not" } else { op = "is" }
            }
            guard let o = op else { break }
            ops.append((o, try arith()))
        }
        return ops.isEmpty ? left : .compare(left, ops)
    }

    private mutating func arith() throws -> Expr {
        var left = try term()
        while isOp("+") || isOp("-") {
            guard case .op(let o) = tok.kind else { break }
            advance()
            left = .binary(o, left, try term())
        }
        return left
    }

    private mutating func term() throws -> Expr {
        var left = try factor()
        while isOp("*") || isOp("/") || isOp("//") || isOp("%") {
            guard case .op(let o) = tok.kind else { break }
            advance()
            left = .binary(o, left, try factor())
        }
        return left
    }

    private mutating func factor() throws -> Expr {
        if isOp("-") { advance(); return .unary("-", try factor()) }
        if isOp("+") { advance(); return .unary("+", try factor()) }
        return try power()
    }

    private mutating func power() throws -> Expr {
        let base = try postfix()
        if isOp("**") { advance(); return .binary("**", base, try factor()) }
        return base
    }

    private mutating func postfix() throws -> Expr {
        var e = try atom()
        while true {
            if isOp("(") {
                advance()
                var args: [Expr] = []
                var kwargs: [(String, Expr)] = []
                while !isOp(")") {
                    if case .name(let n) = tok.kind, i + 1 < toks.count, toks[i + 1].kind == .op("=") {
                        advance(); advance()
                        kwargs.append((n, try expression()))
                    } else {
                        if !kwargs.isEmpty { throw err("SyntaxError: plain arguments must come before name=value ones.") }
                        args.append(try expression())
                    }
                    if isOp(",") { advance() } else { break }
                }
                try expectOp(")", "`)` to close the call")
                e = .call(e, args, kwargs)
            } else if isOp("[") {
                advance()
                if isOp(":") { throw err("Slices like a[1:3] aren't supported yet.") }
                let idx = try expression()
                if isOp(":") { throw err("Slices like a[1:3] aren't supported yet.") }
                try expectOp("]", "`]`")
                e = .index(e, idx)
            } else if isOp(".") {
                advance()
                guard case .name(let n) = tok.kind else { throw err("SyntaxError: expected a name after the dot.") }
                advance()
                e = .attr(e, n)
            } else {
                return e
            }
        }
    }

    private mutating func atom() throws -> Expr {
        let t = tok
        switch t.kind {
        case .int(let v): advance(); return .int(v)
        case .float(let v): advance(); return .float(v)
        case .string(let s):
            advance()
            var str = s
            while case .string(let more) = tok.kind { str += more; advance() }
            return .str(str)
        case .name(let n):
            switch n {
            case "True": advance(); return .bool(true)
            case "False": advance(); return .bool(false)
            case "None": advance(); return .none
            default:
                if PyParser.keywords.contains(n) { throw err("SyntaxError: `\(n)` can't be used here.") }
                advance()
                return .name(n)
            }
        case .op("("):
            advance()
            if isOp(")") { advance(); return .tuple([]) }
            let first = try expression()
            if isOp(",") {
                var items = [first]
                while isOp(",") {
                    advance()
                    if isOp(")") { break }
                    items.append(try expression())
                }
                try expectOp(")", "`)`")
                return .tuple(items)
            }
            try expectOp(")", "`)` to close the bracket")
            return first
        case .op("["):
            advance()
            var items: [Expr] = []
            while !isOp("]") {
                items.append(try expression())
                if isOp(",") { advance() } else { break }
            }
            try expectOp("]", "`]` to close the list")
            return .list(items)
        case .op("{"):
            advance()
            var pairs: [(Expr, Expr)] = []
            while !isOp("}") {
                let k = try expression()
                try expectOp(":", "`:` between a key and its value")
                pairs.append((k, try expression()))
                if isOp(",") { advance() } else { break }
            }
            try expectOp("}", "`}` to close the dictionary")
            return .dict(pairs)
        case .newline, .eof:
            throw err("SyntaxError: this line ends too early.")
        case .indent, .dedent:
            throw err("IndentationError: unexpected indent.")
        default:
            throw err("SyntaxError: unexpected `\(describe(t.kind))`.")
        }
    }

    private func describe(_ k: TokKind) -> String {
        switch k {
        case .op(let o): return o
        case .name(let n): return n
        default: return "symbol"
        }
    }
}
