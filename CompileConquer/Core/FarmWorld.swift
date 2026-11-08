import Foundation

enum Ground: Codable {
    case grass, soil, rock, water

    var walkable: Bool { self == .grass || self == .soil }
}

enum CropKind: String, Codable, CaseIterable {
    case wheat = "Wheat"
}

struct Crop: Codable {
    var kind: CropKind
    var growth: Int = 0
    var growTime: Int

    var ripe: Bool { growth >= growTime }
    /// 0...1 for drawing.
    var progress: Double { min(1, Double(growth) / Double(max(1, growTime))) }
}

struct Tile: Codable {
    var ground: Ground
    var crop: Crop? = nil
    var wetTicks: Int = 0
}

/// Everything the drone can be told to do. One command = one tick of game time.
enum DroneCommand: Equatable {
    case move(Direction)
    case till
    case plant(CropKind)
    case water
    case harvest
    case wait

    var name: String {
        switch self {
        case .move: return "move"
        case .till: return "till"
        case .plant: return "plant"
        case .water: return "water"
        case .harvest: return "harvest"
        case .wait: return "wait"
        }
    }
}

/// What happened when a command ran, for the map animation and the console.
enum CommandOutcome {
    case ok(note: String?)
    /// The command did nothing, with a reason. The program keeps running.
    case warning(String)
    case bumped(String)
}

/// The state of one farm level. A value type, so resetting a level is just copying the starting world.
struct FarmWorld {
    let width: Int
    let height: Int
    private(set) var tiles: [Tile]
    private(set) var drone: Pos
    private(set) var facing: Direction = .north
    private(set) var inventory: [CropKind: Int] = [:]
    private(set) var ticks = 0
    let growTime: Int

    init(width: Int, height: Int, ground: Ground = .grass, drone: Pos, growTime: Int) {
        self.width = width
        self.height = height
        self.tiles = Array(repeating: Tile(ground: ground), count: width * height)
        self.drone = drone
        self.growTime = growTime
    }

    func inBounds(_ p: Pos) -> Bool { p.x >= 0 && p.y >= 0 && p.x < width && p.y < height }

    func tile(at p: Pos) -> Tile { tiles[p.y * width + p.x] }

    mutating func setGround(_ g: Ground, at p: Pos) {
        tiles[p.y * width + p.x].ground = g
    }

    func count(of kind: CropKind) -> Int { inventory[kind, default: 0] }

    /// Runs one command, then lets one tick of time pass (crops grow, water dries).
    mutating func perform(_ command: DroneCommand) -> CommandOutcome {
        let outcome = apply(command)
        advanceTime()
        return outcome
    }

    private mutating func apply(_ command: DroneCommand) -> CommandOutcome {
        let i = drone.y * width + drone.x
        switch command {
        case .move(let dir):
            facing = dir
            let next = drone.moved(dir)
            guard inBounds(next) else { return .bumped("The drone hit the edge of the field going \(dir.rawValue).") }
            let g = tile(at: next).ground
            guard g.walkable else {
                return .bumped(g == .rock ? "A rock blocks the way \(dir.rawValue)." : "Water blocks the way \(dir.rawValue).")
            }
            drone = next
            return .ok(note: nil)

        case .till:
            switch tiles[i].ground {
            case .grass:
                tiles[i].ground = .soil
                return .ok(note: nil)
            case .soil:
                return .warning("This tile is already soil.")
            default:
                return .warning("Can't till here.")
            }

        case .plant(let kind):
            guard tiles[i].ground == .soil else { return .warning("plant() needs soil. Use till() on grass first.") }
            guard tiles[i].crop == nil else { return .warning("Something is already planted here.") }
            tiles[i].crop = Crop(kind: kind, growTime: growTime)
            return .ok(note: nil)

        case .water:
            guard tiles[i].ground == .soil else { return .warning("Watering only helps soil.") }
            tiles[i].wetTicks = 8
            return .ok(note: nil)

        case .harvest:
            guard let crop = tiles[i].crop else { return .warning("tile.crop is None here, so there was nothing to harvest.") }
            tiles[i].crop = nil
            guard crop.ripe else {
                return .warning("Unripe! crop.age was \(crop.growth) but GROW_TIME is \(crop.growTime), so the wheat was lost.")
            }
            inventory[crop.kind, default: 0] += 1
            return .ok(note: "+1 \(crop.kind.rawValue)")

        case .wait:
            return .ok(note: nil)
        }
    }

    private mutating func advanceTime() {
        ticks += 1
        for i in tiles.indices {
            let wet = tiles[i].wetTicks > 0
            if tiles[i].crop != nil, !(tiles[i].crop!.ripe) {
                tiles[i].crop!.growth += wet ? 2 : 1
            }
            if wet { tiles[i].wetTicks -= 1 }
        }
    }
}
