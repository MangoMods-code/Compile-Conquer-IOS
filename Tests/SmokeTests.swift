import XCTest
import SpriteKit
import UIKit
@testable import CompileConquer

/// Opens every level the way the app does and plays real Python through it.
/// If any level crashes, can't be solved, or its taught solution misses 3 stars, this fails in CI.
@MainActor
final class SmokeTests: XCTestCase {
    private var allLevels: [LevelSpec] { WorldInfo.all.flatMap { $0.levels } }

    private func start(_ level: LevelSpec, seed: UInt64) -> WorldState {
        let base = WorldState.make(level, seed: seed)
        return level.rerollsEachRun ? base.rerolled(level, seed: seed &* 31 &+ 7) : base
    }

    private func describe(_ ending: SimEnding, _ level: LevelSpec) -> String {
        let offset = level.header.components(separatedBy: "\n").count - 1
        switch ending {
        case .goal: return "goal"
        case .finished: return "ended without reaching the goal"
        case .error(let e): return "error on line \(e.line - offset) of the test code: \(e.message)"
        case .failed(let m): return "broke a level rule: \(m)"
        case .outOfTicks: return "ran out of ticks"
        }
    }

    func testLevelListsAreSane() {
        XCTAssertEqual(FarmChapter.levels.count, 10)
        XCTAssertEqual(WarehouseChapter.levels.count, 8)
        XCTAssertEqual(Set(allLevels.map { $0.id }).count, allLevels.count, "level ids must be unique")
        for (i, l) in FarmChapter.levels.enumerated() { XCTAssertEqual(l.number, i + 1) }
        for (i, l) in WarehouseChapter.levels.enumerated() { XCTAssertEqual(l.number, i + 1) }
        for l in allLevels { XCTAssertGreaterThan(l.goal, 0, l.id) }
    }

    func testEveryLevelGeneratesAndHasPar() {
        for level in allLevels {
            for seed: UInt64 in 1...25 {
                let w = start(level, seed: seed)
                XCTAssertNotNil(w.par(level), "\(level.id) seed \(seed): no 3-star limit")
                XCTAssertEqual(w.progress(level), 0, "\(level.id) seed \(seed): starts with progress")
            }
        }
    }

    func testSetupCodeIsShortEnoughForAPhone() {
        for level in allLevels {
            for line in level.header.components(separatedBy: "\n") {
                XCTAssertLessThanOrEqual(line.count, 46, "\(level.id) setup line is too wide: \(line)")
            }
        }
    }

