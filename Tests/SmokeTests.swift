import XCTest
import SpriteKit
import UIKit
@testable import CompileConquer

/// Opens every level the way the app does and plays a real Python solution through it.
/// If any level crashes or can't be solved, this fails in CI before a build reaches a phone.
@MainActor
final class SmokeTests: XCTestCase {
    private var allLevels: [LevelSpec] { WorldInfo.all.flatMap { $0.levels } }

    // A Python solver that works on any map: breadth-first search for paths.
    private static let pathCode = """
    def path_to(tx, ty, me, grid):
        start = (me.x, me.y)
        prev = {start: None}
        queue = [start]
        while len(queue) > 0:
            cur = queue.pop(0)
            if cur == (tx, ty):
                break
            x, y = cur
            for d in [North, East, South, West]:
                nx = x
                ny = y
                if d == North:
                    ny += 1
                elif d == South:
                    ny -= 1
                elif d == East:
                    nx += 1
                else:
                    nx -= 1
                nxt = (nx, ny)
                if grid.is_open(nx, ny) and nxt not in prev:
                    prev[nxt] = (cur, d)
                    queue.append(nxt)
        steps = []
        cur = (tx, ty)
        while prev[cur] is not None:
            p, d = prev[cur]
            steps.append(d)
            cur = p
        steps.reverse()
        for d in steps:
            move(d)

    """

    private static let farmSolver = pathCode + """
    targets = []
    for y in range(field.height):
        for x in range(field.width):
            if field.tile_at(x, y).ground == "soil":
                targets.append((x, y))
    if len(targets) == 0:
        for y in range(field.height):
            for x in range(field.width):
                if field.tile_at(x, y).ground == "grass":
                    targets.append((x, y))
    i = 0
    while stock["Wheat"] < GOAL:
        tx, ty = targets[i % len(targets)]
        i += 1
        if (drone.x, drone.y) != (tx, ty):
            path_to(tx, ty, drone, field)
        if field.tile_at(tx, ty).ground == "grass":
            till()
        plant()
        while field.tile_at(tx, ty).crop.age < GROW_TIME:
            wait()
        harvest()
        print("stock", stock["Wheat"])
    """

    private static let warehouseSolver = pathCode + """
    while len(floor.crates) > 0 or loader.carrying is not None:
        if loader.carrying is None:
            c = floor.crates[0]
            path_to(c.x, c.y, loader, floor)
            pick()
        color = loader.carrying.color
        if color == "?":
            color = scan()
        bay = BAYS[color]
        path_to(bay.x, bay.y, loader, floor)
        drop()
        print("shipped", shipped)
    """

    func testEveryLevelGeneratesAndHasPar() {
        for level in allLevels {
            for seed: UInt64 in 1...25 {
                let w = WorldState.make(level, seed: seed)
                XCTAssertNotNil(w.par(level), "\(level.id) seed \(seed): no straightforward solution")
            }
        }
    }

    func testEveryLevelOpensLikeTheApp() {
        for level in allLevels {
            let session = GameSession(level: level)
            XCTAssertTrue(session.fullText.hasPrefix(session.header), level.id)
            // Resize like SpriteView does; this rebuilds the scene and all textures.
            session.scene.size = CGSize(width: 430, height: 330)
            session.scene.size = CGSize(width: 380, height: 300)
            _ = PyLexerCheck.parseHeaderSafe(level)
        }
    }

    func testEditorWithEveryHeader() {
        for level in allLevels {
            let session = GameSession(level: level)
            // Same order as CodeEditor.makeUIView: locked length is set before any text.
            let tv = CodeTextView.make()
            tv.lockedLength = session.lockedLength
            tv.frame = CGRect(x: 0, y: 0, width: 400, height: 250)
            tv.font = CodeStyle.font(13)
            tv.text = session.fullText + String(repeating: "move(North)\n", count: 300)
            tv.textChanged()
            tv.lockedLength = session.lockedLength
            let editor = CodeEditor(text: .constant(tv.text), activeLine: session.firstCodeLine, errorLine: 3,
                                    editable: true, lockedLength: session.lockedLength, commands: level.commands)
            let coordinator = editor.makeCoordinator()
            coordinator.styleAll(tv)
            tv.layoutIfNeeded()
            tv.scroll(toLine: tv.lineCount)
            tv.scroll(toLine: 1)
            XCTAssertGreaterThan(tv.lineCount, session.headerLines)
        }
    }

