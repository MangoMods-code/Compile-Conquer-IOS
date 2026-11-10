import SwiftUI
import SpriteKit

/// Plays a tiny looping program on a real farm scene, for the title screen.
@MainActor
final class DemoDriver: ObservableObject {
    let scene: FarmScene
    /// The line of `code` that is running right now.
    @Published private(set) var line = 0

    static let code = [
        "for i in range(5):",
        "    move(East)",
        "    plant()",
        "wait(2)",
        "for i in range(5):",
        "    harvest()",
        "    move(West)",
    ]

    private var world: FarmWorld
    private var steps: [(Int, DroneCommand)] = []
    private var index = 0
    private var timer: Timer?
    private let interval = 0.5

    init() {
        var w = FarmWorld(width: 7, height: 4, drone: Pos(x: 0, y: 2), growTimes: [.wheat: 3])
        for x in 1...5 { w.setGround(.soil, at: Pos(x: x, y: 2)) }
        w.setGround(.rock, at: Pos(x: 1, y: 0))
        w.setGround(.water, at: Pos(x: 4, y: 0))
        w.setGround(.rock, at: Pos(x: 6, y: 3))
        var program: [(Int, DroneCommand)] = []
        for _ in 0..<5 { program.append((1, .move(.east))); program.append((2, .plant(.wheat))) }
        program.append((3, .wait)); program.append((3, .wait))
        for _ in 0..<5 { program.append((5, .harvest)); program.append((6, .move(.west))) }

        let sc = FarmScene(size: CGSize(width: 400, height: 300))
        sc.decorative = true
        sc.load(w)

        world = w
        steps = program
        scene = sc
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let (lineIndex, command) = steps[index]
        index = (index + 1) % steps.count
        line = lineIndex
        let outcome = world.perform(command)
        scene.apply(world, command: command, outcome: outcome, duration: interval)
    }
}

struct TitleView: View {
    let onPlay: () -> Void
    let onContinue: (LevelSpec) -> Void

    @StateObject private var demo = DemoDriver()
    @ObservedObject private var progress = GameProgress.shared
    @State private var showSettings = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Theme.bg.ignoresSafeArea()

                // The live farm fills the right side and fades into the dark on the left.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    SpriteView(scene: demo.scene, options: [.ignoresSiblingOrder])
                        .frame(width: geo.size.width * 0.62)
                        .overlay(
                            LinearGradient(stops: [.init(color: Theme.bg, location: 0), .init(color: Theme.bg.opacity(0.75), location: 0.18),
                                                   .init(color: .clear, location: 0.5)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea()

                leftColumn
                    .frame(width: max(280, geo.size.width * 0.46), alignment: .leading)
                    .padding(.leading, 26)
            }
            .overlay(alignment: .bottomTrailing) { codeTicker.padding(14) }
            .overlay(alignment: .topTrailing) {
                IconButton(symbol: "gearshape.fill", size: 40) { showSettings = true }
                    .accessibilityIdentifier("settings")
                    .padding(14)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .onAppear {
            demo.start()
            SoundFX.shared.setTrack(.farm)
        }
        .onDisappear { demo.stop() }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent))
                Text("A CODING GAME")
                    .font(Theme.mono(10, .bold))
                    .foregroundStyle(Theme.dim)
                    .tracking(2)
            }
            VStack(alignment: .leading, spacing: -4) {
                Text("COMPILE").font(Theme.mono(44, .heavy)).foregroundStyle(Theme.text)
                Text("& CONQUER").font(Theme.mono(44, .heavy)).foregroundStyle(Theme.accent)
            }
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            Text("Write real code. Command machines.\nConquer every map.")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)

            rankChip.padding(.top, 2)

            HStack(spacing: 10) {
                if let next = progress.nextLevel(), progress.allStars > 0 {
                    Button {
                        SoundFX.shared.play(.tap)
                        onContinue(next)
                    } label: {
                        Label("CONTINUE", systemImage: "play.fill").frame(minWidth: 120)
                    }
                    .buttonStyle(PillButtonStyle())
                    .accessibilityIdentifier("continue")
                    Button {
                        SoundFX.shared.play(.tap)
                        onPlay()
                    } label: {
                        Label("LEVELS", systemImage: "square.grid.2x2.fill")
                    }
                    .buttonStyle(PillButtonStyle(color: Theme.text, filled: false))
                    .accessibilityIdentifier("play")
                } else {
                    Button {
                        SoundFX.shared.play(.tap)
                        onPlay()
                    } label: {
                        Label("PLAY", systemImage: "play.fill").frame(minWidth: 150)
                    }
                    .buttonStyle(PillButtonStyle())
                    .accessibilityIdentifier("play")
                }
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
            Text(AppInfo.versionLabel)
                .font(Theme.mono(9))
                .foregroundStyle(Theme.dim.opacity(0.6))
                .padding(.bottom, 6)
        }
    }

    private var rankChip: some View {
        let rank = progress.rank
        return HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.gold)
            Text(rank.title.uppercased()).font(Theme.mono(11, .heavy)).foregroundStyle(Theme.text)
            HStack(spacing: 3) {
                Image(systemName: "star.fill").font(.system(size: 9))
                Text("\(rank.stars)").font(Theme.mono(11, .bold))
            }
            .foregroundStyle(Theme.gold)
            if let next = rank.next {
                Text("next rank at \(next)").font(Theme.mono(9)).foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.4)))
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
    }

    /// The program the drone on screen is running, with the current line lit up.
    private var codeTicker: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(DemoDriver.code.enumerated()), id: \.offset) { i, text in
                Text(text)
                    .font(Theme.mono(10, i == demo.line ? .bold : .regular))
                    .foregroundStyle(i == demo.line ? Color.black : Theme.text.opacity(0.75))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 4).fill(i == demo.line ? Theme.accent : Color.clear))
            }
        }
        .padding(8)
        .frame(width: 190)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.35), lineWidth: 1))
        .animation(.easeOut(duration: 0.12), value: demo.line)
    }
}
