import SwiftUI

/// The bar over the top of the map: back, level name, goal counters, tick counter, new map.
struct LevelHUD: View {
    @ObservedObject var session: GameSession
    let tint: Color
    let onExit: () -> Void

    private var level: LevelSpec { session.level }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                IconButton(symbol: "chevron.left", size: 32, fill: Color.black.opacity(0.55), action: onExit)
                    .accessibilityIdentifier("back")
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(level.worldLabel) \(level.number) · \(level.concept.uppercased())")
                        .font(Theme.mono(9, .bold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(level.title)
                        .font(Theme.mono(14, .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                Menu {
                    Button { session.newMap() } label: { Label("New map", systemImage: "dice") }
                        .disabled(session.state.isActive)
                    Text("Map code \(session.seedText)")
                } label: {
                    Image(systemName: "dice.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                        .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                }
                .accessibilityIdentifier("mapMenu")
            }
            HStack(spacing: 6) {
                ForEach(session.goalItems) { item in
                    GoalChip(item: item, world: level.world, showLabel: session.goalItems.count <= 2)
                }
                Spacer(minLength: 4)
                tickChip
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.75), Color.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
        )
    }

    /// Ticks used so far, with the stars this run would earn if it finished right now.
    private var tickChip: some View {
        let ticks = session.world.ticks
        let stars = session.stars(forTicks: ticks)
        return HStack(spacing: 5) {
            Image(systemName: "clock.fill").font(.system(size: 9, weight: .bold))
            Text("\(ticks)").font(Theme.mono(12, .bold)).monospacedDigit()
            Text("/ \(session.threeStarTicks)").font(Theme.mono(10)).foregroundStyle(.white.opacity(0.6))
            StarsView(count: stars, size: 8)
        }
        .foregroundStyle(.white)
        .fixedSize()
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
        .accessibilityIdentifier("ticks")
    }
}

struct GoalChip: View {
    let item: GoalItem
    let world: WorldKind
    var showLabel = true

    private var color: Color {
        switch item.label {
        case "Wheat": return Theme.gold
        case "Carrot": return Color(red: 1, green: 0.58, blue: 0.2)
        case "Pumpkin": return Color(red: 0.95, green: 0.45, blue: 0.12)
        default: return Theme.gold
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if world == .farm {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(showLabel ? item.label : String(item.label.prefix(1)))
                    .font(Theme.mono(10))
                    .foregroundStyle(.white.opacity(0.75))
            } else {
                Image(systemName: "shippingbox.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            }
            Text("\(item.have)/\(item.need)")
                .font(Theme.mono(12, .bold))
                .monospacedDigit()
                .foregroundStyle(item.done ? Theme.accent : .white)
            if item.done {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.accent)
            }
        }
        .fixedSize()
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .overlay(Capsule().stroke(item.done ? Theme.accent.opacity(0.6) : Theme.line, lineWidth: 1))
        .accessibilityLabel("\(item.label) \(item.have) of \(item.need)")
    }
}

/// Shown when a map tile is tapped: the code that reads the tile and what it holds.
struct TileInspector: View {
    let info: TileInfo
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "scope").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.blue)
                Text(info.code).font(Theme.mono(11, .bold)).foregroundStyle(Theme.blue)
                Spacer(minLength: 8)
                Image(systemName: "xmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.dim)
            }
            ForEach(info.rows, id: \.name) { row in
                HStack(spacing: 6) {
                    Text(row.name).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                    Text(row.value).font(Theme.mono(10, .bold)).foregroundStyle(Theme.text)
                }
            }
        }
        .padding(9)
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.blue.opacity(0.5), lineWidth: 1))
        .onTapGesture(perform: onClose)
    }
}

struct FailBanner: View {
    let message: String
    let canReview: Bool
    let onReview: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                Text(message)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Spacer()
                if canReview {
                    Button("Review run", action: onReview)
                        .buttonStyle(PillButtonStyle(color: Theme.blue, filled: false))
                }
                Button("Fix code", action: onDismiss)
                    .buttonStyle(PillButtonStyle(color: Theme.danger))
                    .accessibilityIdentifier("fixCode")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.danger.opacity(0.5), lineWidth: 1))
    }
}

/// Console output and the Variables watch, under the run controls.
struct BottomPanel: View {
    @ObservedObject var session: GameSession
    @Binding var tab: Int
    @Binding var expanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                tabButton("Console", icon: "terminal.fill", index: 0)
                tabButton(session.watch.isEmpty ? "Variables" : "Variables \(session.watch.count)", icon: "tablecells", index: 1)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 30, height: 20)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)

            Group {
                if tab == 0 { consoleView } else { variablesView }
            }
            .frame(height: expanded ? 132 : 48)
        }
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.38)))
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }

    private func tabButton(_ title: String, icon: String, index: Int) -> some View {
        Button { tab = index } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 8, weight: .bold))
                Text(title).font(Theme.mono(10, .bold))
            }
            .foregroundStyle(tab == index ? Theme.text : Theme.dim.opacity(0.7))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(tab == index ? Theme.panelHi : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab.\(title.prefix(3))")
    }

    private var consoleView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(session.console) { line in
                        Text(line.kind == .output ? "› " + line.text : line.text)
                            .font(Theme.mono(10))
                            .foregroundStyle(color(for: line.kind))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .onChange(of: session.console.count) { _, _ in
                if let last = session.console.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onChange(of: expanded) { _, _ in
                if let last = session.console.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    /// The player's variables at this point of the run.
    private var variablesView: some View {
        ScrollView {
            if session.watch.isEmpty {
                Text(session.hasRun ? "No variables yet at this point of the run." : "Run your code to watch your variables change step by step.")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(session.watch.enumerated()), id: \.offset) { _, v in
                        HStack(alignment: .top, spacing: 6) {
                            Text(v.name)
                                .font(Theme.mono(10, .bold))
                                .foregroundStyle(v.scope == nil ? Theme.blue : Theme.purple)
                            Text("=").font(Theme.mono(10)).foregroundStyle(Theme.dim)
                            Text(v.value).font(Theme.mono(10)).foregroundStyle(Theme.text)
                            Spacer(minLength: 0)
                            if let scope = v.scope {
                                Text("in \(scope)()").font(Theme.mono(9)).foregroundStyle(Theme.dim)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    private func color(for kind: ConsoleLine.Kind) -> Color {
        switch kind {
        case .info: return Theme.dim
        case .output: return Theme.text
        case .warning: return Theme.gold
        case .error: return Theme.danger
        case .success: return Theme.accent
        }
    }
}
