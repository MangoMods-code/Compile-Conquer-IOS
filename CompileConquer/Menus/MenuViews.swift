import SwiftUI

// MARK: - Shared header

struct MenuHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 12) {
            IconButton(symbol: "chevron.left", size: 38) { dismiss() }
                .accessibilityIdentifier("back")
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.mono(20, .heavy)).foregroundStyle(Theme.text)
                Text(subtitle).font(Theme.mono(11)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

struct StarCount: View {
    let have: Int
    let of: Int
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill").font(.system(size: 11, weight: .bold))
            Text("\(have)/\(of)").font(Theme.mono(13, .bold)).monospacedDigit()
        }
        .foregroundStyle(Theme.gold)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Theme.gold.opacity(0.12)))
    }
}

// MARK: - Worlds (with the language campaigns across the top)

struct WorldSelectView: View {
    let onPick: (WorldInfo) -> Void
    @ObservedObject private var progress = GameProgress.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var campaign = Campaign.all[0]

    var body: some View {
        ZStack {
            GridBackground()
            VStack(alignment: .leading, spacing: 12) {
                MenuHeader(title: "\(campaign.name) campaign", subtitle: "Every world is a new place with a new machine to program.") {
                    StarCount(have: progress.allStars, of: WorldInfo.all.reduce(0) { $0 + $1.levels.count * 3 })
                }
                campaignTabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(WorldInfo.all.enumerated()), id: \.element.id) { i, w in
                            Button {
                                SoundFX.shared.play(.tap)
                                onPick(w)
                            } label: { card(w, index: i) }
                                .buttonStyle(PressStyle())
                                .disabled(!progress.isUnlocked(w))
                                .accessibilityIdentifier("world.\(w.id)")
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { SoundFX.shared.setTrack(.farm) }
    }

    /// One tab per language. Only Python is playable for now.
    private var campaignTabs: some View {
        HStack(spacing: 8) {
            ForEach(Campaign.all) { c in
                HStack(spacing: 5) {
                    Image(systemName: c.available ? c.symbol : "lock.fill").font(.system(size: 10, weight: .bold))
                    Text(c.name).font(Theme.mono(12, .bold))
                    if !c.available { Text("SOON").font(Theme.mono(8, .bold)).foregroundStyle(Theme.dim.opacity(0.7)) }
                }
                .foregroundStyle(c == campaign ? Color.black : (c.available ? Theme.text : Theme.dim.opacity(0.7)))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(c == campaign ? Theme.accent : Theme.panelHi.opacity(c.available ? 1 : 0.5)))
                .accessibilityIdentifier("campaign.\(c.id)")
            }
            Spacer()
        }
    }

    private func card(_ w: WorldInfo, index: Int) -> some View {
        let unlocked = progress.isUnlocked(w)
        let total = w.levels.count * 3
        let have = progress.totalStars(w.levels)
        let tint = Theme.tint(w.kind)
        return VStack(alignment: .leading, spacing: 0) {
            WorldThumbnail(world: w, height: 96)
                .overlay(LinearGradient(colors: [.clear, Theme.panel.opacity(0.9)], startPoint: .center, endPoint: .bottom))
                .overlay(alignment: .topLeading) {
                    Text("WORLD \(index + 1)")
                        .font(Theme.mono(9, .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .padding(8)
                }
                .overlay {
                    if !unlocked {
                        ZStack {
                            Color.black.opacity(0.55)
                            Image(systemName: "lock.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
                .saturation(unlocked ? 1 : 0.3)

            VStack(alignment: .leading, spacing: 5) {
                Text(w.name).font(Theme.mono(17, .heavy)).foregroundStyle(unlocked ? Theme.text : Theme.dim)
                Text(w.machine.uppercased()).font(Theme.mono(9, .bold)).foregroundStyle(tint.opacity(unlocked ? 1 : 0.5))
                Text(w.blurb)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
                if unlocked {
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule().fill(tint).frame(width: geo.size.width * CGFloat(have) / CGFloat(max(1, total)))
                            }
                        }
                        .frame(height: 5)
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill").font(.system(size: 8))
                            Text("\(have)/\(total)").font(Theme.mono(10, .bold)).monospacedDigit()
                        }
                        .foregroundStyle(Theme.gold)
                    }
                } else {
                    Text(w.available ? "Finish the world before it to unlock" : "Coming soon")
                        .font(Theme.mono(9, .bold))
                        .foregroundStyle(Theme.dim.opacity(0.8))
                }
            }
            .padding(12)
        }
        .frame(width: 214, height: 236)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(unlocked ? tint.opacity(0.5) : Theme.line, lineWidth: 1))
        .opacity(unlocked ? 1 : 0.75)
    }
}

// MARK: - Levels (a path through the world)

struct LevelSelectView: View {
    let world: WorldInfo
    let onPick: (LevelSpec) -> Void
    @ObservedObject private var progress = GameProgress.shared
    @State private var pulse = false

    private let spacing: CGFloat = 148
    private let pathHeight: CGFloat = 190
    private var tint: Color { Theme.tint(world.kind) }

    /// The level to play next: the first open one without a star.
    private var current: LevelSpec? {
        world.levels.first { progress.isUnlocked($0, in: world.levels) && progress.stars(for: $0.id) == 0 }
    }

    /// How far down each node sits; alternating gives the path its wave.
    private func drop(_ i: Int) -> CGFloat { i % 2 == 0 ? 0 : 36 }

    /// The middle of a node's circle, in the row's coordinates.
    private func center(_ i: Int) -> CGPoint {
        CGPoint(x: (CGFloat(i) + 0.5) * spacing, y: drop(i) + 39)
    }

    var body: some View {
        ZStack {
            GridBackground(glow: tint)
            VStack(alignment: .leading, spacing: 8) {
                MenuHeader(title: world.name, subtitle: "\(world.machine) · maps are generated, so no two plays are the same") {
                    let tidyTotal = world.levels.filter { $0.tidyLines != nil }.count
                    if tidyTotal > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "scissors").font(.system(size: 10, weight: .bold))
                            Text("\(world.levels.filter { progress.isTidy($0.id) }.count)/\(tidyTotal)").font(Theme.mono(13, .bold))
                        }
                        .foregroundStyle(Theme.blue)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.blue.opacity(0.12)))
                    }
                    StarCount(have: progress.totalStars(world.levels), of: world.levels.count * 3)
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 0)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(world.levels.enumerated()), id: \.element.id) { i, level in
                                node(level, index: i)
                                    .frame(width: spacing)
                                    .padding(.top, drop(i))
                                    .id(level.id)
                            }
                        }
                        .frame(height: pathHeight, alignment: .top)
                        .background(alignment: .topLeading) { trail }
                        .padding(.horizontal, 24)
                    }
                    .onAppear {
                        if let c = current { proxy.scrollTo(c.id, anchor: .center) }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            SoundFX.shared.setTrack(world.kind == .warehouse ? .warehouse : .farm)
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    /// The dotted path joining the level nodes; the part already cleared is solid.
    private var trail: some View {
        Canvas { ctx, _ in
            for i in 0..<max(0, world.levels.count - 1) {
                let a = center(i), b = center(i + 1)
                var p = Path()
                p.move(to: a)
                p.addCurve(to: b, control1: CGPoint(x: a.x + spacing * 0.5, y: a.y), control2: CGPoint(x: b.x - spacing * 0.5, y: b.y))
                let cleared = progress.stars(for: world.levels[i].id) > 0
                ctx.stroke(p, with: .color(cleared ? tint.opacity(0.8) : Color.white.opacity(0.16)),
                           style: StrokeStyle(lineWidth: cleared ? 4 : 3, lineCap: .round, dash: cleared ? [] : [2, 9]))
            }
        }
        .allowsHitTesting(false)
    }

    private func node(_ level: LevelSpec, index: Int) -> some View {
        let unlocked = progress.isUnlocked(level, in: world.levels)
        let stars = progress.stars(for: level.id)
        let isCurrent = current == level
        return Button {
            SoundFX.shared.play(.tap)
            onPick(level)
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    if isCurrent {
                        Circle().stroke(tint.opacity(0.5), lineWidth: 3)
                            .frame(width: 74, height: 74)
                            .scaleEffect(pulse ? 1.14 : 0.96)
                            .opacity(pulse ? 0.15 : 0.9)
                    }
                    Circle()
                        .fill(stars > 0 ? tint : (unlocked ? Theme.panelHi : Theme.panel))
                        .frame(width: 58, height: 58)
                        .overlay(Circle().stroke(unlocked ? tint : Theme.line, lineWidth: stars > 0 ? 0 : 2))
                        .shadow(color: (stars > 0 || isCurrent) ? tint.opacity(0.45) : .clear, radius: 10)
                    if unlocked {
                        Text("\(level.number)")
                            .font(Theme.mono(22, .heavy))
                            .foregroundStyle(stars > 0 ? Color.black : Theme.text)
                    } else {
                        Image(systemName: "lock.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.dim.opacity(0.7))
                    }
                }
                .frame(width: 78, height: 78)
                .overlay(alignment: .topTrailing) {
                    if progress.isTidy(level.id) {
                        Image(systemName: "scissors")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.black)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Theme.blue))
                            .offset(x: -4, y: 4)
                    }
                }

                StarsView(count: stars, size: 12)
                    .opacity(unlocked ? 1 : 0.35)
                Text(level.title)
                    .font(Theme.mono(11, .bold))
                    .foregroundStyle(unlocked ? Theme.text : Theme.dim)
                    .lineLimit(1)
                Text(level.concept)
                    .font(Theme.mono(9))
                    .foregroundStyle(unlocked ? Theme.purple : Theme.dim.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(width: 140)
        }
        .buttonStyle(PressStyle())
        .disabled(!unlocked)
        .accessibilityIdentifier("level.\(level.id)")
    }
}
