import SwiftUI

enum Theme {
    static let bg = Color(red: 0.055, green: 0.067, blue: 0.09)
    static let panel = Color(red: 0.09, green: 0.11, blue: 0.14)
    static let panelHi = Color(red: 0.13, green: 0.15, blue: 0.19)
    static let line = Color.white.opacity(0.08)
    static let accent = Color(red: 0.24, green: 0.86, blue: 0.52)
    static let gold = Color(red: 0.98, green: 0.78, blue: 0.3)
    static let danger = Color(red: 1, green: 0.42, blue: 0.38)
    static let text = Color(white: 0.92)
    static let dim = Color(white: 0.55)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Faint grid behind menus, like a level map.
struct GridBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 32
            var path = Path()
            var x: CGFloat = 0
            while x < size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y < size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            ctx.stroke(path, with: .color(Theme.accent.opacity(0.05)), lineWidth: 1)
        }
        .background(Theme.bg)
        .ignoresSafeArea()
    }
}

struct StarsView: View {
    let count: Int
    var size: CGFloat = 12
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < count ? "star.fill" : "star")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(i < count ? Theme.gold : Theme.dim.opacity(0.6))
            }
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(14, .bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(filled ? Color.black : color)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(filled ? color : color.opacity(0.12))
            )
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(filled ? 0 : 0.5), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

enum AppInfo {
    static var versionLabel: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(v) (build \(b))"
    }
}
