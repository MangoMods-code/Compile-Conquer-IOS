import SwiftUI

@main
struct CompileConquerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

enum Route: Hashable {
    case campaigns
    case worlds(Campaign)
    case levels(Campaign, WorldInfo)
    case play(LevelSpec)
}

struct RootView: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            TitleView { path.append(.campaigns) }
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
        }
        .tint(Theme.accent)
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .campaigns:
            CampaignSelectView { path.append(.worlds($0)) }
        case .worlds(let c):
            WorldSelectView(campaign: c) { path.append(.levels(c, $0)) }
        case .levels(_, let w):
            LevelSelectView(world: w) { path.append(.play($0)) }
        case .play(let level):
            let chapter = FarmChapter.levels
            let next = chapter.firstIndex(of: level).flatMap { $0 + 1 < chapter.count ? chapter[$0 + 1] : nil }
            GameScreen(
                level: level,
                onExit: { path.removeLast() },
                onNext: next.map { n -> () -> Void in { path[path.count - 1] = .play(n) } }
            )
            .id(level.id)
        }
    }
}
