import SwiftUI
import SpriteKit

struct GameScreen: View {
    @StateObject private var session: GameSession
    let onExit: () -> Void
    let onNext: (() -> Void)?
    @State private var showHint = false
    @State private var tab = 0

    init(level: LevelSpec, onExit: @escaping () -> Void, onNext: (() -> Void)?) {
        _session = StateObject(wrappedValue: GameSession(level: level))
        self.onExit = onExit
        self.onNext = onNext
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    topBar
                    SpriteView(scene: session.scene, options: [.ignoresSiblingOrder])
                        .overlay(alignment: .center) { resultOverlay }
                        .overlay(alignment: .bottom) { failureBanner }
                }
                .frame(width: geo.size.width * 0.5)

                Rectangle().fill(Theme.line).frame(width: 1)

                rightPanel
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .ignoresSafeArea(.keyboard)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
    }

    // MARK: Map side

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: onExit) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.panelHi))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("FARM \(session.level.number)")
                    .font(Theme.mono(10, .bold)).foregroundStyle(Theme.accent)
                Text(session.level.title)
                    .font(Theme.mono(14, .bold)).foregroundStyle(Theme.text).lineLimit(1)
            }
            Spacer(minLength: 4)
            stat(icon: "leaf.fill", text: "\(session.wheat)/\(session.level.goal)", color: Theme.gold)
            stat(icon: "clock", text: "\(session.world.ticks)", color: Theme.text)
            Menu {
                Button { session.newMap() } label: { Label("New map", systemImage: "dice") }
                    .disabled(session.state.isActive)
                Text("Seed \(session.seedText)")
            } label: {
                Image(systemName: "dice.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.panelHi))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func stat(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(text).font(Theme.mono(13, .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Capsule().fill(Theme.panelHi))
    }

    @ViewBuilder private var resultOverlay: some View {
        if case .won(let stars, let ticks) = session.state {
            VStack(spacing: 10) {
                Text("LEVEL COMPLETE").font(Theme.mono(16, .heavy)).foregroundStyle(Theme.accent)
                StarsView(count: stars, size: 26)
                Text("\(ticks) ticks  ·  ★★★ at \(session.level.threeStarTicks) or less")
                    .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                HStack(spacing: 8) {
                    Button("Replay") { session.dismissResult() }
                        .buttonStyle(PillButtonStyle(filled: false))
                    if let onNext {
                        Button("Next ›", action: onNext).buttonStyle(PillButtonStyle())
                    } else {
                        Button("Levels", action: onExit).buttonStyle(PillButtonStyle())
                    }
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel.opacity(0.96)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.4), lineWidth: 1))
            .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder private var failureBanner: some View {
        if case .failed(let message) = session.state {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                Text(message).font(Theme.mono(11)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("OK") { session.dismissResult() }.font(Theme.mono(12, .bold)).foregroundStyle(Theme.accent)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel.opacity(0.96)))
            .padding(8)
        }
    }

    // MARK: Code side

    private var rightPanel: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Text(showHint ? "Hint: \(session.level.hint)" : session.level.brief)
                    .font(Theme.mono(11))
                    .foregroundStyle(showHint ? Theme.gold : Theme.dim)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { showHint.toggle() } label: {
                    Image(systemName: showHint ? "lightbulb.fill" : "lightbulb")
                        .foregroundStyle(Theme.gold)
                        .font(.system(size: 15))
                }
                Menu {
                    Button(role: .destructive) { session.restoreStarterCode() } label: {
                        Label("Restore starter code", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(session.state.isActive)
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Theme.dim).font(.system(size: 15))
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            fileTabs

            Group {
                if tab == 0 {
                    CodeEditor(text: Binding(get: { session.fullText }, set: { session.setFullText($0) }),
                               activeLine: session.activeLine,
                               errorLine: session.errorLine,
                               editable: !session.state.isActive,
                               lockedLength: (session.level.header as NSString).length,
                               commands: session.level.commands)
                } else {
                    CodeEditor(text: .constant(session.librarySource),
                               activeLine: nil, errorLine: nil, editable: false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
            .padding(.horizontal, 6)

            controls
            consoleView
        }
        .background(Theme.panel)
    }

    private var fileTabs: some View {
        HStack(spacing: 4) {
            tabButton("main.py", icon: "pencil", index: 0)
            tabButton("drone.py", icon: "lock.fill", index: 1)
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private func tabButton(_ title: String, icon: String, index: Int) -> some View {
        Button { tab = index } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
                Text(title).font(Theme.mono(12, .bold))
            }
            .foregroundStyle(tab == index ? Color.black : Theme.dim)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(tab == index ? Theme.accent : Theme.panelHi))
        }
        .buttonStyle(.plain)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button { tab = 0; session.runOrPause() } label: {
                Label(session.state == .running ? "Pause" : (session.state == .paused ? "Resume" : "Run"),
                      systemImage: session.state == .running ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle())

            Button { tab = 0; session.step() } label: { Image(systemName: "forward.frame.fill") }
                .buttonStyle(PillButtonStyle(color: Theme.text, filled: false))

            Button { session.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(PillButtonStyle(color: Theme.text, filled: false))

            Button { session.cycleSpeed() } label: { Text(session.speedLabel).frame(minWidth: 26) }
                .buttonStyle(PillButtonStyle(color: Theme.gold, filled: false))
        }
        .padding(.horizontal, 6)
    }

    private var consoleView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(session.console) { line in
                        Text(line.text)
                            .font(Theme.mono(10))
                            .foregroundStyle(color(for: line.kind))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(6)
            }
            .frame(height: 58)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
            .onChange(of: session.console.count) { _, _ in
                if let last = session.console.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private func color(for kind: ConsoleLine.Kind) -> Color {
        switch kind {
        case .info: return Theme.dim
        case .warning: return Theme.gold
        case .error: return Theme.danger
        case .success: return Theme.accent
        }
    }
}
