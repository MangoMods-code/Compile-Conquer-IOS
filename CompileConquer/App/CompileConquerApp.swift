import SwiftUI

@main
struct CompileConquerApp: App {
    init() {
        SoundFX.shared.prepare()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

enum Route: Hashable {
    case worlds
    case levels(WorldInfo)
    case play(LevelSpec)
}

struct RootView: View {
    @State private var path: [Route] = RootView.startPath()

    /// UI tests can jump straight into a level with `-uitest.open <level id>`.
    private static func startPath() -> [Route] {
        guard let id = UserDefaults.standard.string(forKey: "uitest.open"),
              let level = WorldInfo.all.flatMap({ $0.levels }).first(where: { $0.id == id }),
              let world = WorldInfo.containing(level) else { return [] }
        return [.worlds, .levels(world), .play(level)]
    }
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $path) {
            TitleView(
                onPlay: { path.append(.worlds) },
                onContinue: { level in
                    // Build the whole trail so Back leads through the level map and worlds.
                    var trail: [Route] = [.worlds]
                    if let world = WorldInfo.containing(level) { trail.append(.levels(world)) }
                    trail.append(.play(level))
                    path = trail
                }
            )
            .navigationDestination(for: Route.self) { route in
                destination(route)
            }
        }
        .tint(Theme.accent)
        .onChange(of: scenePhase) { _, phase in
            // Pick the music back up when the app returns to the front.
            if phase == .active { SoundFX.shared.settingsChanged() }
        }
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .worlds:
            WorldSelectView { path.append(.levels($0)) }
        case .levels(let w):
            LevelSelectView(world: w) { path.append(.play($0)) }
        case .play(let level):
            let chapter = WorldInfo.containing(level)?.levels ?? []
            let next = chapter.firstIndex(of: level).flatMap { $0 + 1 < chapter.count ? chapter[$0 + 1] : nil }
            GameScreen(
                level: level,
                onExit: { if !path.isEmpty { path.removeLast() } },
                onNext: next.map { n -> () -> Void in { if !path.isEmpty { path[path.count - 1] = .play(n) } } }
            )
            .id(level.id)
        }
    }
}