    func testPythonSolverBeatsEveryLevelAndScenesPlayIt() {
        for level in allLevels {
            let code = level.world == .farm ? Self.farmSolver : Self.warehouseSolver
            for seed: UInt64 in 1...6 {
                var start = WorldState.make(level, seed: seed)
                if level.warehouse?.reshuffleEachRun == true, case .warehouse(let w) = start {
                    start = .warehouse(WarehouseGenerator.reshuffle(w, level: level, seed: seed &* 31))
                }
                let result = Simulator.run(code: code, level: level, start: start)
                switch result.ending {
                case .goal: break
                case .error(let e): XCTFail("\(level.id) seed \(seed): line \(e.line - level.headerLines) of solver: \(e.message)")
                case .finished: XCTFail("\(level.id) seed \(seed): solver ended without reaching the goal")
                case .outOfTicks: XCTFail("\(level.id) seed \(seed): ran out of ticks")
                }

                // Play the trace through the real scene, like the level screen does.
                let session = GameSession(level: level)
                session.scene.size = CGSize(width: 420, height: 320)
                guard let renderer = session.scene as? WorldRenderer else { XCTFail("no renderer"); continue }
                renderer.load(start)
                for step in result.steps {
                    if case .tick(let state, let action, let outcome) = step.kind {
                        renderer.apply(state, action: action, outcome: outcome, duration: 0.01)
                    }
                }
            }
        }
    }

    func testPythonLanguage() {
        let level = FarmChapter.levels[0]
        let start = WorldState.make(level, seed: 7)
        let program = """
        total = 0
        for i in range(1, 5):
            total += i * 2
        names = ["a", "b"]
        names.append("c")
        d = {"x": 1}
        d["y"] = 2
        def f(a, b=10):
            return a + b
        print(total, len(names), d["y"], f(1), f(1, b=2), 7 // 2, -7 % 3, 2 ** 5, "hi" * 2)
        if total > 10 and not (total == 3):
            print("big")
        elif total < 0:
            print("neg")
        else:
            print("small")
        n = 0
        while True:
            n += 1
            if n >= 3:
                break
        print(n, names)
        plant()
        wait(GROW_TIME)
        harvest()
        """
        let result = Simulator.run(code: program, level: level, start: start)
        let prints = result.steps.compactMap { s -> String? in if case .print(let t) = s.kind { return t }; return nil }
        if case .error(let e) = result.ending { XCTFail("line \(e.line): \(e.message)") }
        XCTAssertEqual(prints.first, "20 3 2 11 3 3 2 32 hihi")
        XCTAssertEqual(prints.dropFirst().first, "big")
        XCTAssertEqual(prints.last, "3 ['a', 'b', 'c']")
        if case .goal = result.ending {} else { XCTFail("expected the wheat goal") }
    }

    func testRunawayLoopIsCaughtNotFrozen() {
        let level = FarmChapter.levels[0]
        let result = Simulator.run(code: "while True:\n    x = 1\n", level: level, start: WorldState.make(level, seed: 1))
        guard case .error(let e) = result.ending else { return XCTFail("expected an error") }
        XCTAssertTrue(e.message.contains("loop"))
    }
}

/// Small helper so the test also exercises the lexer on every level's header text.
enum PyLexerCheck {
    static func parseHeaderSafe(_ level: LevelSpec) -> Bool {
        (try? PyLexer.tokenize(level.starterCode, lineOffset: level.headerLines)) != nil
    }
}
