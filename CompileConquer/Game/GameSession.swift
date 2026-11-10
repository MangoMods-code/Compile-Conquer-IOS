import SwiftUI
import SpriteKit

/// The result card's numbers.
struct WinInfo: Equatable {
    let stars: Int
    let ticks: Int
    let par: Int
    let lines: Int
    /// The Tidy bonus limit, if this level has one.
    let tidyLimit: Int?
    let tidy: Bool
    let newBest: Bool
}

enum RunState: Equatable {
    case editing
    /// The program is being checked and simulated.
    case compiling
    case running
    case paused
    case won(WinInfo)
    case failed(String)

    /// The editor is locked while a run is on screen.
    var isActive: Bool { self == .running || self == .paused || self == .compiling }
}

struct ConsoleLine: Identifiable {
    enum Kind { case info, output, warning, error, success }
    let id = UUID()
    let text: String
    let kind: Kind
}

/// Anything that can draw a world and animate one step of it.
@MainActor
protocol WorldRenderer: AnyObject {
    var onTapTile: ((Pos) -> Void)? { get set }
    var topInset: CGFloat { get set }
    var leadingInset: CGFloat { get set }
    func load(_ state: WorldState)
    func apply(_ state: WorldState, action: WorldAction, outcome: CommandOutcome, duration: TimeInterval)
    func highlight(_ p: Pos?)
}

