import SpriteKit
import UIKit

/// Draws a FarmWorld top-down and animates the drone between ticks.
final class FarmScene: SKScene {
    private var world: FarmWorld?
    private let board = SKNode()
    private var tileNodes: [SKSpriteNode] = []
    private var cropNodes: [Int: SKNode] = [:]
    private var cropKeys: [Int: String] = [:]
    private var droneRoot = SKNode()
    private var droneBody = SKNode()
    private var tileSize: CGFloat = 40
    private var origin = CGPoint.zero

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.07, green: 0.09, blue: 0.11, alpha: 1)
        addChild(board)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        if let w = world { rebuild(w) }
    }

    // MARK: Public

    /// Shows a world instantly (level start, reset, new map).
    func load(_ w: FarmWorld) {
        world = w
        rebuild(w)
    }

    /// Shows the world after one command, animating what changed.
    func apply(_ w: FarmWorld, command: DroneCommand, outcome: CommandOutcome, duration: TimeInterval) {
        let old = world
        world = w
        guard let old, old.width == w.width, old.height == w.height, !tileNodes.isEmpty else {
            rebuild(w)
            return
        }
        refreshTiles(w)

        let move = max(0.05, duration * 0.8)
        switch outcome {
        case .bumped:
            if case .move(let d) = command {
                let dx = CGFloat(d.delta.dx) * tileSize * 0.22
                let dy = CGFloat(d.delta.dy) * tileSize * 0.22
                droneRoot.run(.sequence([.moveBy(x: dx, y: dy, duration: move * 0.4), .moveBy(x: -dx, y: -dy, duration: move * 0.4)]))
            }
            float("!", color: UIColor(red: 1, green: 0.42, blue: 0.35, alpha: 1))
        case .warning:
            float("?", color: UIColor(red: 1, green: 0.78, blue: 0.3, alpha: 1))
        case .ok(let note):
            if let note { float(note, color: UIColor(red: 0.95, green: 0.82, blue: 0.35, alpha: 1)) }
        }

        let target = center(of: w.drone)
        if droneRoot.position != target {
            droneRoot.removeAction(forKey: "move")
            let a = SKAction.move(to: target, duration: move)
            a.timingMode = .easeInEaseOut
            droneRoot.run(a, withKey: "move")
        }
        turnDrone(to: w.facing, duration: move * 0.6)

        // Little action pulses so you can see work happening.
        switch command {
        case .till, .plant, .water, .harvest:
            droneBody.run(.sequence([.scale(to: 0.82, duration: move * 0.35), .scale(to: 1.0, duration: move * 0.35)]))
            if command == .water { splash(at: target) }
        default: break
        }
    }

    // MARK: Layout

    private func rebuild(_ w: FarmWorld) {
        board.removeAllChildren()
        tileNodes = []
        cropNodes = [:]
        cropKeys = [:]

        let pad: CGFloat = 16
        tileSize = floor(min((size.width - pad * 2) / CGFloat(w.width), (size.height - pad * 2) / CGFloat(w.height)))
        tileSize = max(8, tileSize)
        origin = CGPoint(x: (size.width - tileSize * CGFloat(w.width)) / 2,
                         y: (size.height - tileSize * CGFloat(w.height)) / 2)

        // Board frame.
        let frameRect = CGRect(x: origin.x - 4, y: origin.y - 4, width: tileSize * CGFloat(w.width) + 8, height: tileSize * CGFloat(w.height) + 8)
        let frame = SKShapeNode(rect: frameRect, cornerRadius: 6)
        frame.fillColor = UIColor(red: 0.16, green: 0.12, blue: 0.09, alpha: 1)
        frame.strokeColor = .clear
        board.addChild(frame)

        for y in 0..<w.height {
            for x in 0..<w.width {
                let n = SKSpriteNode(color: .green, size: CGSize(width: tileSize - 1, height: tileSize - 1))
                n.position = center(of: Pos(x: x, y: y))
                n.zPosition = 1
                board.addChild(n)
                tileNodes.append(n)
            }
        }
        refreshTiles(w)

        droneRoot = makeDrone()
        droneRoot.position = center(of: w.drone)
        droneRoot.zPosition = 10
        board.addChild(droneRoot)
        turnDrone(to: w.facing, duration: 0)
    }

    private func center(of p: Pos) -> CGPoint {
        CGPoint(x: origin.x + (CGFloat(p.x) + 0.5) * tileSize, y: origin.y + (CGFloat(p.y) + 0.5) * tileSize)
    }

    // MARK: Tiles & crops

    private func refreshTiles(_ w: FarmWorld) {
        for y in 0..<w.height {
            for x in 0..<w.width {
                let i = y * w.width + x
                let t = w.tile(at: Pos(x: x, y: y))
                let checker = (x + y) % 2 == 0
                let node = tileNodes[i]
                switch t.ground {
                case .grass, .rock:
                    node.color = checker ? UIColor(red: 0.31, green: 0.60, blue: 0.28, alpha: 1) : UIColor(red: 0.28, green: 0.56, blue: 0.25, alpha: 1)
                case .soil:
                    if t.wetTicks > 0 {
                        node.color = checker ? UIColor(red: 0.31, green: 0.20, blue: 0.13, alpha: 1) : UIColor(red: 0.29, green: 0.18, blue: 0.12, alpha: 1)
                    } else {
                        node.color = checker ? UIColor(red: 0.48, green: 0.31, blue: 0.20, alpha: 1) : UIColor(red: 0.44, green: 0.28, blue: 0.18, alpha: 1)
                    }
                case .water:
                    node.color = UIColor(red: 0.19, green: 0.44, blue: 0.66, alpha: 1)
                }

                let key = renderKey(t)
                if cropKeys[i] != key {
                    cropKeys[i] = key
                    cropNodes[i]?.removeFromParent()
                    cropNodes[i] = nil
                    if let deco = decoration(for: t) {
                        deco.position = node.position
                        deco.zPosition = 2
                        board.addChild(deco)
                        cropNodes[i] = deco
                    }
                }
            }
        }
    }

    private func renderKey(_ t: Tile) -> String {
        switch t.ground {
        case .rock: return "rock"
        case .water: return "water"
        default: break
        }
        guard let c = t.crop else { return "none" }
        if c.ripe { return "ripe" }
        return "grow\(min(2, Int(c.progress * 3)))"
    }

    private func decoration(for t: Tile) -> SKNode? {
        let s = tileSize
        switch t.ground {
        case .rock:
            let n = SKNode()
            let rock = SKShapeNode(ellipseOf: CGSize(width: s * 0.62, height: s * 0.48))
            rock.fillColor = UIColor(white: 0.55, alpha: 1)
            rock.strokeColor = UIColor(white: 0.32, alpha: 1)
            rock.lineWidth = max(1, s * 0.04)
            let shine = SKShapeNode(ellipseOf: CGSize(width: s * 0.2, height: s * 0.1))
            shine.fillColor = UIColor(white: 0.75, alpha: 1)
            shine.strokeColor = .clear
            shine.position = CGPoint(x: -s * 0.1, y: s * 0.08)
            n.addChild(rock)
            n.addChild(shine)
            return n
        case .water:
            let n = SKNode()
            for k in 0..<2 {
                let r = SKShapeNode(ellipseOf: CGSize(width: s * (0.5 - CGFloat(k) * 0.2), height: s * (0.14 - CGFloat(k) * 0.04)))
                r.strokeColor = UIColor(red: 0.55, green: 0.78, blue: 0.95, alpha: 0.7)
                r.fillColor = .clear
                r.lineWidth = max(1, s * 0.03)
                r.position = CGPoint(x: CGFloat(k) * s * 0.12, y: CGFloat(k) * s * -0.18)
                n.addChild(r)
            }
            n.run(.repeatForever(.sequence([.fadeAlpha(to: 0.5, duration: 1.2), .fadeAlpha(to: 1, duration: 1.2)])))
            return n
        default:
            break
        }
        guard let crop = t.crop else { return nil }
        let n = SKNode()
        let ripe = crop.ripe
        let stage = ripe ? 3 : min(2, Int(crop.progress * 3))
        let heights: [CGFloat] = [0.12, 0.24, 0.36, 0.40]
        let h = s * heights[stage]
        let stalkColor = ripe ? UIColor(red: 0.78, green: 0.62, blue: 0.22, alpha: 1) : UIColor(red: 0.45, green: 0.85, blue: 0.35, alpha: 1)
        for dx in [-0.2, 0.0, 0.2] {
            let x = s * CGFloat(dx)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: -s * 0.2))
            path.addLine(to: CGPoint(x: x + s * 0.02, y: -s * 0.2 + h))
            let stalk = SKShapeNode(path: path)
            stalk.strokeColor = stalkColor
            stalk.lineWidth = max(1.5, s * 0.05)
            stalk.lineCap = .round
            n.addChild(stalk)
            if ripe {
                let head = SKShapeNode(ellipseOf: CGSize(width: s * 0.11, height: s * 0.2))
                head.fillColor = UIColor(red: 0.96, green: 0.78, blue: 0.28, alpha: 1)
                head.strokeColor = UIColor(red: 0.72, green: 0.52, blue: 0.15, alpha: 1)
                head.lineWidth = 1
                head.position = CGPoint(x: x + s * 0.02, y: -s * 0.2 + h)
                n.addChild(head)
            }
        }
        if ripe {
            n.run(.repeatForever(.sequence([.rotate(toAngle: 0.05, duration: 0.8), .rotate(toAngle: -0.05, duration: 0.8)])))
        }
        n.setScale(0.6)
        n.run(.scale(to: 1, duration: 0.15))
        return n
    }

    // MARK: Drone

    private func makeDrone() -> SKNode {
        let s = tileSize
        let root = SKNode()

        let shadow = SKShapeNode(ellipseOf: CGSize(width: s * 0.6, height: s * 0.2))
        shadow.fillColor = UIColor(white: 0, alpha: 0.3)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -s * 0.3)
        root.addChild(shadow)

        let body = SKNode()
        for (ox, oy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            let arm = SKShapeNode(rectOf: CGSize(width: s * 0.06, height: s * 0.36), cornerRadius: s * 0.02)
            arm.fillColor = UIColor(red: 0.27, green: 0.31, blue: 0.37, alpha: 1)
            arm.strokeColor = .clear
            arm.position = CGPoint(x: s * 0.13 * CGFloat(ox), y: s * 0.13 * CGFloat(oy))
            arm.zRotation = CGFloat(ox * oy) * -.pi / 4
            body.addChild(arm)

            let rotorPos = CGPoint(x: s * 0.25 * CGFloat(ox), y: s * 0.25 * CGFloat(oy))
            let disc = SKShapeNode(circleOfRadius: s * 0.13)
            disc.fillColor = UIColor(red: 0.67, green: 0.73, blue: 0.79, alpha: 0.35)
            disc.strokeColor = UIColor(red: 0.67, green: 0.73, blue: 0.79, alpha: 0.6)
            disc.lineWidth = 1
            disc.position = rotorPos
            body.addChild(disc)

            let blade = SKShapeNode(rectOf: CGSize(width: s * 0.24, height: s * 0.03), cornerRadius: s * 0.015)
            blade.fillColor = UIColor(white: 0.9, alpha: 0.9)
            blade.strokeColor = .clear
            blade.position = rotorPos
            blade.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 0.18)))
            body.addChild(blade)
        }

        let hull = SKShapeNode(rectOf: CGSize(width: s * 0.3, height: s * 0.3), cornerRadius: s * 0.08)
        hull.fillColor = UIColor(red: 0.16, green: 0.18, blue: 0.23, alpha: 1)
        hull.strokeColor = UIColor(red: 0.24, green: 0.86, blue: 0.52, alpha: 1)
        hull.lineWidth = max(1.5, s * 0.04)
        body.addChild(hull)

        // The "eye" shows which way the drone faces.
        let eye = SKShapeNode(circleOfRadius: s * 0.05)
        eye.fillColor = UIColor(red: 0.24, green: 0.86, blue: 0.52, alpha: 1)
        eye.strokeColor = .clear
        eye.position = CGPoint(x: 0, y: s * 0.08)
        eye.name = "eye"
        body.addChild(eye)

        body.run(.repeatForever(.sequence([.moveBy(x: 0, y: s * 0.04, duration: 0.6), .moveBy(x: 0, y: -s * 0.04, duration: 0.6)])))
        root.addChild(body)
        droneBody = body
        return root
    }

    private func turnDrone(to d: Direction, duration: TimeInterval) {
        let angle: CGFloat
        switch d {
        case .north: angle = 0
        case .west: angle = .pi / 2
        case .south: angle = .pi
        case .east: angle = -.pi / 2
        }
        if duration <= 0 {
            droneBody.zRotation = angle
        } else {
            droneBody.run(.rotate(toAngle: angle, duration: duration, shortestUnitArc: true))
        }
    }

    // MARK: Effects

    private func float(_ text: String, color: UIColor) {
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = text
        label.fontSize = max(11, tileSize * 0.28)
        label.fontColor = color
        label.position = CGPoint(x: droneRoot.position.x, y: droneRoot.position.y + tileSize * 0.35)
        label.zPosition = 20
        board.addChild(label)
        label.run(.sequence([.group([.moveBy(x: 0, y: tileSize * 0.4, duration: 0.7), .fadeOut(withDuration: 0.7)]), .removeFromParent()]))
    }

    private func splash(at p: CGPoint) {
        for k in 0..<5 {
            let drop = SKShapeNode(circleOfRadius: max(1.5, tileSize * 0.04))
            drop.fillColor = UIColor(red: 0.55, green: 0.8, blue: 1, alpha: 0.9)
            drop.strokeColor = .clear
            drop.position = p
            drop.zPosition = 9
            board.addChild(drop)
            let a = CGFloat(k) / 5 * .pi * 2
            drop.run(.sequence([.group([.moveBy(x: cos(a) * tileSize * 0.3, y: sin(a) * tileSize * 0.3 - tileSize * 0.15, duration: 0.35), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
        }
    }
}
