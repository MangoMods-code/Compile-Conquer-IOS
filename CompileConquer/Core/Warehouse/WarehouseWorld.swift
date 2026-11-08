import Foundation

enum FloorTile: Equatable {
    case floor
    case rack
    case bay(String)   // a drop-off bay that only accepts one color

    var walkable: Bool { self != .rack }
}

struct Crate: Equatable {
    var color: String
    /// Hidden crates show "?" until scanned.
    var hidden: Bool = false

    var visibleColor: String { hidden ? "?" : color }
}

/// Everything the loader can be told to do. One command = one tick.
enum LoaderCommand: Equatable {
    case move(Direction)
    case pick
    case drop
    case scan
    case wait
}

/// The state of one warehouse level. A value type, so resetting is copying.
struct WarehouseWorld {
    static let colors = ["red", "blue", "green", "yellow"]

    let width: Int
    let height: Int
    private(set) var tiles: [FloorTile]
    private(set) var crates: [Pos: Crate] = [:]
    private(set) var loader: Pos
    private(set) var facing: Direction = .north
    private(set) var carrying: Crate?
    private(set) var shipped = 0
    private(set) var ticks = 0

    init(width: Int, height: Int, loader: Pos) {
        self.width = width
        self.height = height
        self.tiles = Array(repeating: .floor, count: width * height)
        self.loader = loader
    }

    func inBounds(_ p: Pos) -> Bool { p.x >= 0 && p.y >= 0 && p.x < width && p.y < height }
    func tile(at p: Pos) -> FloorTile { tiles[p.y * width + p.x] }
    func isOpen(_ p: Pos) -> Bool { inBounds(p) && tile(at: p).walkable }

    /// Bay color -> position.
    var bays: [String: Pos] {
        var out: [String: Pos] = [:]
        for y in 0..<height { for x in 0..<width { if case .bay(let c) = tile(at: Pos(x: x, y: y)) { out[c] = Pos(x: x, y: y) } } }
        return out
    }

    // Generator helpers
    mutating func setTile(_ t: FloorTile, at p: Pos) { tiles[p.y * width + p.x] = t }
    mutating func putCrate(_ c: Crate, at p: Pos) { crates[p] = c }
    mutating func recolor(_ p: Pos, to color: String) { crates[p]?.color = color }

    mutating func perform(_ command: LoaderCommand) -> CommandOutcome {
        let outcome = apply(command)
        ticks += 1
        return outcome
    }

    private mutating func apply(_ command: LoaderCommand) -> CommandOutcome {
        switch command {
        case .move(let dir):
            facing = dir
            let next = loader.moved(dir)
            guard inBounds(next) else { return .bumped("The loader hit the warehouse wall going \(dir.rawValue).") }
            guard tile(at: next).walkable else { return .bumped("A rack blocks the way \(dir.rawValue).") }
            loader = next
            return .ok(note: nil)

        case .pick:
            if carrying != nil { return .warning("loader.carrying isn't None: the forks already hold a crate. drop() it first.") }
            guard let c = crates[loader] else { return .warning("No crate here, so loader.carrying stays None.") }
            crates[loader] = nil
            carrying = c
            return .ok(note: nil)

        case .drop:
            guard let c = carrying else { return .warning("loader.carrying is None: there's nothing to drop.") }
            switch tile(at: loader) {
            case .bay(let color):
                guard c.color == color else {
                    return .warning("This bay only takes \(color) crates, so the \(c.color) crate stays on the forks.")
                }
                carrying = nil
                shipped += 1
                return .ok(note: "+1 shipped")
            default:
                if crates[loader] != nil { return .warning("There's already a crate here.") }
                crates[loader] = c
                carrying = nil
                return .ok(note: nil)
            }

        case .scan:
            if crates[loader] != nil {
                crates[loader]!.hidden = false
                return .ok(note: "scan: \(crates[loader]!.color)")
            }
            if carrying != nil {
                carrying!.hidden = false
                return .ok(note: "scan: \(carrying!.color)")
            }
            return .ok(note: "scan: None")

        case .wait:
            return .ok(note: nil)
        }
    }

    /// What scan() returns right after scanning.
    var scannedColor: String? { crates[loader]?.color ?? carrying?.color }
}
