import SwiftUI
import SpriteKit

enum RunState: Equatable {
    case editing
    case running
    case paused
    case won(stars: Int, ticks: Int)
    case failed(String)

    var isActive: Bool { self == .running || self == .paused }
}

struct ConsoleLine: Identifiable {
    enum Kind { case info, output, warning, error, success }
    let id = UUID()
    let text: String
    let kind: Kind
}

/// Anything that can draw a world and animate one step of it.
protocol WorldRenderer: AnyObject {
    func load(_ state: WorldState)
    func apply(_ state: WorldState, action: WorldAction, outcome: CommandOutcome, duration: TimeInterval)
}

/// Runs one level: the map, the player's code, and playback of the run.
/// Pressing Run simulates the whole program instantly, then plays the recorded steps back.
@MainActor
final class GameSession: ObservableObject {
    let level: LevelSpec
    let scene: SKScene
    private let renderer: WorldRenderer

    /// The locked setup at the top of main.py (cached; it's long).
    let header: String
    let headerLines: Int
    let lockedLength: Int

    @Published private(set) var seed: UInt64
    /// Ticks for 3 stars on this exact map: what the straightforward solution takes.
    @Published private(set) var threeStarTicks: Int
    @Published private(set) var world: WorldState
    @Published var code: String {
        didSet { GameProgress.shared.saveCode(code, for: level) }
    }
    @Published private(set) var state: RunState = .editing
    @Published private(set) var activeLine: Int?
    @Published private(set) var errorLine: Int?
    @Published private(set) var console: [ConsoleLine] = []
    @Published var speedIndex: Int

    static let speeds: [Double] = [1, 2, 4, 10]
    var speedLabel: String { "\(Int(Self.speeds[speedIndex]))x" }
    private var tickDuration: Double { 0.5 / Self.speeds[speedIndex] }

    private var startWorld: WorldState
    private var trace: [TraceStep] = []
    private var cursor = 0
    private var ending: SimEnding = .finished
    private var runTask: Task<Void, Never>?

    init(level: LevelSpec) {
        self.level = level
        let h = level.header
        header = h
        headerLines = h.components(separatedBy: "\n").count - 1
        lockedLength = (h as NSString).length
        speedIndex = min(max(0, AppSettings.shared.defaultSpeed), Self.speeds.count - 1)

        let s = SeedCode.random()
        seed = s
        let w = WorldState.make(level, seed: s)
        startWorld = w
        world = w
        threeStarTicks = w.par(level) ?? level.threeStarTicks
        code = GameProgress.shared.code(for: level)

        switch level.world {
        case .farm:
            let sc = FarmScene(size: CGSize(width: 400, height: 400))
            scene = sc
            renderer = sc
        case .warehouse:
            let sc = WarehouseScene(size: CGSize(width: 400, height: 400))
            scene = sc
            renderer = sc
        }
        renderer.load(w)
        log("Map \(SeedCode.format(s)) ready. Goal: \(level.goal) \(level.goalNoun). ★★★ at \(threeStarTicks) ticks or less.", .info)
    }

    var seedText: String { SeedCode.format(seed) }
    var goalCount: Int { world.goalCount }

    /// 2 stars gets a generous buffer above the 3-star limit.
    var twoStarTicks: Int { threeStarTicks + max(4, threeStarTicks / 2) }
    func stars(forTicks t: Int) -> Int { t <= threeStarTicks ? 3 : (t <= twoStarTicks ? 2 : 1) }

    /// The whole main.py: the locked setup plus the player's code.
    var fullText: String { header + code }

    /// Called by the editor. Edits that would touch the locked setup are ignored.
    func setFullText(_ text: String) {
        guard text.hasPrefix(header) else { return }
        let body = String(text.dropFirst(header.count))
        if body != code { code = body; errorLine = nil }
    }

    /// First line of the player's code in main.py.
    var firstCodeLine: Int { headerLines + 1 }

    // MARK: Controls

    func runOrPause() {
        switch state {
        case .running:
            runTask?.cancel()
            state = .paused
        case .paused:
            state = .running
            startLoop()
        default:
            guard prepareRun() else { return }
            state = .running
            startLoop()
        }
    }

