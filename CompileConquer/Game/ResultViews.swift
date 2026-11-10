import SwiftUI

/// The card shown when a level is beaten: stars pop in one by one, with the run's numbers.
struct WinOverlay: View {
    let info: WinInfo
    let level: LevelSpec
    let tint: Color
    let onReplay: () -> Void
    let onReview: () -> Void
    let onNext: (() -> Void)?
    let onExit: () -> Void

    @State private var shown = 0
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            ConfettiView().ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 12) {
                Text("LEVEL COMPLETE")
                    .font(Theme.mono(18, .heavy))
                    .foregroundStyle(tint)
                    .accessibilityIdentifier("levelComplete")
                Text(level.title).font(Theme.mono(12)).foregroundStyle(Theme.dim)

                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: i < info.stars ? "star.fill" : "star")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(i < shown ? Theme.gold : Theme.dim.opacity(0.35))
                            .scaleEffect(i < shown ? 1 : 0.6)
                            .rotationEffect(.degrees(i < shown ? 0 : -25))
                            .animation(.spring(response: 0.35, dampingFraction: 0.5), value: shown)
                    }
                }
                .padding(.vertical, 2)

                VStack(spacing: 6) {
                    statRow(icon: "clock.fill", title: "Ticks", value: "\(info.ticks)",
                            note: info.stars == 3 ? "3 stars at \(info.par) or less" : "3 stars need \(info.par) or less",
                            good: info.stars == 3)
                    if let limit = info.tidyLimit {
                        statRow(icon: "scissors", title: "Lines of code", value: "\(info.lines)",
                                note: info.tidy ? "Tidy bonus earned (\(limit) or fewer)" : "Tidy bonus: \(limit) lines or fewer",
                                good: info.tidy)
                    } else {
                        statRow(icon: "text.alignleft", title: "Lines of code", value: "\(info.lines)", note: "", good: true)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.3)))

                if info.newBest {
                    Chip(text: "NEW BEST", icon: "arrow.up", color: Theme.gold, filled: true)
                }

                HStack(spacing: 8) {
                    Button("Replay", action: onReplay)
                        .buttonStyle(PillButtonStyle(color: Theme.text, filled: false))
                    Button("Review run", action: onReview)
                        .buttonStyle(PillButtonStyle(color: Theme.blue, filled: false))
                    if let onNext {
                        Button(action: onNext) { Label("Next level", systemImage: "arrow.right") }
                            .buttonStyle(PillButtonStyle(color: tint))
                            .accessibilityIdentifier("next")
                    } else {
                        Button(action: onExit) { Label("World complete", systemImage: "flag.checkered") }
                            .buttonStyle(PillButtonStyle(color: tint))
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 430)
            .card(radius: 20, stroke: tint.opacity(0.5), fill: Theme.panel.opacity(0.97))
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { appeared = true }
            let sounds: [SoundFX.Effect] = [.star1, .star2, .star3]
            for i in 0..<min(3, info.stars) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45 + Double(i) * 0.32) {
                    shown = i + 1
                    SoundFX.shared.play(sounds[i])
                    Haptics.tap()
                }
            }
        }
    }

    private func statRow(icon: String, title: String, value: String, note: String, good: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(good ? Theme.accent : Theme.dim)
                .frame(width: 16)
            Text(title).font(Theme.mono(12)).foregroundStyle(Theme.dim)
            Text(value).font(Theme.mono(14, .heavy)).foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            Text(note).font(Theme.mono(10)).foregroundStyle(good ? Theme.accent : Theme.dim)
        }
    }
}

/// A briefing shown the first time a level opens (and from the info button).
struct IntroCard: View {
    let level: LevelSpec
    let par: Int
    let tint: Color
    let onStart: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture(perform: onStart)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("\(level.worldLabel) \(level.number)")
                        .font(Theme.mono(11, .heavy))
                        .foregroundStyle(tint)
                    Chip(text: level.concept, icon: "graduationcap.fill", color: Theme.purple)
                    Spacer()
                }
                Text(level.title)
                    .font(Theme.mono(24, .heavy))
                    .foregroundStyle(Theme.text)
                Text(level.brief)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.text.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    rule(icon: "flag.fill", color: tint, text: level.goalSummary)
                    rule(icon: "star.fill", color: Theme.gold, text: "3 stars: finish in \(par) ticks or less. Every command costs 1 tick.")
                    if let tidy = level.tidyLines {
                        rule(icon: "scissors", color: Theme.blue, text: "Tidy bonus: solve it in \(tidy) lines of code or fewer.")
                    }
                    if level.rerollsEachRun {
                        rule(icon: "dice.fill", color: Theme.purple, text: "This map changes every time you press Run.")
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.3)))

                HStack {
                    Text("Tap a tile on the map to inspect it.")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.dim)
                    Spacer()
                    Button(action: onStart) { Label("Start", systemImage: "play.fill") }
                        .buttonStyle(PillButtonStyle(color: tint))
                        .accessibilityIdentifier("intro.start")
                }
            }
            .padding(20)
            .frame(maxWidth: 470)
            .card(radius: 20, stroke: tint.opacity(0.5), fill: Theme.panel.opacity(0.98))
        }
    }

    private func rule(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(text)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Paper confetti falling across the screen, drawn in one canvas.
struct ConfettiView: View {
    private struct Piece {
        let x: Double        // 0...1 across the screen
        let delay: Double
        let speed: Double
        let sway: Double
        let size: Double
        let spin: Double
        let color: Color
    }

    private let pieces: [Piece]
    private let start = Date()

    init(count: Int = 70) {
        let colors: [Color] = [Theme.accent, Theme.gold, Theme.blue, Theme.purple, Theme.danger, .white]
        var rng = SeededRNG(seed: 99)
        pieces = (0..<count).map { _ in
            Piece(x: Double.random(in: 0...1, using: &rng),
                  delay: Double.random(in: 0...0.9, using: &rng),
                  speed: Double.random(in: 0.28...0.6, using: &rng),
                  sway: Double.random(in: 0.01...0.05, using: &rng),
                  size: Double.random(in: 5...10, using: &rng),
                  spin: Double.random(in: 2...7, using: &rng),
                  color: colors.randomElement(using: &rng) ?? .white)
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                guard t < 4.5 else { return }
                for p in pieces {
                    let local = t - p.delay
                    guard local > 0 else { continue }
                    let y = -20 + local * p.speed * size.height
                    guard y < size.height + 20 else { continue }
                    let x = (p.x + sin(local * 3 + p.x * 20) * p.sway) * size.width
                    let fade = min(1, max(0, (4.5 - t) / 1.0))
                    var piece = ctx
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(local * p.spin))
                    piece.opacity = fade
                    let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)
                    piece.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(p.color))
                }
            }
        }
    }
}
