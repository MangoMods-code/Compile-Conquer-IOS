import SwiftUI

// MARK: - Title

struct TitleView: View {
    let onPlay: () -> Void
    @State private var bob = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            GridBackground()
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                Image(systemName: "chevron.right.square.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .offset(y: bob ? -6 : 6)
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: bob)
                VStack(spacing: 4) {
                    Text("COMPILE")
                        .font(Theme.mono(40, .heavy))
                    Text("& CONQUER")
                        .font(Theme.mono(40, .heavy))
                        .foregroundStyle(Theme.accent)
                }
                .foregroundStyle(Theme.text)
                Text("Write code. Command machines. Conquer the map.")
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.dim)
                Button(action: onPlay) {
                    Label("PLAY", systemImage: "play.fill").frame(minWidth: 160)
                }
                .buttonStyle(PillButtonStyle())
                .padding(.top, 6)
                Spacer(minLength: 0)
                Text(AppInfo.versionLabel)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.dim.opacity(0.7))
                    .padding(.bottom, 8)
            }
            .padding()
        }
        .overlay(alignment: .topTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Theme.panelHi))
            }
            .padding(16)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { bob = true }
    }
}

// MARK: - Shared header

struct MenuHeader: View {
    let title: String
    let subtitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.panelHi))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.mono(20, .heavy)).foregroundStyle(Theme.text)
                Text(subtitle).font(Theme.mono(11)).foregroundStyle(Theme.dim)
            }
            Spacer()
        }
    }
}

struct LockedBadge: View {
    var body: some View {
        Label("SOON", systemImage: "lock.fill")
            .font(Theme.mono(10, .bold))
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Theme.panelHi))
    }
}

// MARK: - Campaigns

struct CampaignSelectView: View {
    let onPick: (Campaign) -> Void

    var body: some View {
        ZStack {
            GridBackground()
            VStack(alignment: .leading, spacing: 14) {
                MenuHeader(title: "Choose a language", subtitle: "Each language is its own campaign.")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Campaign.all) { c in
                            Button { onPick(c) } label: { card(c) }
                                .buttonStyle(.plain)
                                .disabled(!c.available)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func card(_ c: Campaign) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: c.symbol)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(c.available ? Theme.accent : Theme.dim)
                Spacer()
                if !c.available { LockedBadge() }
            }
            Spacer(minLength: 0)
            Text(c.name).font(Theme.mono(22, .heavy)).foregroundStyle(c.available ? Theme.text : Theme.dim)
            Text(c.tagline).font(Theme.mono(11)).foregroundStyle(Theme.dim).lineLimit(2)
        }
        .padding(16)
        .frame(width: 210, height: 190)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(c.available ? Theme.accent.opacity(0.5) : Theme.line, lineWidth: 1))
        .opacity(c.available ? 1 : 0.65)
    }
}

// MARK: - Worlds

struct WorldSelectView: View {
    let campaign: Campaign
    let onPick: (WorldInfo) -> Void
    @ObservedObject private var progress = GameProgress.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ZStack {
            GridBackground()
            VStack(alignment: .leading, spacing: 14) {
                MenuHeader(title: "\(campaign.name) campaign", subtitle: "Pick a world. Every world gives you a different machine.")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(WorldInfo.all) { w in
                            Button { onPick(w) } label: { card(w) }
                                .buttonStyle(.plain)
                                .disabled(!progress.isUnlocked(w))
                        }
                    }
                    .padding(.vertical, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func card(_ w: WorldInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: w.symbol)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(w.available ? Theme.gold : Theme.dim)
                Spacer()
                if progress.isUnlocked(w) {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").font(.system(size: 10))
                        Text("\(progress.totalStars(w.levels))/\(w.levels.count * 3)").font(Theme.mono(11, .bold))
                    }
                    .foregroundStyle(Theme.gold)
                } else if w.available {
                    Label("FINISH PREVIOUS", systemImage: "lock.fill")
                        .font(Theme.mono(9, .bold))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.panelHi))
                } else {
                    LockedBadge()
                }
            }
            Spacer(minLength: 0)
            Text(w.name).font(Theme.mono(19, .heavy)).foregroundStyle(w.available ? Theme.text : Theme.dim)
            Text(w.machine.uppercased()).font(Theme.mono(10, .bold)).foregroundStyle(Theme.accent.opacity(w.available ? 1 : 0.5))
            Text(w.blurb).font(Theme.mono(11)).foregroundStyle(Theme.dim).lineLimit(2)
        }
        .padding(14)
        .frame(width: 190, height: 180)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(w.available ? Theme.gold.opacity(0.45) : Theme.line, lineWidth: 1))
        .opacity(w.available ? 1 : 0.65)
    }
}

// MARK: - Levels

struct LevelSelectView: View {
    let world: WorldInfo
    let onPick: (LevelSpec) -> Void
    @ObservedObject private var progress = GameProgress.shared

    var body: some View {
        ZStack {
            GridBackground()
            VStack(alignment: .leading, spacing: 14) {
                MenuHeader(title: world.name, subtitle: "Maps are generated fresh each time you play.")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(world.levels) { level in
                            let unlocked = progress.isUnlocked(level, in: world.levels)
                            Button { onPick(level) } label: { tile(level, unlocked: unlocked) }
                                .buttonStyle(.plain)
                                .disabled(!unlocked)
                        }
                        comingSoon
                    }
                    .padding(.vertical, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func tile(_ level: LevelSpec, unlocked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(format: "%02d", level.number))
                    .font(Theme.mono(28, .heavy))
                    .foregroundStyle(unlocked ? Theme.accent : Theme.dim)
                Spacer()
                if !unlocked { Image(systemName: "lock.fill").foregroundStyle(Theme.dim) }
            }
            Text(level.title).font(Theme.mono(14, .bold)).foregroundStyle(unlocked ? Theme.text : Theme.dim).lineLimit(1)
            Spacer(minLength: 0)
            StarsView(count: progress.stars(for: level.id), size: 14)
        }
        .padding(14)
        .frame(width: 150, height: 150)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(unlocked ? Theme.accent.opacity(0.4) : Theme.line, lineWidth: 1))
        .opacity(unlocked ? 1 : 0.6)
    }

    private var comingSoon: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 22, weight: .bold))
            Text("More levels\ncoming soon").font(Theme.mono(11, .bold)).multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.dim)
        .frame(width: 150, height: 150)
        .background(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}