    func testEveryLevelOpensLikeTheApp() {
        for level in allLevels {
            let session = GameSession(level: level)
            XCTAssertTrue(session.fullText.hasPrefix(session.header), level.id)
            // Resize like SpriteView does; this rebuilds the scene and all textures.
            session.scene.size = CGSize(width: 430, height: 330)
            session.setTopInset(48)
            session.scene.size = CGSize(width: 380, height: 300)
            session.inspect(Pos(x: 0, y: 0))
            XCTAssertNotNil(session.inspected, level.id)
            session.clearInspection()
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
                                    editable: true, lockedLength: session.lockedLength, commands: level.commands, names: level.setupNames)
            let coordinator = editor.makeCoordinator()
            coordinator.styleAll(tv)
            tv.layoutIfNeeded()
            tv.scroll(toLine: tv.lineCount)
            tv.scroll(toLine: 1)
            XCTAssertGreaterThan(tv.lineCount, session.headerLines)
        }
    }

    func testGeneralSolverBeatsEveryLevelAndScenesPlayIt() {
        for level in allLevels {
            let code = Solutions.general(for: level)
            for seed: UInt64 in 1...6 {
                let world = start(level, seed: seed)
                let result = Simulator.run(code: code, level: level, start: world)
                guard case .goal = result.ending else {
                    XCTFail("\(level.id) seed \(seed): \(describe(result.ending, level))")
                    continue
                }
                // Play the trace through the real scene, like the level screen does.
                let session = GameSession(level: level)
                session.scene.size = CGSize(width: 420, height: 320)
                guard let renderer = session.scene as? WorldRenderer else { XCTFail("no renderer"); continue }
                renderer.load(world)
                for step in result.steps {
                    if case .tick(let state, let action, let outcome) = step.kind {
                        renderer.apply(state, action: action, outcome: outcome, duration: 0.01)
                    }
                }
            }
        }
    }

    /// The solution each level's hints lead to has to earn 3 stars on every map.
    func testIntendedSolutionsEarnThreeStars() {
        for level in allLevels {
            guard let code = Solutions.intended[level.id] else { continue }
            for seed: UInt64 in 1...15 {
                let world = start(level, seed: seed)
                let result = Simulator.run(code: code, level: level, start: world)
                guard case .goal = result.ending else {
                    XCTFail("\(level.id) seed \(seed): \(describe(result.ending, level))")
                    continue
                }
                let ticks = result.steps.reduce(0) { n, s in if case .tick = s.kind { return n + 1 }; return n }
                let par = world.par(level) ?? 0
                XCTAssertLessThanOrEqual(ticks, par, "\(level.id) seed \(seed): intended solution took \(ticks) ticks, 3 stars need \(par)")
            }
        }
    }

    func testLevelRuleEndsTheRun() {
        guard let level = FarmChapter.levels.first(where: { $0.farm?.maxLost != nil }) else { return XCTFail("no rule level") }
        // Harvest everything without checking: sooner or later this picks an unripe pumpkin.
        let code = """
        d = East
        if not field.is_open(drone.x + 1, drone.y):
            d = West
        for i in range(6):
            move(d)
            harvest()
        """
        var failures = 0
        for seed: UInt64 in 1...8 {
            let result = Simulator.run(code: code, level: level, start: start(level, seed: seed))
            if case .failed = result.ending { failures += 1 }
        }
        XCTAssertGreaterThan(failures, 0, "harvesting unripe crops should end the run on this level")
    }

    func testPythonLanguage() {
        let level = FarmChapter.levels[0]
        let world = start(level, seed: 7)
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
        squares = [x * x for x in range(6) if x % 2 == 0]
        print(squares, names[1:], names[::-1], "abcdef"[2:4])
        print(f"total={total} half={total / 8:.2f} {names[0]}!")
        for i, name in enumerate(names):
            print(i, name)
        print("-".join(["a", "b"]), sorted([3, 1, 2]), any([0, 1]), all([1, 0]), sum([1, 2, 3]))
        plant()
        wait(GROW_TIME)
        harvest()
        """
        let result = Simulator.run(code: program, level: level, start: world)
        let prints = result.steps.compactMap { s -> String? in if case .print(let t) = s.kind { return t }; return nil }
        if case .error(let e) = result.ending { XCTFail("line \(e.line): \(e.message)") }
        let expected = [
            "20 3 2 11 3 3 2 32 hihi",
            "big",
            "3 ['a', 'b', 'c']",
            "[0, 4, 16] ['b', 'c'] ['c', 'b', 'a'] cd",
            "total=20 half=2.50 a!",
            "0 a", "1 b", "2 c",
            "a-b [1, 2, 3] True False 6",
        ]
        XCTAssertEqual(prints, expected)
        if case .goal = result.ending {} else { XCTFail("expected the wheat goal") }
        // The Variables panel sees the player's variables.
        XCTAssertTrue(result.finalVars.contains { $0.name == "total" && $0.value == "20" })
    }

    func testFriendlyErrors() {
        let level = FarmChapter.levels[1]
        let world = start(level, seed: 3)
        func message(_ code: String) -> String {
            if case .error(let e) = Simulator.run(code: code, level: level, start: world).ending { return e.message }
            return ""
        }
        XCTAssertTrue(message("mvoe(North)").contains("move"), "typos should suggest the right name")
        XCTAssertTrue(message("move(north)").contains("North"))
        XCTAssertTrue(message("water()").contains("later level"), "locked commands should say so")
        XCTAssertTrue(message("if drone.x = 3:\n    wait()").contains("=="))
        XCTAssertTrue(message("for i in range(3)\n    wait()").contains(":"))
        XCTAssertTrue(message("while True:\n    x = 1").contains("loop"))
    }
}