    func step() {
        switch state {
        case .running:
            runTask?.cancel()
            state = .paused
            return
        case .paused:
            break
        default:
            guard prepareRun() else { return }
            state = .paused
        }
        advance()
    }

    func reset() {
        runTask?.cancel()
        trace = []
        cursor = 0
        activeLine = nil
        world = startWorld
        renderer.load(world)
        state = .editing
    }

    func newMap() {
        seed = SeedCode.random()
        startWorld = WorldState.make(level, seed: seed)
        threeStarTicks = startWorld.par(level) ?? level.threeStarTicks
        reset()
        log("New map \(SeedCode.format(seed)). ★★★ at \(threeStarTicks) ticks or less.", .info)
    }

    func restoreStarterCode() { code = level.starterCode }

    func cycleSpeed() { speedIndex = (speedIndex + 1) % Self.speeds.count }

    func dismissResult() {
        if case .won = state { reset() } else if case .failed = state { reset() }
    }

    // MARK: Running

    /// Resets the map, re-rolls colors where the level asks for it, and simulates the program.
    private func prepareRun() -> Bool {
        reset()
        errorLine = nil

        if level.warehouse?.reshuffleEachRun == true, case .warehouse(let w) = startWorld {
            startWorld = .warehouse(WarehouseGenerator.reshuffle(w, level: level, seed: SeedCode.random()))
            threeStarTicks = startWorld.par(level) ?? level.threeStarTicks
            world = startWorld
            renderer.load(world)
        }

        let result = Simulator.run(code: code, level: level, start: startWorld)
        if result.steps.isEmpty {
            switch result.ending {
            case .error(let e):
                errorLine = e.line
                log("Line \(e.line): \(e.message)", .error)
            default:
                log("Your code didn't run any commands yet. Call one from the setup.", .warning)
            }
            return false
        }
        trace = result.steps
        ending = result.ending
        cursor = 0
        log("Running…", .info)
        return true
    }

    private func startLoop() {
        runTask?.cancel()
        runTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.state == .running else { break }
                self.advance()
                guard self.state == .running else { break }
                let delay = UInt64(self.tickDuration * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    /// Plays recorded steps up to and including the next tick.
    private func advance() {
        while cursor < trace.count {
            let s = trace[cursor]
            cursor += 1
            activeLine = s.line
            switch s.kind {
            case .print(let text):
                log(text, .output)
            case .tick(let newState, let action, let outcome):
                world = newState
                renderer.apply(newState, action: action, outcome: outcome, duration: tickDuration)
                switch outcome {
                case .ok(let note): if let note { log("Line \(s.line): \(note)", .success) }
                case .warning(let msg): log("Line \(s.line): \(msg)", .warning)
                case .bumped(let msg): log("Line \(s.line): \(msg)", .warning)
                }
                // Show any prints that came right after this step, then stop for the animation.
                while cursor < trace.count, case .print(let text) = trace[cursor].kind {
                    log(text, .output)
                    cursor += 1
                }
                if cursor >= trace.count { finish() }
                return
            }
        }
        finish()
    }

    private func finish() {
        runTask?.cancel()
        activeLine = nil
        switch ending {
        case .goal:
            let ticks = world.ticks
            let stars = stars(forTicks: ticks)
            GameProgress.shared.record(stars: stars, for: level.id)
            state = .won(stars: stars, ticks: ticks)
            log("Goal complete in \(ticks) ticks!", .success)
        case .finished:
            fail("Program ended with \(goalCount)/\(level.goal) \(level.goalNoun). Add more code or tweak your plan.")
        case .error(let e):
            errorLine = e.line
            fail("Line \(e.line): \(e.message)")
        case .outOfTicks:
            fail("Stopped after \(Simulator.maxTicks) ticks without reaching the goal.")
        }
    }

    private func fail(_ message: String) {
        state = .failed(message)
        log(message, .error)
    }

    private func log(_ text: String, _ kind: ConsoleLine.Kind) {
        console.append(ConsoleLine(text: text, kind: kind))
        if console.count > 200 { console.removeFirst(console.count - 200) }
    }
}
