import SwiftUI
import UIKit

enum Theme {
    static let bg = Color(red: 0.047, green: 0.059, blue: 0.082)
    static let panel = Color(red: 0.086, green: 0.106, blue: 0.141)
    static let panelHi = Color(red: 0.133, green: 0.157, blue: 0.2)
    static let line = Color.white.opacity(0.09)
    static let accent = Color(red: 0.24, green: 0.86, blue: 0.52)
    static let gold = Color(red: 0.99, green: 0.78, blue: 0.28)
    static let danger = Color(red: 1, green: 0.42, blue: 0.38)
    static let blue = Color(red: 0.38, green: 0.68, blue: 1)
    static let purple = Color(red: 0.78, green: 0.52, blue: 0.98)
    static let text = Color(white: 0.93)
    static let dim = Color(white: 0.58)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// The signature color of a world.
    static func tint(_ world: WorldKind?) -> Color {
        switch world {
        case .farm: return accent
        case .warehouse: return gold
        case nil: return dim
        }
    }
}

/// Faint grid behind menus, like a level map, with a soft glow in one corner.
struct GridBackground: View {
    var glow: Color = Theme.accent

    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 32
            var path = Path()
            var x: CGFloat = 0
            while x < size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y < size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            ctx.stroke(path, with: .color(Color.white.opacity(0.03)), lineWidth: 1)
        }
        .background(
            ZStack {
                Theme.bg
                RadialGradient(colors: [glow.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
                RadialGradient(colors: [Theme.blue.opacity(0.10), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 480)
            }
        )
        .ignoresSafeArea()
    }
}

struct StarsView: View {
    let count: Int
    var size: CGFloat = 12
    var body: some View {
        HStack(spacing: size * 0.16) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < count ? "star.fill" : "star")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(i < count ? Theme.gold : Theme.dim.opacity(0.5))
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
                RoundedRectangle(cornerRadius: 11)
                    .fill(filled ? color : color.opacity(0.12))
            )
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(color.opacity(filled ? 0 : 0.45), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Cards and tiles that sink slightly when pressed.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// A round icon button used in the HUD and headers.
struct IconButton: View {
    let symbol: String
    var size: CGFloat = 34
    var tint: Color = Theme.text
    var fill: Color = Theme.panelHi
    let action: () -> Void

    var body: some View {
        Button {
            SoundFX.shared.play(.tap)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
    }
}

/// A small rounded label with an optional icon.
struct Chip: View {
    let text: String
    var icon: String? = nil
    var color: Color = Theme.accent
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
            Text(text).font(Theme.mono(10, .bold))
        }
        .foregroundStyle(filled ? Color.black : color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(filled ? color : color.opacity(0.14)))
    }
}

extension View {
    /// The standard dark card look.
    func card(radius: CGFloat = 16, stroke: Color = Theme.line, fill: Color = Theme.panel) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(stroke, lineWidth: 1))
    }
}

enum Haptics {
    static func tap() {
        guard AppSettings.shared.haptics else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func thud() {
        guard AppSettings.shared.haptics else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    static func success() {
        guard AppSettings.shared.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard AppSettings.shared.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

enum AppInfo {
    static var versionLabel: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(v) (build \(b))"
    }
}
