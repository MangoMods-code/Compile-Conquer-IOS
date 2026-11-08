import Foundation

/// A cell on a level's grid. (0,0) is the bottom-left corner; North is +y.
struct Pos: Hashable, Codable {
    var x: Int
    var y: Int

    func moved(_ dir: Direction) -> Pos {
        let d = dir.delta
        return Pos(x: x + d.dx, y: y + d.dy)
    }
}

enum Direction: String, CaseIterable, Codable {
    case north = "North", east = "East", south = "South", west = "West"

    var delta: (dx: Int, dy: Int) {
        switch self {
        case .north: return (0, 1)
        case .east: return (1, 0)
        case .south: return (0, -1)
        case .west: return (-1, 0)
        }
    }

    /// Accepts "North", "north", "NORTH".
    init?(name: String) {
        guard let d = Direction.allCases.first(where: { $0.rawValue.lowercased() == name.lowercased() }) else { return nil }
        self = d
    }
}

/// Small, fast, deterministic random generator so a seed always rebuilds the same map.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Seeds are shown to the player as short codes like "K7Q2-9XMA" so a map can be shared or replayed.
enum SeedCode {
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    static func random() -> UInt64 { UInt64.random(in: 1...UInt64(1) << 40) }

    static func format(_ seed: UInt64) -> String {
        var v = seed
        var chars: [Character] = []
        for _ in 0..<8 {
            chars.append(alphabet[Int(v % 32)])
            v /= 32
        }
        let s = String(chars)
        return String(s.prefix(4)) + "-" + String(s.suffix(4))
    }
}
