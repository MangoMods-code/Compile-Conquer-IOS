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
    enum Kind { case info, warning, error, success }
    let id = UUID()
    let text: String
    let kind: Kind
}

/// Runs one level: the map, the player's code, and the step-by-step execution.
@MainActor
final class GameSession: ObservableObject {
    let level: LevelSpec
    let scene: FarmScene

    @Published private(set) var seed: UInt64
    /// Ticks for 3 stars on this exact map: what the straightforward solution takes.
    @Published private(set) var threeStarTicks: Int
    @Published private(set) var world: FarmWorld
    @Published var code: String {
        didSet { GameProgress.shared.saveCode(code, for: level) }
    }
    @Published private(set) var state: RunState = .editing
    @Published private(set) var activeLine: Int?
    @Published private(set) var errorLine: Int?
    @Published private(set) var console: [ConsoleLine] = []
    @Published var speedIndex = 1

    static let speeds: [Double] = [1, 2, 4, 10]
    var speedLabel: String { "\(Int(Self.speeds[speedIndex]))x" }
    private var tickDuration: Double { 0.5 / Self.speeds[speedIndex] }

    private var startWorld: FarmWorld
    private var program: LineScript?
    private var runTask: Task<Void, Never>?
    private let maxTicks = 2000

    init(level: LevelSpec) {
        self.level = level
        let s = SeedCode.random()
        self.seed = s
        let w = LevelGenerator.make(level, seed: s)
        self.startWorld = w
        self.world = w
        self.threeStarTicks = ParSolver.straightforwardTicks(w, spec: level) ?? level.threeStarTicks
        self.code = GameProgress.shared.code(for: level)
        self.scene = FarmScene(size: CGSize(width: 400, height: 400))
        scene.load(w)
        log("Map \(SeedCode.format(s)) ready. Goal: \(level.goal) Wheat. ★★★ at \(threeStarTicks) ticks or less.", .info)
    }

    var seedText: String { SeedCode.format(seed) }

    /// 2 stars gets a generous buffer above the 3-star limit.
    var twoStarTicks: Int { threeStarTicks + max(4, threeStarTicks / 2) }

    func stars(forTicks t: Int) -> Int { t <= threeStarTicks ? 3 : (t <= twoStarTicks ? 2 : 1) }

    /// The whole main.py: the locked header (imports) plus the player's code.
    var fullText: String { level.header + code }

    /// Called by the editor. Edits that would touch the locked header are ignored.
    func setFullText(_ text: String) {
        guard text.hasPrefix(level.header) else { return }
        let body = String(text.dropFirst(level.header.count))
        if body != code { code = body; errorLine = nil }
    }

    /// First line of the player's code in main.py.
    var firstCodeLine: Int { level.headerLines + 1 }
    var wheat: Int { world.count(of: .wheat) }

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
            guard compileFresh() else { return }
            state = .running
            startLoop()
        }
    }

    func step() {
        switch state {
        case .running:
            runTask?.cancel()
            state = .paused
        case .paused:
            break
        default:
            guard compileFresh() else { return }
            state = .paused
        }
        execute()
    }

    func reset() {
        runTask?.cancel()
        program = nil
        activeLine = nil
        world = startWorld
        scene.load(world)
        state = .editing
    }

    func newMap() {
        seed = SeedCode.random()
        startWorld = LevelGenerator.make(level, seed: seed)
        threeStarTicks = ParSolver.straightforwardTicks(startWorld, spec: level) ?? level.threeStarTicks
        reset()
        log("New map \(SeedCode.format(seed)). ★★★ at \(threeStarTicks) ticks or less.", .info)
    }

    func restoreStarterCode() {
        code = level.starterCode
    }

    func cycleSpeed() { speedIndex = (speedIndex + 1) % Self.speeds.count }

    func dismissResult() {
        if case .won = state { reset() } else if case .failed = state { reset() }
    }

    // MARK: Running

    /// Compiles the code and resets the map so every run starts from the same layout.
    private func compileFresh() -> Bool {
        reset()
        errorLine = nil
        do {
            let script = try LineScript(source: code, lineOffset: level.headerLines,
                                        defined: Set(level.commands + level.setupNames))
            guard !script.isEmpty else {
                log("Write some code first: call a command from the setup.", .warning)
                return false
            }
            program = script
            log("Running…", .info)
            return true
        } catch let e as ScriptError {
            errorLine = e.line
            log("Line \(e.line): \(e.message)", .error)
            return false
        } catch {
            log(error.localizedDescription, .error)
            return false
        }
    }

    private func startLoop() {
        runTask?.cancel()
        runTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.state == .running else { break }
                self.execute()
                guard self.state == .running else { break }
                let delay = UInt64(self.tickDuration * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    private func execute() {
        guard var p = program else { return }
        let next: (line: Int, command: DroneCommand)?
        do {
            next = try p.next()
        } catch let e as ScriptError {
            errorLine = e.line
            finish(failure: "Line \(e.line): \(e.message)")
            return
        } catch {
            finish(failure: error.localizedDescription)
            return
        }
        program = p

        guard let nextStep = next else {
            finish(failure: "Program ended with \(wheat)/\(level.goal) Wheat. Add more commands or tweak your plan.")
            return
        }
        let line = nextStep.line
        let command = nextStep.command

        activeLine = line
        let outcome = world.perform(command)
        scene.apply(world, command: command, outcome: outcome, duration: tickDuration)

        switch outcome {
        case .ok(let note): if let note { log("Line \(line): \(note)", .success) }
        case .warning(let msg): log("Line \(line): \(msg)", .warning)
        case .bumped(let msg): log("Line \(line): \(msg)", .warning)
        }

        if wheat >= level.goal {
            let stars = stars(forTicks: world.ticks)
            GameProgress.shared.record(stars: stars, for: level.id)
            runTask?.cancel()
            activeLine = nil
            state = .won(stars: stars, ticks: world.ticks)
            log("Goal complete in \(world.ticks) ticks!", .success)
        } else if world.ticks >= maxTicks {
            finish(failure: "Stopped after \(maxTicks) ticks.")
        }
    }

    private func finish(failure message: String) {
        runTask?.cancel()
        activeLine = nil
        state = .failed(message)
        log(message, .error)
    }

    private func log(_ text: String, _ kind: ConsoleLine.Kind) {
        console.append(ConsoleLine(text: text, kind: kind))
        if console.count > 60 { console.removeFirst(console.count - 60) }
    }
}