/// Runs one level: the map, the player's code, and playback of the run.
/// Pressing Run simulates the whole program in the background, then plays the recorded steps back.
/// Because the whole run is recorded, it can be paused, stepped and scrubbed in both directions.
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
    /// Ticks for 3 stars on this exact map.
    @Published private(set) var threeStarTicks: Int
    @Published private(set) var world: WorldState
    @Published var code: String {
        didSet { GameProgress.shared.saveCode(code, for: level) }
    }
    @Published private(set) var state: RunState = .editing
    @Published private(set) var activeLine: Int?
    @Published private(set) var errorLine: Int?
    @Published private(set) var console: [ConsoleLine] = []
    /// The player's variables at the current point of the run.
    @Published private(set) var watch: [PyInterpreter.WatchVar] = []
    /// Playback position, in ticks, and the length of the recorded run.
    @Published private(set) var tick = 0
    @Published private(set) var totalTicks = 0
    /// The tile the player tapped on the map.
    @Published private(set) var inspected: TileInfo?
    @Published var speedIndex: Int
    @Published var showIntro: Bool

    static let speeds: [Double] = [1, 2, 4, 10]
    var speedLabel: String { "\(Int(Self.speeds[speedIndex]))x" }
    private var tickDuration: Double { 0.5 / Self.speeds[speedIndex] }

    /// The map as generated from the seed, and the (possibly re-rolled) map this run started from.
    private var baseWorld: WorldState
    private var startWorld: WorldState
    private var trace: [TraceStep] = []
    /// Index into `trace` of each tick step.
    private var tickIndex: [Int] = []
    /// Console lines produced by each trace step.
    private var stepLines: [[ConsoleLine]] = []
    private var baseConsole: [ConsoleLine] = []
    private var cursor = 0
    private var ending: SimEnding = .finished
    private var runTask: Task<Void, Never>?
    private var simTask: Task<Void, Never>?

    init(level: LevelSpec) {
        self.level = level
        let h = level.header
        header = h
        headerLines = h.components(separatedBy: "\n").count - 1
        lockedLength = (h as NSString).length
        speedIndex = min(max(0, AppSettings.shared.defaultSpeed), Self.speeds.count - 1)

        let progress = GameProgress.shared
        let s = progress.seed(for: level) ?? SeedCode.random()
        progress.saveSeed(s, for: level)
        seed = s
        let w = WorldState.make(level, seed: s)
        baseWorld = w
        startWorld = w
        world = w
        threeStarTicks = w.par(level) ?? 60
        code = progress.code(for: level)
        showIntro = !progress.hasSeenIntro(level) && !UserDefaults.standard.bool(forKey: "uitest.noIntro")

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
        renderer.onTapTile = { [weak self] p in self?.inspect(p) }
        note("Map \(SeedCode.format(s)) ready. \(level.goalSummary). ★★★ at \(threeStarTicks) ticks or less.", .info)
    }

    var seedText: String { SeedCode.format(seed) }
    var goalCount: Int { world.progress(level) }
    var goalItems: [GoalItem] { world.goalItems(level) }
    var codeLineCount: Int { LevelSpec.codeLines(code) }
    var hasRun: Bool { !trace.isEmpty }

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

    func setTopInset(_ inset: CGFloat) { renderer.topInset = inset }
    func setLeadingInset(_ inset: CGFloat) { renderer.leadingInset = inset }

    // MARK: Controls

    func runOrPause() {
        switch state {
        case .compiling:
            break
        case .running:
            runTask?.cancel()
            state = .paused
        case .paused:
            state = .running
            startLoop()
        default:
            SoundFX.shared.play(.run)
            prepareRun { [weak self] in
                guard let self else { return }
                self.state = .running
                self.startLoop()
            }
        }
    }

    /// Runs one tick forward.
    func step() {
        switch state {
        case .compiling:
            break
        case .running:
            runTask?.cancel()
            state = .paused
        case .paused:
            advance()
        default:
            prepareRun { [weak self] in
                guard let self else { return }
                self.state = .paused
                self.advance()
            }
        }
    }

    /// Goes back one tick.
    func stepBack() {
        guard hasRun, tick > 0 else { return }
        seek(tick - 1)
    }

    /// Jumps to any tick of the recorded run.
    func seek(_ k: Int) {
        guard hasRun, state != .compiling else { return }
        runTask?.cancel()
        let target = min(max(0, k), totalTicks)
        if target == 0 {
            world = startWorld
            cursor = 0
            activeLine = nil
            watch = []
        } else {
            let idx = tickIndex[target - 1]
            let s = trace[idx]
            if case .tick(let st, _, _) = s.kind { world = st }
            cursor = idx + 1
            while cursor < trace.count, case .print = trace[cursor].kind { cursor += 1 }
            activeLine = s.line
            watch = s.vars
        }
        tick = target
        renderer.load(world)
        refreshInspection()
        rebuildConsole()
        state = .paused
    }

    func reset() {
        runTask?.cancel()
        simTask?.cancel()
        trace = []
        tickIndex = []
        stepLines = []
        cursor = 0
        tick = 0
        totalTicks = 0
        activeLine = nil
        watch = []
        world = startWorld
        renderer.load(world)
        refreshInspection()
        state = .editing
    }

    func newMap() {
        seed = SeedCode.random()
        GameProgress.shared.saveSeed(seed, for: level)
        baseWorld = WorldState.make(level, seed: seed)
        startWorld = baseWorld
        threeStarTicks = startWorld.par(level) ?? threeStarTicks
        clearInspection()
        reset()
        baseConsole = []
        note("New map \(SeedCode.format(seed)). ★★★ at \(threeStarTicks) ticks or less.", .info)
    }

    func restoreStarterCode() { code = level.starterCode }

    func cycleSpeed() { speedIndex = (speedIndex + 1) % Self.speeds.count }

    /// Closes the result card or failure banner and goes back to editing.
    func dismissResult() {
        switch state {
        case .won, .failed: reset()
        default: break
        }
    }

    func dismissIntro() {
        showIntro = false
        GameProgress.shared.markIntroSeen(level)
    }

    /// Stops everything when the level screen closes.
    func stop() {
        runTask?.cancel()
        simTask?.cancel()
    }

    // MARK: Inspecting tiles

    func inspect(_ p: Pos) {
        if inspected?.pos == p { clearInspection(); return }
        inspected = world.inspect(p)
        renderer.highlight(inspected == nil ? nil : p)
        SoundFX.shared.play(.tap)
    }

    func clearInspection() {
        inspected = nil
        renderer.highlight(nil)
    }

    private func refreshInspection() {
        guard let p = inspected?.pos else { return }
        inspected = world.inspect(p)
        renderer.highlight(p)
    }

    // MARK: Running

    /// Resets the map, re-rolls it where the level asks for it, and simulates the program off the main thread.
    private func prepareRun(then start: @escaping () -> Void) {
        reset()
        errorLine = nil

        if level.rerollsEachRun {
            startWorld = baseWorld.rerolled(level, seed: SeedCode.random())
            threeStarTicks = startWorld.par(level) ?? threeStarTicks
            world = startWorld
            renderer.load(world)
            refreshInspection()
        }

        state = .compiling
        let code = self.code
        let level = self.level
        let startWorld = self.startWorld
        let offset = headerLines
        simTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Simulator.run(code: code, level: level, start: startWorld, headerLines: offset)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.accept(result, then: start)
        }
    }

    private func accept(_ result: SimResult, then start: () -> Void) {
        guard state == .compiling else { return }
        if result.steps.isEmpty {
            state = .editing
            switch result.ending {
            case .error(let e):
                errorLine = e.line
                note("Line \(e.line): \(e.message)", .error)
                SoundFX.shared.play(.error)
                Haptics.warning()
            default:
                note("Your code didn't run any commands yet. Call one from the setup.", .warning)
            }
            return
        }
        trace = result.steps
        ending = result.ending
        cursor = 0
        tick = 0
        tickIndex = []
        stepLines = []
        stepLines.reserveCapacity(trace.count)
        for (i, s) in trace.enumerated() {
            switch s.kind {
            case .print(let text):
                stepLines.append([ConsoleLine(text: text, kind: .output)])
            case .tick(_, _, let outcome):
                tickIndex.append(i)
                switch outcome {
                case .ok(let n):
                    if let n { stepLines.append([ConsoleLine(text: "Line \(s.line): \(n)", kind: .success)]) } else { stepLines.append([]) }
                case .warning(let msg), .bumped(let msg):
                    stepLines.append([ConsoleLine(text: "Line \(s.line): \(msg)", kind: .warning)])
                }
            }
        }
        totalTicks = tickIndex.count
        note("Running…", .info)
        start()
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
        var newLines: [ConsoleLine] = []
        defer { if !newLines.isEmpty { appendConsole(newLines) } }

        while cursor < trace.count {
            let s = trace[cursor]
            newLines += stepLines[cursor]
            cursor += 1
            guard case .tick(let newState, let action, let outcome) = s.kind else { continue }

            activeLine = s.line
            world = newState
            watch = s.vars
            tick += 1
            renderer.apply(newState, action: action, outcome: outcome, duration: tickDuration)
            playSound(for: action, outcome)
            refreshInspection()

            // Show any prints that came right after this step, then stop for the animation.
            while cursor < trace.count, case .print = trace[cursor].kind {
                newLines += stepLines[cursor]
                cursor += 1
            }
            if cursor >= trace.count { finish() }
            return
        }
        finish()
    }

    private func playSound(for action: WorldAction, _ outcome: CommandOutcome) {
        let fx = SoundFX.shared
        switch outcome {
        case .bumped:
            fx.play(.bump)
            Haptics.thud()
            return
        case .warning:
            fx.play(.error)
            return
        case .ok(let noteText):
            switch action {
            case .farm(let c):
                switch c {
                case .move: fx.play(.move)
                case .till: fx.play(.till)
                case .plant: fx.play(.plant)
                case .water: fx.play(.water)
                case .harvest: fx.play(.harvest)
                case .wait: break
                }
            case .warehouse(let c):
                switch c {
                case .move: fx.play(.move)
                case .pick: fx.play(.pick)
                case .drop: fx.play(noteText == nil ? .drop : .ship)
                case .scan: fx.play(.scan)
                case .wait: break
                }
            }
        }
    }

    private func finish() {
        runTask?.cancel()
        activeLine = nil
        switch ending {
        case .goal:
            let ticks = world.ticks
            let stars = stars(forTicks: ticks)
            let lines = codeLineCount
            let tidy = level.tidyLines.map { lines <= $0 } ?? false
            let newBest = GameProgress.shared.record(stars: stars, ticks: ticks, tidy: tidy, for: level.id)
            // The next visit gets a fresh map.
            GameProgress.shared.clearSeed(for: level)
            appendConsole([ConsoleLine(text: "Goal complete in \(ticks) ticks!", kind: .success)])
            state = .won(WinInfo(stars: stars, ticks: ticks, par: threeStarTicks, lines: lines,
                                 tidyLimit: level.tidyLines, tidy: tidy, newBest: newBest))
            SoundFX.shared.play(.win)
            Haptics.success()
        case .finished:
            fail("The program ended with \(goalCount)/\(level.goal) \(level.goalNoun). Add more code or tweak your plan.")
        case .error(let e):
            errorLine = e.line
            fail("Line \(e.line): \(e.message)")
        case .failed(let message):
            fail(message)
        case .outOfTicks:
            fail("Stopped after \(Simulator.maxTicks) ticks without reaching the goal.")
        }
    }

    private func fail(_ message: String) {
        state = .failed(message)
        appendConsole([ConsoleLine(text: message, kind: .error)])
        SoundFX.shared.play(.fail)
        Haptics.warning()
    }

    // MARK: Console

    /// A line that isn't part of the recorded run (map ready, compile errors...).
    private func note(_ text: String, _ kind: ConsoleLine.Kind) {
        let line = ConsoleLine(text: text, kind: kind)
        baseConsole.append(line)
        if baseConsole.count > 40 { baseConsole.removeFirst(baseConsole.count - 40) }
        appendConsole([line])
    }

    private func appendConsole(_ lines: [ConsoleLine]) {
        console += lines
        if console.count > 300 { console.removeFirst(console.count - 300) }
    }

    /// Rebuilds the console for the current playback position (after scrubbing).
    private func rebuildConsole() {
        var lines = baseConsole
        let upTo = min(cursor, stepLines.count)
        if upTo > 0 { for i in 0..<upTo { lines += stepLines[i] } }
        console = Array(lines.suffix(300))
    }
}
