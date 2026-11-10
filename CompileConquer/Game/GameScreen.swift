import SwiftUI
import SpriteKit

/// The level screen: the live map on the left, main.py and the run controls on the right.
struct GameScreen: View {
    @StateObject private var session: GameSession
    let onExit: () -> Void
    let onNext: (() -> Void)?

    @State private var showHint = false
    @State private var jump: EditorJump?
    @State private var showSettings = false
    @State private var showHandbook = false
    @State private var panelTab = 0
    @State private var panelExpanded = false
    @ObservedObject private var settings = AppSettings.shared

    init(level: LevelSpec, onExit: @escaping () -> Void, onNext: (() -> Void)?) {
        _session = StateObject(wrappedValue: GameSession(level: level))
        self.onExit = onExit
        self.onNext = onNext
    }

    private var level: LevelSpec { session.level }
    private var tint: Color { Theme.tint(level.world) }
    private var mapColor: Color {
        level.world == .farm ? Color(red: 0.11, green: 0.23, blue: 0.12) : Color(red: 0.1, green: 0.11, blue: 0.13)
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                mapSide
                    .frame(width: geo.size.width * 0.47)
                Rectangle().fill(Color.black.opacity(0.5)).frame(width: 1)
                codeSide
            }
        }
        .background(
            HStack(spacing: 0) {
                mapColor
                Theme.panel
            }
            .ignoresSafeArea()
        )
        .ignoresSafeArea(.keyboard)
        .overlay {
            if case .won(let info) = session.state {
                WinOverlay(info: info, level: level, tint: tint,
                           onReplay: { session.dismissResult() },
                           onReview: { session.seek(session.totalTicks) },
                           onNext: onNext, onExit: onExit)
                    .transition(.opacity)
            }
        }
        .overlay {
            if session.showIntro {
                IntroCard(level: level, par: session.threeStarTicks, tint: tint) {
                    withAnimation(.easeOut(duration: 0.2)) { session.dismissIntro() }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: session.state)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showHandbook) { HandbookView(level: level) }
        .onAppear {
            session.setTopInset(48)
            SoundFX.shared.setTrack(level.world == .farm ? .farm : .warehouse)
            // First visit: start at the top so the setup gets read. After that, open at your code.
            let firstVisit = !GameProgress.shared.hasSavedCode(for: level)
            jump = EditorJump(line: firstVisit ? 1 : session.firstCodeLine)
        }
        .onDisappear { session.stop() }
    }

    // MARK: Map side

    private var mapSide: some View {
        ZStack(alignment: .top) {
            SpriteView(scene: session.scene, options: [.ignoresSiblingOrder])
            LevelHUD(session: session, tint: tint, onExit: onExit)
        }
        .overlay(alignment: .bottomLeading) {
            if let info = session.inspected {
                TileInspector(info: info) { session.clearInspection() }
                    .padding(8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if case .failed(let message) = session.state {
                FailBanner(message: message, canReview: session.hasRun,
                           onReview: { session.seek(session.totalTicks) },
                           onDismiss: { session.dismissResult() })
                    .padding(8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: session.inspected)
        .clipped()
    }

    // MARK: Code side

    private var codeSide: some View {
        VStack(spacing: 5) {
            fileBar
            if showHint {
                Text(level.hint)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.gold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.gold.opacity(0.1)))
                    .padding(.horizontal, 6)
                    .transition(.opacity)
            }
            CodeEditor(text: Binding(get: { session.fullText }, set: { session.setFullText($0) }),
                       activeLine: session.activeLine,
                       errorLine: session.errorLine,
                       editable: !session.state.isActive,
                       lockedLength: session.lockedLength,
                       commands: level.commands,
                       names: level.setupNames,
                       jump: jump,
                       fontSize: CGFloat(settings.codeFontSize))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
                .padding(.horizontal, 6)
            if session.hasRun { timeline }
            controls
            BottomPanel(session: session, tab: $panelTab, expanded: $panelExpanded)
        }
        .padding(.top, 5)
        .background(Theme.panel)
    }

    private var fileBar: some View {
        HStack(spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "doc.text.fill").font(.system(size: 10, weight: .bold))
                Text("main.py").font(Theme.mono(12, .bold))
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.panelHi))

            jumpButton("Setup", icon: "lock.fill", line: 1)
            jumpButton("Your code", icon: "pencil", line: session.firstCodeLine)
            Spacer(minLength: 2)
            IconButton(symbol: "info", size: 28, tint: Theme.blue) { session.showIntro = true }
                .accessibilityIdentifier("brief")
            IconButton(symbol: "book.fill", size: 28, tint: Theme.purple) { showHandbook = true }
                .accessibilityIdentifier("handbook")
            IconButton(symbol: showHint ? "lightbulb.fill" : "lightbulb", size: 28, tint: Theme.gold) {
                withAnimation(.easeOut(duration: 0.15)) { showHint.toggle() }
            }
            .accessibilityIdentifier("hint")
            Menu {
                Button(role: .destructive) { session.restoreStarterCode() } label: {
                    Label("Restore starter code", systemImage: "arrow.uturn.backward")
                }
                .disabled(session.state.isActive)
                Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.panelHi))
            }
        }
        .padding(.horizontal, 8)
    }

    private func jumpButton(_ title: String, icon: String, line: Int) -> some View {
        Button { jump = EditorJump(line: line) } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
                Text(title).font(Theme.mono(11, .bold))
            }
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier(title)
    }

    /// Scrub through the recorded run, forwards or backwards.
    private var timeline: some View {
        HStack(spacing: 6) {
            Button { session.stepBack() } label: {
                Image(systemName: "backward.frame.fill").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(session.tick > 0 ? Theme.text : Theme.dim.opacity(0.4))
                    .frame(width: 26, height: 22)
            }
            .disabled(session.tick == 0)
            .accessibilityIdentifier("stepBack")
            Slider(value: Binding(get: { Double(session.tick) }, set: { session.seek(Int($0.rounded())) }),
                   in: 0...Double(max(1, session.totalTicks)), step: 1)
                .tint(tint)
                .controlSize(.mini)
            Text("\(session.tick)/\(session.totalTicks)")
                .font(Theme.mono(10, .bold))
                .foregroundStyle(Theme.dim)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
    }

    private var runTitle: String {
        switch session.state {
        case .running: return "Pause"
        case .paused: return "Resume"
        case .compiling: return "Checking…"
        default: return "Run"
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button { session.runOrPause() } label: {
                Label(runTitle, systemImage: session.state == .running ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle(color: tint))
            .accessibilityIdentifier("Run")

            Button { session.step() } label: { Image(systemName: "forward.frame.fill") }
                .buttonStyle(PillButtonStyle(color: Theme.text, filled: false))
                .accessibilityIdentifier("step")

            Button { session.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(PillButtonStyle(color: Theme.text, filled: false))
                .accessibilityIdentifier("reset")

            Button { session.cycleSpeed() } label: { Text(session.speedLabel).frame(minWidth: 28) }
                .buttonStyle(PillButtonStyle(color: Theme.gold, filled: false))
                .accessibilityIdentifier("speed")
        }
        .padding(.horizontal, 6)
    }
}
