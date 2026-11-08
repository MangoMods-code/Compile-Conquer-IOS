import SpriteKit
import UIKit

/// Draws a FarmWorld top-down and animates the drone between ticks.
final class FarmScene: SKScene {
    private var world: FarmWorld?
    private let background = SKSpriteNode()
    private let board = SKNode()
    private var tileNodes: [SKSpriteNode] = []
    private var overlayNodes: [Int: SKSpriteNode] = [:]
    private var tileKeys: [Int: String] = [:]
    private var overlayKeys: [Int: String] = [:]
    private var ageBadges: [Int: SKNode] = [:]
    private var droneRoot = SKNode()
    private var droneLift = SKNode()
    private var droneBody = SKNode()
    private var droneShadow = SKSpriteNode()
    private var tileSize: CGFloat = 40
    private var origin = CGPoint.zero
    private var builtSize = CGSize.zero

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.12, green: 0.25, blue: 0.13, alpha: 1)
        background.zPosition = -10
        addChild(background)
        addChild(board)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        if let w = world, size.width > 10, size.height > 10 { rebuild(w) }
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

        let move = max(0.05, duration * 0.8)
        let target = center(of: w.drone)
        let groundPoint = center(of: old.drone)

        switch outcome {
        case .bumped:
            if case .move(let d) = command {
                let dx = CGFloat(d.delta.dx) * tileSize * 0.22
                let dy = CGFloat(d.delta.dy) * tileSize * 0.22
                droneRoot.run(.sequence([.moveBy(x: dx, y: dy, duration: move * 0.35), .moveBy(x: -dx, y: -dy, duration: move * 0.45)]))
                dust(at: CGPoint(x: droneRoot.position.x + dx * 2, y: droneRoot.position.y + dy * 2), color: UIColor(white: 0.85, alpha: 1), count: 5)
            }
            float("bonk!", color: UIColor(red: 1, green: 0.45, blue: 0.38, alpha: 1))
        case .warning:
            float("?", color: UIColor(red: 1, green: 0.78, blue: 0.3, alpha: 1))
        case .ok(let note):
            if let note { float(note, color: UIColor(red: 0.98, green: 0.84, blue: 0.35, alpha: 1)) }
        }

        // Tool effects play under the drone, then the ground updates.
        var tileDelay: TimeInterval = 0
        switch (command, outcome) {
        case (.till, .ok):
            dust(at: groundPoint, color: UIColor(red: 0.55, green: 0.38, blue: 0.24, alpha: 1), count: 10)
            tileDelay = move * 0.3
        case (.plant, .ok):
            seeds(at: groundPoint, duration: move)
            tileDelay = move * 0.6
        case (.water, .ok):
            spray(at: groundPoint, duration: move)
            tileDelay = move * 0.4
        case (.harvest, .ok):
            sparkle(at: groundPoint)
        default:
            break
        }
        if tileDelay > 0 {
            run(.sequence([.wait(forDuration: tileDelay), .run { [weak self] in
                guard let self, let current = self.world else { return }
                self.refreshTiles(current, animated: true)
            }]))
        } else {
            refreshTiles(w, animated: true)
        }

        if droneRoot.position != target {
            droneRoot.removeAction(forKey: "move")
            let a = SKAction.move(to: target, duration: move)
            a.timingMode = .easeInEaseOut
            droneRoot.run(a, withKey: "move")
            // lean into the move
            droneLift.run(.sequence([.scale(to: 0.94, duration: move * 0.3), .scale(to: 1, duration: move * 0.5)]))
        }
        turnDrone(to: w.facing, duration: move * 0.6)

        switch command {
        case .till, .plant, .water, .harvest:
            // dip down toward the ground to do the job
            droneLift.run(.sequence([.scale(to: 0.84, duration: move * 0.35), .scale(to: 1.0, duration: move * 0.4)]))
            droneShadow.run(.sequence([.scale(to: 1.15, duration: move * 0.35), .scale(to: 1.0, duration: move * 0.4)]))
        default:
            break
        }
    }

    // MARK: Layout

    private func rebuild(_ w: FarmWorld) {
        board.removeAllChildren()
        removeAllActions()
        tileNodes = []
        overlayNodes = [:]
        tileKeys = [:]
        overlayKeys = [:]
        ageBadges = [:]

        let margin = max(24, min(size.width, size.height) * 0.09)
        tileSize = floor(min((size.width - margin * 2) / CGFloat(w.width), (size.height - margin * 2) / CGFloat(w.height)))
        tileSize = max(12, tileSize)
        origin = CGPoint(x: ((size.width - tileSize * CGFloat(w.width)) / 2).rounded(),
                         y: ((size.height - tileSize * CGFloat(w.height)) / 2).rounded())
        if builtSize != size { FarmArt.clearCache(); builtSize = size }

        // Surroundings (UIKit coordinates for the texture: y grows downward).
        let fieldUIKit = CGRect(x: origin.x, y: size.height - origin.y - tileSize * CGFloat(w.height),
                                width: tileSize * CGFloat(w.width), height: tileSize * CGFloat(w.height))
        background.texture = FarmArt.surroundings(size: size, field: fieldUIKit, tile: tileSize)
        background.size = size
        background.position = CGPoint(x: size.width / 2, y: size.height / 2)

        for y in 0..<w.height {
            for x in 0..<w.width {
                let n = SKSpriteNode(color: .clear, size: CGSize(width: tileSize, height: tileSize))
                n.position = center(of: Pos(x: x, y: y))
                n.zPosition = 1
                board.addChild(n)
                tileNodes.append(n)
            }
        }
        refreshTiles(w, animated: false)
        buildFence(w)
        addClouds()

        droneRoot = makeDrone()
        droneRoot.position = center(of: w.drone)
        droneRoot.zPosition = 10
        board.addChild(droneRoot)
        turnDrone(to: w.facing, duration: 0)
    }

    private func center(of p: Pos) -> CGPoint {
        CGPoint(x: origin.x + (CGFloat(p.x) + 0.5) * tileSize, y: origin.y + (CGFloat(p.y) + 0.5) * tileSize)
    }

    private func buildFence(_ w: FarmWorld) {
        let wood = UIColor(red: 0.6, green: 0.42, blue: 0.25, alpha: 1)
        let gap = tileSize * 0.16
        let left = origin.x - gap, right = origin.x + tileSize * CGFloat(w.width) + gap
        let bottom = origin.y - gap, top = origin.y + tileSize * CGFloat(w.height) + gap
        let railH = max(2, tileSize * 0.05)

        func rail(from a: CGPoint, to b: CGPoint) {
            let len = hypot(b.x - a.x, b.y - a.y)
            for (k, offset) in [CGFloat(-1), 1].enumerated() {
                let r = SKSpriteNode(color: k == 0 ? wood : wood.withAlphaComponent(0.9), size: CGSize(width: len, height: railH))
                r.position = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                r.zRotation = atan2(b.y - a.y, b.x - a.x)
                let normal = CGPoint(x: -(b.y - a.y) / len, y: (b.x - a.x) / len)
                r.position.x += normal.x * offset * railH * 1.1
                r.position.y += normal.y * offset * railH * 1.1
                r.zPosition = 4
                board.addChild(r)
            }
        }
        rail(from: CGPoint(x: left, y: bottom), to: CGPoint(x: right, y: bottom))
        rail(from: CGPoint(x: left, y: top), to: CGPoint(x: right, y: top))
        rail(from: CGPoint(x: left, y: bottom), to: CGPoint(x: left, y: top))
        rail(from: CGPoint(x: right, y: bottom), to: CGPoint(x: right, y: top))

        let postSize = max(6, tileSize * 0.17)
        let tex = FarmArt.fencePost(postSize)
        var points: [CGPoint] = []
        for i in 0...w.width {
            let x = i == 0 ? left : (i == w.width ? right : origin.x + CGFloat(i) * tileSize)
            points.append(CGPoint(x: x, y: bottom)); points.append(CGPoint(x: x, y: top))
        }
        for j in 1..<w.height {
            let y = origin.y + CGFloat(j) * tileSize
            points.append(CGPoint(x: left, y: y)); points.append(CGPoint(x: right, y: y))
        }
        for p in points {
            let post = SKSpriteNode(texture: tex, size: CGSize(width: postSize, height: postSize))
            post.position = p
            post.zPosition = 5
            board.addChild(post)
        }
    }

    private func addClouds() {
        for k in 0..<2 {
            let cloud = SKSpriteNode(texture: FarmArt.cloudShadow(tileSize * 1.6))
            cloud.alpha = 0.16
            cloud.zPosition = 6
            let y = size.height * (k == 0 ? 0.7 : 0.3)
            let span = size.width + cloud.size.width
            cloud.position = CGPoint(x: -cloud.size.width / 2 + span * (k == 0 ? 0.2 : 0.65), y: y)
            board.addChild(cloud)
            let speed: CGFloat = 14 // points per second
            let first = SKAction.moveTo(x: size.width + cloud.size.width / 2, duration: TimeInterval((size.width + cloud.size.width / 2 - cloud.position.x) / speed))
            let loop = SKAction.repeatForever(.sequence([
                .moveTo(x: -cloud.size.width / 2, duration: 0),
                .moveTo(x: size.width + cloud.size.width / 2, duration: TimeInterval(span / speed)),
            ]))
            cloud.run(.sequence([first, loop]))
        }
    }

    // MARK: Tiles & crops

    private func variant(_ x: Int, _ y: Int, _ n: Int) -> Int { abs((x * 73_856_093) ^ (y * 19_349_663)) % n }

    private func refreshTiles(_ w: FarmWorld, animated: Bool) {
        for y in 0..<w.height {
            for x in 0..<w.width {
                let i = y * w.width + x
                let t = w.tile(at: Pos(x: x, y: y))
                let node = tileNodes[i]

                // Ground
                let groundKey: String
                switch t.ground {
                case .grass, .rock: groundKey = "g\(variant(x, y, 4))"
                case .soil: groundKey = "s\(variant(x, y, 2))\(t.wetTicks > 0 ? "w" : "")"
                case .water: groundKey = "pond"
                }
                if tileKeys[i] != groundKey {
                    let wasSet = tileKeys[i] != nil
                    tileKeys[i] = groundKey
                    switch t.ground {
                    case .grass, .rock: node.texture = FarmArt.grass(variant(x, y, 4), tileSize)
                    case .soil: node.texture = FarmArt.soil(variant(x, y, 2), wet: t.wetTicks > 0, tileSize)
                    case .water: node.texture = FarmArt.pond(tileSize)
                    }
                    node.color = .white
                    if animated && wasSet {
                        node.run(.sequence([.scale(to: 0.92, duration: 0.06), .scale(to: 1, duration: 0.12)]))
                    }
                }

                // Overlay: rock or crop
                var overlayKey = ""
                var overlayTex: SKTexture?
                if t.ground == .rock {
                    overlayKey = "rock"
                    overlayTex = FarmArt.rock(variant(x, y, 3), tileSize)
                } else if let crop = t.crop {
                    let stage = crop.ripe ? 3 : min(2, Int(crop.progress * 3))
                    overlayKey = "wheat\(stage)"
                    overlayTex = FarmArt.wheat(stage: stage, tileSize)
                }
                updateAgeBadge(i, crop: t.crop, at: node.position)

                if overlayKeys[i] != overlayKey {
                    overlayKeys[i] = overlayKey
                    overlayNodes[i]?.removeFromParent()
                    overlayNodes[i] = nil
                    if let tex = overlayTex {
                        let o = SKSpriteNode(texture: tex, size: CGSize(width: tileSize, height: tileSize))
                        o.position = node.position
                        o.zPosition = 3
                        board.addChild(o)
                        overlayNodes[i] = o
                        if overlayKey == "wheat3" {
                            o.run(.repeatForever(.sequence([
                                .scaleX(to: 1.03, y: 0.97, duration: 0.9),
                                .scaleX(to: 0.98, y: 1.02, duration: 0.9),
                            ])))
                        }
                        if animated && overlayKey != "rock" {
                            o.setScale(0.7)
                            o.run(.scale(to: 1, duration: 0.18))
                        }
                    }
                }
            }
        }
    }

    /// A small "age/GROW_TIME" tag on each crop so you can see when it will be ripe.
    private func updateAgeBadge(_ i: Int, crop: Crop?, at p: CGPoint) {
        guard let crop, AppSettings.shared.showCropAges else {
            ageBadges[i]?.removeFromParent()
            ageBadges[i] = nil
            return
        }
        let text = "\(min(crop.growth, crop.growTime))/\(crop.growTime)"
        let badge: SKNode
        if let existing = ageBadges[i] {
            badge = existing
        } else {
            badge = SKNode()
            let bg = SKShapeNode(rectOf: CGSize(width: tileSize * 0.42, height: tileSize * 0.2), cornerRadius: tileSize * 0.1)
            bg.name = "bg"
            bg.lineWidth = 1
            badge.addChild(bg)
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.name = "label"
            label.fontSize = max(8, tileSize * 0.14)
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            badge.addChild(label)
            badge.position = CGPoint(x: p.x + tileSize * 0.26, y: p.y - tileSize * 0.36)
            badge.zPosition = 7
            board.addChild(badge)
            ageBadges[i] = badge
        }
        let ripe = crop.ripe
        if let label = badge.childNode(withName: "label") as? SKLabelNode, label.text != text {
            label.text = text
            label.fontColor = ripe ? UIColor(red: 0.15, green: 0.1, blue: 0, alpha: 1) : .white
            if label.parent != nil, !ripe { badge.run(.sequence([.scale(to: 1.25, duration: 0.08), .scale(to: 1, duration: 0.12)])) }
        }
        if let bg = badge.childNode(withName: "bg") as? SKShapeNode {
            bg.fillColor = ripe ? UIColor(red: 0.98, green: 0.8, blue: 0.3, alpha: 0.95) : UIColor(white: 0, alpha: 0.6)
            bg.strokeColor = ripe ? UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1) : UIColor(white: 1, alpha: 0.25)
        }
    }

    // MARK: Drone

    private func makeDrone() -> SKNode {
        let s = tileSize
        let d = s * 0.92
        let root = SKNode()

        droneShadow = SKSpriteNode(texture: FarmArt.softShadow(d), size: CGSize(width: d * 0.95, height: d * 0.5))
        droneShadow.position = CGPoint(x: s * 0.12, y: -s * 0.2)
        droneShadow.zPosition = -1
        root.addChild(droneShadow)

        let lift = SKNode()
        let body = SKNode()
        body.addChild(SKSpriteNode(texture: FarmArt.droneBody(d), size: CGSize(width: d, height: d)))

        // Rotors sit over the motor hubs (texture coordinates are flipped to SpriteKit's y-up).
        let hubs = [CGPoint(x: -0.3, y: 0.3), CGPoint(x: 0.3, y: 0.3), CGPoint(x: -0.3, y: -0.3), CGPoint(x: 0.3, y: -0.3)]
        for (k, h) in hubs.enumerated() {
            let p = CGPoint(x: h.x * d, y: h.y * d)
            let disc = SKSpriteNode(texture: FarmArt.rotorDisc(d * 0.42), size: CGSize(width: d * 0.42, height: d * 0.42))
            disc.position = p
            disc.zPosition = 1
            body.addChild(disc)
            let prop = SKSpriteNode(texture: FarmArt.propeller(d * 0.4), size: CGSize(width: d * 0.4, height: d * 0.4))
            prop.position = p
            prop.zPosition = 2
            prop.zRotation = CGFloat(k) * 0.7
            let dir: CGFloat = (k == 0 || k == 3) ? 1 : -1
            prop.run(.repeatForever(.rotate(byAngle: dir * .pi * 2, duration: 0.12)))
            body.addChild(prop)

            // Navigation lights: green at the front, red at the back.
            let front = h.y > 0
            let color = front ? UIColor(red: 0.3, green: 1, blue: 0.55, alpha: 1) : UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
            let led = SKSpriteNode(texture: FarmArt.glow(color, key: front ? "g" : "r", d * 0.16), size: CGSize(width: d * 0.16, height: d * 0.16))
            led.position = CGPoint(x: p.x * 1.32, y: p.y * 1.32)
            led.zPosition = 3
            led.blendMode = .add
            let delay = front ? 0.0 : 0.5
            led.run(.sequence([.wait(forDuration: delay), .repeatForever(.sequence([
                .fadeAlpha(to: 1, duration: 0.08), .wait(forDuration: 0.25),
                .fadeAlpha(to: 0.25, duration: 0.3), .wait(forDuration: 0.4),
            ]))]))
            body.addChild(led)
        }

        lift.addChild(body)
        root.addChild(lift)

        // Hover: the drone floats up and down while its shadow shrinks and grows.
        let bob = s * 0.045
        lift.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: bob, duration: 0.7), .moveBy(x: 0, y: -bob, duration: 0.7),
        ])))
        droneShadow.run(.repeatForever(.sequence([
            .group([.scale(to: 0.9, duration: 0.7), .fadeAlpha(to: 0.75, duration: 0.7)]),
            .group([.scale(to: 1.0, duration: 0.7), .fadeAlpha(to: 1.0, duration: 0.7)]),
        ])))

        droneLift = lift
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
        label.fontSize = max(11, tileSize * 0.26)
        label.fontColor = color
        label.position = CGPoint(x: droneRoot.position.x, y: droneRoot.position.y + tileSize * 0.4)
        label.zPosition = 30
        let outline = SKLabelNode(fontNamed: "Menlo-Bold")
        outline.text = text
        outline.fontSize = label.fontSize
        outline.fontColor = UIColor(white: 0, alpha: 0.6)
        outline.position = CGPoint(x: 1.5, y: -1.5)
        outline.zPosition = -1
        label.addChild(outline)
        board.addChild(label)
        label.run(.sequence([.group([.moveBy(x: 0, y: tileSize * 0.45, duration: 0.8), .sequence([.wait(forDuration: 0.4), .fadeOut(withDuration: 0.4)])]), .removeFromParent()]))
    }

    private func particle(_ color: UIColor, radius: CGFloat) -> SKShapeNode {
        let p = SKShapeNode(circleOfRadius: max(1.2, radius))
        p.fillColor = color
        p.strokeColor = .clear
        p.zPosition = 8
        return p
    }

    private func dust(at point: CGPoint, color: UIColor, count: Int) {
        for k in 0..<count {
            let p = particle(color.withAlphaComponent(0.85), radius: tileSize * CGFloat.random(in: 0.03...0.06))
            p.position = point
            board.addChild(p)
            let a = CGFloat(k) / CGFloat(count) * .pi * 2 + CGFloat.random(in: -0.3...0.3)
            let dist = tileSize * CGFloat.random(in: 0.25...0.45)
            p.run(.sequence([.group([
                .moveBy(x: cos(a) * dist, y: sin(a) * dist, duration: 0.4),
                .fadeOut(withDuration: 0.4), .scale(to: 1.6, duration: 0.4),
            ]), .removeFromParent()]))
        }
    }

    private func seeds(at point: CGPoint, duration: TimeInterval) {
        for k in 0..<6 {
            let seed = SKShapeNode(ellipseOf: CGSize(width: tileSize * 0.05, height: tileSize * 0.08))
            seed.fillColor = UIColor(red: 0.9, green: 0.78, blue: 0.5, alpha: 1)
            seed.strokeColor = UIColor(red: 0.5, green: 0.35, blue: 0.15, alpha: 1)
            seed.lineWidth = 0.5
            seed.zPosition = 9
            seed.position = CGPoint(x: point.x, y: point.y + tileSize * 0.1)
            board.addChild(seed)
            let tx = CGFloat(k % 3 - 1) * tileSize * 0.28
            let ty = (k < 3 ? 0.1 : -0.3) * tileSize
            seed.run(.sequence([
                .wait(forDuration: Double(k) * 0.03),
                .group([.moveBy(x: tx, y: ty, duration: duration * 0.5), .scale(to: 0.5, duration: duration * 0.5)]),
                .fadeOut(withDuration: 0.15), .removeFromParent(),
            ]))
        }
    }

    private func spray(at point: CGPoint, duration: TimeInterval) {
        for k in 0..<12 {
            let drop = particle(UIColor(red: 0.55, green: 0.82, blue: 1, alpha: 0.9), radius: tileSize * 0.035)
            drop.position = CGPoint(x: point.x, y: point.y + tileSize * 0.05)
            board.addChild(drop)
            let tx = CGFloat.random(in: -0.4...0.4) * tileSize
            let ty = CGFloat.random(in: -0.4...0.35) * tileSize
            drop.run(.sequence([
                .wait(forDuration: Double(k) * 0.015),
                .group([.moveBy(x: tx, y: ty, duration: duration * 0.45), .fadeOut(withDuration: duration * 0.45)]),
                .removeFromParent(),
            ]))
        }
    }

    private func sparkle(at point: CGPoint) {
        for k in 0..<10 {
            let star = SKLabelNode(text: k % 2 == 0 ? "✦" : "•")
            star.fontSize = tileSize * CGFloat.random(in: 0.14...0.24)
            star.fontColor = UIColor(red: 1, green: 0.86, blue: 0.35, alpha: 1)
            star.position = point
            star.zPosition = 9
            board.addChild(star)
            let a = CGFloat(k) / 10 * .pi * 2
            star.run(.sequence([.group([
                .moveBy(x: cos(a) * tileSize * 0.4, y: sin(a) * tileSize * 0.4 + tileSize * 0.15, duration: 0.5),
                .fadeOut(withDuration: 0.5),
            ]), .removeFromParent()]))
        }
    }
}


extension FarmScene: WorldRenderer {
    func load(_ state: WorldState) {
        if case .farm(let w) = state { load(w) }
    }

    func apply(_ state: WorldState, action: WorldAction, outcome: CommandOutcome, duration: TimeInterval) {
        guard case .farm(let w) = state, case .farm(let c) = action else { return }
        apply(w, command: c, outcome: outcome, duration: duration)
    }
}
