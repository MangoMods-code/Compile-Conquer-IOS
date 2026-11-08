import SpriteKit
import UIKit

/// Draws a WarehouseWorld top-down and animates the loader between ticks.
final class WarehouseScene: SKScene, WorldRenderer {
    private var world: WarehouseWorld?
    private let background = SKSpriteNode()
    private let board = SKNode()
    private var tileNodes: [SKSpriteNode] = []
    private var crateNodes: [Pos: SKSpriteNode] = [:]
    private var crateKeys: [Pos: String] = [:]
    private var loaderRoot = SKNode()
    private var loaderBody = SKNode()
    private var carriedNode = SKSpriteNode()
    private var tileSize: CGFloat = 40
    private var origin = CGPoint.zero
    private var builtSize = CGSize.zero

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.1, green: 0.11, blue: 0.13, alpha: 1)
        background.zPosition = -10
        addChild(background)
        addChild(board)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        if let w = world, size.width > 10, size.height > 10 { rebuild(w) }
    }

    // MARK: WorldRenderer

    func load(_ state: WorldState) {
        guard case .warehouse(let w) = state else { return }
        world = w
        rebuild(w)
    }

    func apply(_ state: WorldState, action: WorldAction, outcome: CommandOutcome, duration: TimeInterval) {
        guard case .warehouse(let w) = state, case .warehouse(let command) = action else { return }
        let old = world
        world = w
        guard let old, old.width == w.width, !tileNodes.isEmpty else { rebuild(w); return }

        let move = max(0.05, duration * 0.8)
        let target = center(of: w.loader)
        let here = center(of: old.loader)

        switch outcome {
        case .bumped:
            if case .move(let d) = command {
                let dx = CGFloat(d.delta.dx) * tileSize * 0.2
                let dy = CGFloat(d.delta.dy) * tileSize * 0.2
                loaderRoot.run(.sequence([.moveBy(x: dx, y: dy, duration: move * 0.35), .moveBy(x: -dx, y: -dy, duration: move * 0.45)]))
                sparks(at: CGPoint(x: here.x + dx * 2.2, y: here.y + dy * 2.2))
            }
            float("clunk!", color: UIColor(red: 1, green: 0.45, blue: 0.38, alpha: 1))
        case .warning:
            float("?", color: UIColor(red: 1, green: 0.78, blue: 0.3, alpha: 1))
        case .ok(let note):
            if let note, !note.hasPrefix("scan") {
                float(note, color: UIColor(red: 0.45, green: 0.95, blue: 0.6, alpha: 1))
            }
        }

        switch (command, outcome) {
        case (.pick, .ok):
            liftCarried(from: here, duration: move)
        case (.drop, .ok(let note)):
            if note != nil {
                ship(at: here, duration: move)
            } else {
                setCarried(w.carrying)
            }
        case (.scan, .ok):
            scanBeam(at: here, duration: move, color: w.scannedColor)
        default:
            break
        }

        refreshCrates(w, animated: true)
        if case .pick = command {} else if case .drop = command {} else { setCarried(w.carrying) }

        if loaderRoot.position != target {
            loaderRoot.removeAction(forKey: "move")
            let a = SKAction.move(to: target, duration: move)
            a.timingMode = .easeInEaseOut
            loaderRoot.run(a, withKey: "move")
        }
        turn(to: w.facing, duration: move * 0.5)
    }

    // MARK: Layout

    private func rebuild(_ w: WarehouseWorld) {
        board.removeAllChildren()
        tileNodes = []
        crateNodes = [:]
        crateKeys = [:]

        let margin = max(26, min(size.width, size.height) * 0.09)
        tileSize = max(12, floor(min((size.width - margin * 2) / CGFloat(w.width), (size.height - margin * 2) / CGFloat(w.height))))
        origin = CGPoint(x: ((size.width - tileSize * CGFloat(w.width)) / 2).rounded(),
                         y: ((size.height - tileSize * CGFloat(w.height)) / 2).rounded())
        if builtSize != size { WarehouseArt.clearCache(); builtSize = size }

        let fieldUIKit = CGRect(x: origin.x, y: size.height - origin.y - tileSize * CGFloat(w.height),
                                width: tileSize * CGFloat(w.width), height: tileSize * CGFloat(w.height))
        background.texture = WarehouseArt.surroundings(size: size, field: fieldUIKit, tile: tileSize)
        background.size = size
        background.position = CGPoint(x: size.width / 2, y: size.height / 2)

        for y in 0..<w.height {
            for x in 0..<w.width {
                let p = Pos(x: x, y: y)
                let n = SKSpriteNode(texture: groundTexture(w, p), size: CGSize(width: tileSize, height: tileSize))
                n.position = center(of: p)
                n.zPosition = 1
                board.addChild(n)
                tileNodes.append(n)
            }
        }

        // Ceiling lights: soft pools that flicker now and then.
        for k in 0..<max(2, w.width / 3) {
            let light = SKSpriteNode(texture: WarehouseArt.glow(UIColor(red: 1, green: 0.97, blue: 0.85, alpha: 0.22), key: "light", tileSize * 3))
            light.blendMode = .add
            light.position = CGPoint(x: origin.x + tileSize * (CGFloat(k) * 3 + 1.5), y: origin.y + tileSize * CGFloat(w.height) * 0.6)
            light.zPosition = 6
            board.addChild(light)
            light.run(.repeatForever(.sequence([
                .wait(forDuration: Double.random(in: 3...7)),
                .fadeAlpha(to: 0.5, duration: 0.05), .fadeAlpha(to: 1, duration: 0.08),
            ])))
        }

        refreshCrates(w, animated: false)

        loaderRoot = makeLoader()
        loaderRoot.position = center(of: w.loader)
        loaderRoot.zPosition = 10
        board.addChild(loaderRoot)
        setCarried(w.carrying)
        turn(to: w.facing, duration: 0)
    }

    private func center(of p: Pos) -> CGPoint {
        CGPoint(x: origin.x + (CGFloat(p.x) + 0.5) * tileSize, y: origin.y + (CGFloat(p.y) + 0.5) * tileSize)
    }

    private func groundTexture(_ w: WarehouseWorld, _ p: Pos) -> SKTexture {
        let v = abs((p.x * 73_856_093) ^ (p.y * 19_349_663)) % 4
        switch w.tile(at: p) {
        case .floor: return WarehouseArt.concrete(v, tileSize)
        case .rack: return WarehouseArt.rack(v % 3, tileSize)
        case .bay(let c): return WarehouseArt.bay(c, tileSize)
        }
    }

    private func refreshCrates(_ w: WarehouseWorld, animated: Bool) {
        for (p, node) in crateNodes where w.crates[p] == nil {
            node.removeFromParent()
            crateNodes[p] = nil
            crateKeys[p] = nil
        }
        for (p, c) in w.crates {
            let key = "\(c.color)-\(c.hidden)"
            if crateKeys[p] == key { continue }
            let wasThere = crateKeys[p] != nil
            crateKeys[p] = key
            let tex = WarehouseArt.crate(c.color, hidden: c.hidden, tileSize)
            if let node = crateNodes[p] {
                node.texture = tex
                if animated && wasThere { node.run(.sequence([.scale(to: 1.15, duration: 0.08), .scale(to: 1, duration: 0.12)])) }
            } else {
                let node = SKSpriteNode(texture: tex, size: CGSize(width: tileSize, height: tileSize))
                node.position = center(of: p)
                node.zPosition = 3
                board.addChild(node)
                crateNodes[p] = node
                if animated {
                    node.setScale(0.7)
                    node.run(.scale(to: 1, duration: 0.15))
                }
            }
        }
    }

    // MARK: Loader

    private func makeLoader() -> SKNode {
        let d = tileSize * 0.95
        let root = SKNode()
        let shadow = SKSpriteNode(texture: WarehouseArt.softShadow(d), size: CGSize(width: d * 1.05, height: d * 1.05))
        shadow.position = CGPoint(x: tileSize * 0.05, y: -tileSize * 0.06)
        shadow.zPosition = -1
        root.addChild(shadow)

        let body = SKNode()
        body.addChild(SKSpriteNode(texture: WarehouseArt.loader(d), size: CGSize(width: d, height: d)))

        // Crate riding on the forks.
        carriedNode = SKSpriteNode(color: .clear, size: CGSize(width: d * 0.62, height: d * 0.62))
        carriedNode.position = CGPoint(x: 0, y: d * 0.3)
        carriedNode.zPosition = 2
        carriedNode.isHidden = true
        body.addChild(carriedNode)

        // Amber beacon on the roof.
        let beacon = SKSpriteNode(texture: WarehouseArt.glow(UIColor(red: 1, green: 0.62, blue: 0.1, alpha: 1), key: "beacon", d * 0.35),
                                  size: CGSize(width: d * 0.35, height: d * 0.35))
        beacon.position = CGPoint(x: 0, y: -d * 0.32)
        beacon.blendMode = .add
        beacon.zPosition = 3
        beacon.run(.repeatForever(.sequence([.fadeAlpha(to: 0.25, duration: 0.45), .fadeAlpha(to: 1, duration: 0.45)])))
        body.addChild(beacon)

        root.addChild(body)
        loaderBody = body
        return root
    }

    private func setCarried(_ crate: Crate?) {
        guard let crate else { carriedNode.isHidden = true; return }
        carriedNode.texture = WarehouseArt.crate(crate.color, hidden: crate.hidden, tileSize)
        carriedNode.isHidden = false
    }

    private func turn(to d: Direction, duration: TimeInterval) {
        let angle: CGFloat
        switch d {
        case .north: angle = 0
        case .west: angle = .pi / 2
        case .south: angle = .pi
        case .east: angle = -.pi / 2
        }
        if duration <= 0 { loaderBody.zRotation = angle }
        else { loaderBody.run(.rotate(toAngle: angle, duration: duration, shortestUnitArc: true)) }
    }

    // MARK: Effects

    private func liftCarried(from point: CGPoint, duration: TimeInterval) {
        setCarried(world?.carrying)
        carriedNode.setScale(0.6)
        carriedNode.run(.scale(to: 1, duration: duration * 0.5))
    }

    private func ship(at point: CGPoint, duration: TimeInterval) {
        guard let tex = carriedNode.texture else { setCarried(nil); return }
        setCarried(nil)
        let ghost = SKSpriteNode(texture: tex, size: CGSize(width: tileSize * 0.62, height: tileSize * 0.62))
        ghost.position = point
        ghost.zPosition = 9
        board.addChild(ghost)
        ghost.run(.sequence([
            .group([.scale(to: 0.2, duration: duration * 0.7), .fadeOut(withDuration: duration * 0.7), .rotate(byAngle: 0.6, duration: duration * 0.7)]),
            .removeFromParent(),
        ]))
        let ring = SKShapeNode(rectOf: CGSize(width: tileSize * 0.8, height: tileSize * 0.8), cornerRadius: tileSize * 0.1)
        ring.strokeColor = UIColor(red: 0.45, green: 0.95, blue: 0.6, alpha: 1)
        ring.lineWidth = 3
        ring.position = point
        ring.zPosition = 8
        board.addChild(ring)
        ring.run(.sequence([.group([.scale(to: 1.4, duration: 0.5), .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
    }

    private func scanBeam(at point: CGPoint, duration: TimeInterval, color: String?) {
        let beam = SKShapeNode(rectOf: CGSize(width: tileSize * 0.8, height: max(2, tileSize * 0.05)))
        beam.fillColor = UIColor(red: 1, green: 0.2, blue: 0.2, alpha: 0.85)
        beam.strokeColor = .clear
        beam.glowWidth = 3
        beam.position = CGPoint(x: point.x, y: point.y + tileSize * 0.3)
        beam.zPosition = 12
        board.addChild(beam)
        beam.run(.sequence([.moveBy(x: 0, y: -tileSize * 0.6, duration: duration * 0.6), .fadeOut(withDuration: 0.1), .removeFromParent()]))
        let text = color ?? "None"
        float("scan: \(text)", color: color.map { WarehouseArt.color($0) } ?? .white)
    }

    private func sparks(at point: CGPoint) {
        for k in 0..<6 {
            let p = SKShapeNode(circleOfRadius: max(1.2, tileSize * 0.03))
            p.fillColor = UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1)
            p.strokeColor = .clear
            p.position = point
            p.zPosition = 12
            board.addChild(p)
            let a = CGFloat(k) / 6 * .pi * 2
            p.run(.sequence([.group([.moveBy(x: cos(a) * tileSize * 0.3, y: sin(a) * tileSize * 0.3, duration: 0.3), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
        }
    }

    private func float(_ text: String, color: UIColor) {
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = text
        label.fontSize = max(11, tileSize * 0.24)
        label.fontColor = color
        label.position = CGPoint(x: loaderRoot.position.x, y: loaderRoot.position.y + tileSize * 0.4)
        label.zPosition = 30
        let outline = SKLabelNode(fontNamed: "Menlo-Bold")
        outline.text = text
        outline.fontSize = label.fontSize
        outline.fontColor = UIColor(white: 0, alpha: 0.7)
        outline.position = CGPoint(x: 1.5, y: -1.5)
        outline.zPosition = -1
        label.addChild(outline)
        board.addChild(label)
        label.run(.sequence([.group([.moveBy(x: 0, y: tileSize * 0.45, duration: 0.8), .sequence([.wait(forDuration: 0.4), .fadeOut(withDuration: 0.4)])]), .removeFromParent()]))
    }
}
