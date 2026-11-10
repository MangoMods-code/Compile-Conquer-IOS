import SpriteKit
import UIKit

/// Hand-drawn (in code) textures for the farm: grass, soil, ponds, rocks, wheat, fence, trees and the drone.
/// Everything is drawn once per tile size and cached.
enum FarmArt {
    private static var cache: [String: SKTexture] = [:]

    static func clearCache() { cache.removeAll() }

    private static func texture(_ key: String, _ size: CGSize, _ draw: (CGContext, CGSize) -> Void) -> SKTexture {
        let k = "\(key)-\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
        if let t = cache[k] { return t }
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext, size) }
        let t = SKTexture(image: image)
        t.filteringMode = .linear
        cache[k] = t
        return t
    }

    // MARK: Helpers

    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: a)
    }

    private static func linear(_ c: CGContext, _ colors: [UIColor], from: CGPoint, to: CGPoint) {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let g = CGGradient(colorsSpace: cs, colors: colors.map(\.cgColor) as CFArray, locations: nil) else { return }
        c.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func radial(_ c: CGContext, _ colors: [UIColor], center: CGPoint, radius: CGFloat) {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let g = CGGradient(colorsSpace: cs, colors: colors.map(\.cgColor) as CFArray, locations: nil) else { return }
        c.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    private static func ellipse(_ c: CGContext, _ r: CGRect, _ color: UIColor) {
        c.setFillColor(color.cgColor)
        c.fillEllipse(in: r)
    }

    private static func rnd(_ rng: inout SeededRNG, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
        CGFloat.random(in: a...b, using: &rng)
    }

    /// A faint inner edge so the player can still count tiles.
    private static func tileEdge(_ c: CGContext, _ s: CGSize) {
        c.setStrokeColor(UIColor(white: 0, alpha: 0.10).cgColor)
        c.setLineWidth(1)
        c.stroke(CGRect(origin: .zero, size: s).insetBy(dx: 0.5, dy: 0.5))
    }

    private static func grassBlades(_ c: CGContext, _ s: CGSize, _ rng: inout SeededRNG, density: CGFloat, dark: Bool = false) {
        let n = Int(max(10, s.width * density))
        c.setLineCap(.round)
        for _ in 0..<n {
            let x = rnd(&rng, 0, s.width), y = rnd(&rng, 0, s.height)
            let len = s.width * rnd(&rng, 0.04, 0.09)
            let lean = s.width * rnd(&rng, -0.03, 0.03)
            let light = rnd(&rng, 0, 1) > 0.45
            let color = light ? (dark ? rgb(0.30, 0.55, 0.25, 0.55) : rgb(0.55, 0.82, 0.40, 0.55))
                              : (dark ? rgb(0.10, 0.25, 0.10, 0.45) : rgb(0.19, 0.42, 0.16, 0.45))
            c.setStrokeColor(color.cgColor)
            c.setLineWidth(max(1, s.width * 0.016))
            c.move(to: CGPoint(x: x, y: y))
            c.addQuadCurve(to: CGPoint(x: x + lean, y: y - len), control: CGPoint(x: x, y: y - len * 0.6))
            c.strokePath()
        }
    }

    // MARK: Ground

    static func grass(_ variant: Int, _ s: CGFloat) -> SKTexture {
        texture("grass\(variant)", CGSize(width: s, height: s)) { c, sz in
            let bases = [rgb(0.36, 0.64, 0.29), rgb(0.33, 0.61, 0.27), rgb(0.38, 0.66, 0.31), rgb(0.34, 0.62, 0.28)]
            let base = bases[variant % bases.count]
            linear(c, [base.withBrightness(1.05), base.withBrightness(0.95)], from: .zero, to: CGPoint(x: sz.width, y: sz.height))
            var rng = SeededRNG(seed: UInt64(variant * 7919 + 11))
            // soft patches
            for _ in 0..<3 {
                let r = sz.width * rnd(&rng, 0.15, 0.3)
                ellipse(c, CGRect(x: rnd(&rng, -r, sz.width - r), y: rnd(&rng, -r, sz.height - r), width: r * 2, height: r * 1.4),
                        rnd(&rng, 0, 1) > 0.5 ? rgb(0.45, 0.72, 0.33, 0.25) : rgb(0.22, 0.48, 0.2, 0.2))
            }
            grassBlades(c, sz, &rng, density: 1.1)
            if variant == 3 {
                for _ in 0..<3 {
                    let p = CGPoint(x: rnd(&rng, 0.15, 0.85) * sz.width, y: rnd(&rng, 0.15, 0.85) * sz.height)
                    let r = max(1.5, sz.width * 0.03)
                    let petal = rnd(&rng, 0, 1) > 0.5 ? rgb(1, 1, 1, 0.95) : rgb(1, 0.85, 0.35, 0.95)
                    for k in 0..<4 {
                        let a = CGFloat(k) * .pi / 2
                        ellipse(c, CGRect(x: p.x + cos(a) * r - r * 0.7, y: p.y + sin(a) * r - r * 0.7, width: r * 1.4, height: r * 1.4), petal)
                    }
                    ellipse(c, CGRect(x: p.x - r * 0.6, y: p.y - r * 0.6, width: r * 1.2, height: r * 1.2), rgb(0.95, 0.65, 0.15))
                }
            }
            tileEdge(c, sz)
        }
    }

    static func soil(_ variant: Int, wet: Bool, _ s: CGFloat) -> SKTexture {
        texture("soil\(variant)\(wet ? "w" : "")", CGSize(width: s, height: s)) { c, sz in
            let top = wet ? rgb(0.33, 0.22, 0.15) : rgb(0.55, 0.37, 0.24)
            let bottom = wet ? rgb(0.26, 0.17, 0.11) : rgb(0.47, 0.30, 0.19)
            linear(c, [top, bottom], from: .zero, to: CGPoint(x: 0, y: sz.height))
            // Furrows: dark groove with a lit ridge above it.
            let rows = 3
            for i in 0..<rows {
                let y = sz.height * (CGFloat(i) + 0.62) / CGFloat(rows)
                c.setFillColor((wet ? rgb(0.17, 0.11, 0.07, 0.8) : rgb(0.30, 0.19, 0.11, 0.75)).cgColor)
                c.fill(CGRect(x: sz.width * 0.05, y: y, width: sz.width * 0.9, height: sz.height * 0.07))
                c.setFillColor((wet ? rgb(0.45, 0.33, 0.25, 0.5) : rgb(0.68, 0.49, 0.33, 0.6)).cgColor)
                c.fill(CGRect(x: sz.width * 0.05, y: y - sz.height * 0.05, width: sz.width * 0.9, height: sz.height * 0.04))
            }
            var rng = SeededRNG(seed: UInt64(variant * 131 + 7))
            for _ in 0..<Int(max(6, sz.width * 0.25)) {
                let r = sz.width * rnd(&rng, 0.012, 0.03)
                let light = rnd(&rng, 0, 1) > 0.5
                ellipse(c, CGRect(x: rnd(&rng, 0, sz.width), y: rnd(&rng, 0, sz.height), width: r * 2, height: r * 1.5),
                        light ? rgb(0.75, 0.58, 0.42, wet ? 0.25 : 0.5) : rgb(0.2, 0.12, 0.07, 0.5))
            }
            if wet {
                for _ in 0..<3 {
                    let w = sz.width * rnd(&rng, 0.12, 0.22)
                    ellipse(c, CGRect(x: rnd(&rng, 0.05, 0.75) * sz.width, y: rnd(&rng, 0.05, 0.85) * sz.height, width: w, height: w * 0.35),
                            rgb(0.65, 0.8, 0.95, 0.18))
                }
            }
            // A grassy rim so plots sit naturally in the field.
            c.setStrokeColor(rgb(0.25, 0.5, 0.2, 0.55).cgColor)
            c.setLineWidth(max(1, sz.width * 0.035))
            c.stroke(CGRect(origin: .zero, size: sz).insetBy(dx: sz.width * 0.017, dy: sz.width * 0.017))
            tileEdge(c, sz)
        }
    }

    static func pond(_ s: CGFloat) -> SKTexture {
        texture("pond", CGSize(width: s, height: s)) { c, sz in
            linear(c, [rgb(0.36, 0.64, 0.29), rgb(0.33, 0.60, 0.27)], from: .zero, to: CGPoint(x: sz.width, y: sz.height))
            var rng = SeededRNG(seed: 99)
            grassBlades(c, sz, &rng, density: 0.6)
            let water = CGRect(origin: .zero, size: sz).insetBy(dx: sz.width * 0.08, dy: sz.height * 0.1)
            // sandy shore
            ellipse(c, water.insetBy(dx: -sz.width * 0.04, dy: -sz.width * 0.04), rgb(0.78, 0.7, 0.5))
            c.saveGState()
            c.addEllipse(in: water)
            c.clip()
            radial(c, [rgb(0.32, 0.62, 0.85), rgb(0.12, 0.33, 0.58)], center: CGPoint(x: water.midX - water.width * 0.15, y: water.midY - water.height * 0.15), radius: water.width * 0.7)
            c.restoreGState()
            // ripples
            c.setStrokeColor(rgb(0.8, 0.92, 1, 0.45).cgColor)
            c.setLineWidth(max(1, sz.width * 0.02))
            c.strokeEllipse(in: CGRect(x: water.midX - water.width * 0.28, y: water.midY - water.height * 0.05, width: water.width * 0.32, height: water.height * 0.14))
            // lily pad
            let pad = CGRect(x: water.minX + water.width * 0.55, y: water.minY + water.height * 0.5, width: water.width * 0.26, height: water.width * 0.22)
            c.setFillColor(rgb(0.25, 0.6, 0.28).cgColor)
            c.move(to: CGPoint(x: pad.midX, y: pad.midY))
            c.addArc(center: CGPoint(x: pad.midX, y: pad.midY), radius: pad.width / 2, startAngle: 0.35, endAngle: .pi * 2 - 0.1, clockwise: false)
            c.closePath()
            c.fillPath()
            ellipse(c, CGRect(x: pad.midX - pad.width * 0.12, y: pad.minY - pad.height * 0.05, width: pad.width * 0.24, height: pad.width * 0.24), rgb(1, 0.75, 0.85))
            // highlight
            c.setStrokeColor(rgb(1, 1, 1, 0.35).cgColor)
            c.setLineWidth(max(1, sz.width * 0.025))
            c.addArc(center: CGPoint(x: water.midX, y: water.midY), radius: water.width * 0.38, startAngle: .pi * 1.1, endAngle: .pi * 1.4, clockwise: false)
            c.strokePath()
            tileEdge(c, sz)
        }
    }

    static func rock(_ variant: Int, _ s: CGFloat) -> SKTexture {
        texture("rock\(variant)", CGSize(width: s, height: s)) { c, sz in
            var rng = SeededRNG(seed: UInt64(variant * 31 + 3))
            let w = sz.width, h = sz.height
            ellipse(c, CGRect(x: w * 0.18, y: h * 0.58, width: w * 0.72, height: h * 0.26), rgb(0, 0, 0, 0.28))
            let pts: [CGPoint] = (0..<8).map { i in
                let a = CGFloat(i) / 8 * .pi * 2
                let r = rnd(&rng, 0.27, 0.36)
                return CGPoint(x: w * 0.5 + cos(a) * w * r, y: h * 0.5 + sin(a) * h * r * 0.82)
            }
            let path = CGMutablePath()
            path.addLines(between: pts)
            path.closeSubpath()
            c.saveGState()
            c.addPath(path)
            c.clip()
            linear(c, [rgb(0.74, 0.74, 0.72), rgb(0.47, 0.47, 0.47), rgb(0.33, 0.33, 0.35)], from: CGPoint(x: w * 0.25, y: h * 0.2), to: CGPoint(x: w * 0.75, y: h * 0.8))
            // moss
            ellipse(c, CGRect(x: w * rnd(&rng, 0.3, 0.5), y: h * 0.18, width: w * 0.22, height: h * 0.12), rgb(0.35, 0.55, 0.25, 0.65))
            c.restoreGState()
            c.addPath(path)
            c.setStrokeColor(rgb(0.22, 0.22, 0.24).cgColor)
            c.setLineWidth(max(1, w * 0.025))
            c.strokePath()
            // crack + shine
            c.setStrokeColor(rgb(0.25, 0.25, 0.27, 0.8).cgColor)
            c.setLineWidth(max(1, w * 0.018))
            c.move(to: CGPoint(x: w * 0.55, y: h * 0.35))
            c.addLine(to: CGPoint(x: w * 0.6, y: h * 0.5))
            c.addLine(to: CGPoint(x: w * 0.54, y: h * 0.62))
            c.strokePath()
            ellipse(c, CGRect(x: w * 0.34, y: h * 0.3, width: w * 0.14, height: h * 0.07), rgb(1, 1, 1, 0.4))
        }
    }

    // MARK: Wheat

    /// stage 0 = seed, 1 = sprout, 2 = young green, 3 = ripe golden.
    static func wheat(stage: Int, _ s: CGFloat) -> SKTexture {
        texture("wheat\(stage)", CGSize(width: s, height: s)) { c, sz in
            let w = sz.width, h = sz.height
            let spots: [CGPoint] = [
                CGPoint(x: 0.22, y: 0.40), CGPoint(x: 0.5, y: 0.40), CGPoint(x: 0.78, y: 0.40),
                CGPoint(x: 0.22, y: 0.80), CGPoint(x: 0.5, y: 0.80), CGPoint(x: 0.78, y: 0.80),
            ]
            c.setLineCap(.round)
            for (i, sp) in spots.enumerated() {
                let base = CGPoint(x: sp.x * w, y: sp.y * h)
                switch stage {
                case 0:
                    ellipse(c, CGRect(x: base.x - w * 0.07, y: base.y - h * 0.03, width: w * 0.14, height: h * 0.07), rgb(0.35, 0.22, 0.13))
                    ellipse(c, CGRect(x: base.x - w * 0.025, y: base.y - h * 0.06, width: w * 0.05, height: h * 0.05), rgb(0.85, 0.75, 0.5))
                case 1:
                    c.setStrokeColor(rgb(0.45, 0.85, 0.35).cgColor)
                    c.setLineWidth(max(1.2, w * 0.03))
                    for dx in [-0.03, 0.03] {
                        c.move(to: base)
                        c.addQuadCurve(to: CGPoint(x: base.x + w * CGFloat(dx) * 2, y: base.y - h * 0.11), control: CGPoint(x: base.x, y: base.y - h * 0.08))
                        c.strokePath()
                    }
                default:
                    let ripe = stage == 3
                    let height = h * (ripe ? 0.3 : 0.22)
                    let stalk = ripe ? rgb(0.78, 0.6, 0.22) : rgb(0.38, 0.75, 0.3)
                    let leaf = ripe ? rgb(0.7, 0.55, 0.2) : rgb(0.3, 0.65, 0.25)
                    // leaves
                    c.setStrokeColor(leaf.cgColor)
                    c.setLineWidth(max(1, w * 0.022))
                    for side in [-1.0, 1.0] {
                        c.move(to: base)
                        c.addQuadCurve(to: CGPoint(x: base.x + w * 0.07 * CGFloat(side), y: base.y - height * 0.45),
                                       control: CGPoint(x: base.x + w * 0.05 * CGFloat(side), y: base.y - height * 0.1))
                        c.strokePath()
                    }
                    // stalks
                    let lean = CGFloat(i % 2 == 0 ? 1 : -1) * w * 0.012
                    for dx in [-0.025, 0.0, 0.025] {
                        let top = CGPoint(x: base.x + w * CGFloat(dx) * 1.6 + lean, y: base.y - height)
                        c.setStrokeColor(stalk.cgColor)
                        c.setLineWidth(max(1, w * 0.02))
                        c.move(to: CGPoint(x: base.x + w * CGFloat(dx) * 0.5, y: base.y))
                        c.addLine(to: top)
                        c.strokePath()
                        if ripe {
                            // grain head
                            for k in 0..<4 {
                                let gy = top.y + CGFloat(k) * h * 0.022
                                ellipse(c, CGRect(x: top.x - w * 0.022, y: gy - h * 0.018, width: w * 0.044, height: h * 0.034),
                                        k % 2 == 0 ? rgb(0.98, 0.8, 0.3) : rgb(0.9, 0.68, 0.2))
                            }
                            c.setStrokeColor(rgb(0.95, 0.85, 0.5, 0.8).cgColor)
                            c.setLineWidth(max(0.6, w * 0.008))
                            c.move(to: top)
                            c.addLine(to: CGPoint(x: top.x + w * 0.015, y: top.y - h * 0.06))
                            c.strokePath()
                        } else {
                            ellipse(c, CGRect(x: top.x - w * 0.015, y: top.y - h * 0.02, width: w * 0.03, height: h * 0.05), rgb(0.5, 0.85, 0.4))
                        }
                    }
                }
            }
        }
    }

    // MARK: Other crops

    /// Any crop at a growth stage: 0 = seed, 1 = sprout, 2 = young, 3 = ripe.
    static func crop(_ kind: CropKind, stage: Int, _ s: CGFloat) -> SKTexture {
        switch kind {
        case .wheat: return wheat(stage: stage, s)
        case .carrot: return carrot(stage: stage, s)
        case .pumpkin: return pumpkin(stage: stage, s)
        }
    }

    private static func seedMound(_ c: CGContext, at p: CGPoint, _ w: CGFloat) {
        ellipse(c, CGRect(x: p.x - w * 0.075, y: p.y - w * 0.035, width: w * 0.15, height: w * 0.08), rgb(0.33, 0.21, 0.12))
        ellipse(c, CGRect(x: p.x - w * 0.025, y: p.y - w * 0.055, width: w * 0.05, height: w * 0.05), rgb(0.87, 0.77, 0.52))
    }

    static func carrot(stage: Int, _ s: CGFloat) -> SKTexture {
        texture("carrot\(stage)", CGSize(width: s, height: s)) { c, sz in
            let w = sz.width
            let spots = [CGPoint(x: 0.3, y: 0.32), CGPoint(x: 0.7, y: 0.32), CGPoint(x: 0.3, y: 0.74), CGPoint(x: 0.7, y: 0.74)]
            c.setLineCap(.round)
            for (i, sp) in spots.enumerated() {
                let p = CGPoint(x: sp.x * w, y: sp.y * w)
                if stage == 0 { seedMound(c, at: p, w); continue }
                let reaches: [CGFloat] = [0, 0.07, 0.125, 0.17]
                let reach = w * reaches[min(3, max(0, stage))]
                let fronds = stage == 1 ? 3 : (stage == 2 ? 6 : 7)
                if stage == 3 {
                    // The orange shoulder of the carrot pushing out of the soil.
                    ellipse(c, CGRect(x: p.x - w * 0.085, y: p.y - w * 0.085, width: w * 0.17, height: w * 0.17), rgb(0.72, 0.33, 0.05))
                    ellipse(c, CGRect(x: p.x - w * 0.07, y: p.y - w * 0.07, width: w * 0.14, height: w * 0.14), rgb(0.98, 0.55, 0.13))
                    ellipse(c, CGRect(x: p.x - w * 0.045, y: p.y - w * 0.055, width: w * 0.05, height: w * 0.035), rgb(1, 0.78, 0.45, 0.8))
                }
                for k in 0..<fronds {
                    let a = CGFloat(k) / CGFloat(fronds) * .pi * 2 + CGFloat(i) * 0.6
                    let tip = CGPoint(x: p.x + cos(a) * reach, y: p.y + sin(a) * reach * 0.9)
                    let mid = CGPoint(x: p.x + cos(a + 0.5) * reach * 0.55, y: p.y + sin(a + 0.5) * reach * 0.5)
                    c.setStrokeColor((k % 2 == 0 ? rgb(0.30, 0.72, 0.28) : rgb(0.42, 0.82, 0.36)).cgColor)
                    c.setLineWidth(max(1.2, w * (stage == 1 ? 0.022 : 0.03)))
                    c.move(to: p)
                    c.addQuadCurve(to: tip, control: mid)
                    c.strokePath()
                    if stage >= 2 {
                        ellipse(c, CGRect(x: tip.x - w * 0.022, y: tip.y - w * 0.022, width: w * 0.044, height: w * 0.044), rgb(0.5, 0.86, 0.42))
                    }
                }
            }
        }
    }

    static func pumpkin(stage: Int, _ s: CGFloat) -> SKTexture {
        texture("pumpkin\(stage)", CGSize(width: s, height: s)) { c, sz in
            let w = sz.width
            let p = CGPoint(x: w * 0.5, y: w * 0.56)
            if stage == 0 { seedMound(c, at: p, w); return }

            func leaf(_ at: CGPoint, _ r: CGFloat, _ angle: CGFloat) {
                c.saveGState()
                c.translateBy(x: at.x, y: at.y)
                c.rotate(by: angle)
                ellipse(c, CGRect(x: -r, y: -r * 0.72, width: r * 2, height: r * 1.44), rgb(0.22, 0.56, 0.24))
                ellipse(c, CGRect(x: -r * 0.8, y: -r * 0.6, width: r * 1.3, height: r * 0.9), rgb(0.33, 0.68, 0.32))
                c.setStrokeColor(rgb(0.16, 0.42, 0.18, 0.8).cgColor)
                c.setLineWidth(max(0.8, r * 0.1))
                c.move(to: CGPoint(x: -r * 0.8, y: 0)); c.addLine(to: CGPoint(x: r * 0.8, y: 0)); c.strokePath()
                c.restoreGState()
            }

            // Vine
            c.setStrokeColor(rgb(0.25, 0.52, 0.22).cgColor)
            c.setLineWidth(max(1.5, w * 0.03))
            c.setLineCap(.round)
            c.move(to: CGPoint(x: w * 0.2, y: w * 0.78))
            c.addCurve(to: CGPoint(x: w * 0.8, y: w * 0.3), control1: CGPoint(x: w * 0.3, y: w * 0.4), control2: CGPoint(x: w * 0.62, y: w * 0.75))
            if stage >= 2 { c.strokePath() } else { c.beginPath() }

            if stage == 1 {
                leaf(CGPoint(x: p.x - w * 0.09, y: p.y), w * 0.1, -0.5)
                leaf(CGPoint(x: p.x + w * 0.09, y: p.y - w * 0.03), w * 0.1, 0.6)
                return
            }
            leaf(CGPoint(x: w * 0.24, y: w * 0.7), w * 0.13, -0.7)
            leaf(CGPoint(x: w * 0.78, y: w * 0.3), w * 0.13, 0.5)
            leaf(CGPoint(x: w * 0.7, y: w * 0.78), w * 0.11, 0.2)

            let r = stage == 2 ? w * 0.13 : w * 0.26
            let body = stage == 2 ? rgb(0.45, 0.68, 0.22) : rgb(0.96, 0.52, 0.1)
            let dark = stage == 2 ? rgb(0.3, 0.5, 0.15) : rgb(0.76, 0.34, 0.04)
            let lite = stage == 2 ? rgb(0.6, 0.8, 0.35) : rgb(1, 0.68, 0.25)
            // Shadow, then ribs drawn as overlapping ovals.
            ellipse(c, CGRect(x: p.x - r * 0.95, y: p.y - r * 0.55, width: r * 2.1, height: r * 1.6), rgb(0, 0, 0, 0.28))
            ellipse(c, CGRect(x: p.x - r, y: p.y - r * 0.85, width: r * 2, height: r * 1.7), dark)
            for (dx, col) in [(-0.55, body), (0.55, body), (-0.28, lite), (0.28, lite), (0.0, body)] {
                let cx = p.x + r * CGFloat(dx)
                ellipse(c, CGRect(x: cx - r * 0.42, y: p.y - r * 0.8, width: r * 0.84, height: r * 1.6), col)
            }
            c.setStrokeColor(dark.withAlphaComponent(0.55).cgColor)
            c.setLineWidth(max(0.8, r * 0.05))
            for dx in [-0.42, 0.0, 0.42] {
                let cx = p.x + r * CGFloat(dx)
                c.strokeEllipse(in: CGRect(x: cx - r * 0.3, y: p.y - r * 0.78, width: r * 0.6, height: r * 1.56))
            }
            ellipse(c, CGRect(x: p.x - r * 0.5, y: p.y - r * 0.6, width: r * 0.45, height: r * 0.3), rgb(1, 1, 1, 0.3))
            // Stem
            ellipse(c, CGRect(x: p.x - r * 0.14, y: p.y - r * 0.2, width: r * 0.28, height: r * 0.26), rgb(0.3, 0.42, 0.16))
        }
    }

    // MARK: Surroundings

    static func fencePost(_ s: CGFloat) -> SKTexture {
        texture("post", CGSize(width: s, height: s)) { c, sz in
            let r = CGRect(origin: .zero, size: sz).insetBy(dx: sz.width * 0.08, dy: sz.height * 0.08)
            c.setFillColor(rgb(0, 0, 0, 0.3).cgColor)
            c.fill(r.offsetBy(dx: sz.width * 0.08, dy: sz.height * 0.1))
            let path = UIBezierPath(roundedRect: r, cornerRadius: sz.width * 0.15)
            c.addPath(path.cgPath)
            c.clip()
            linear(c, [rgb(0.72, 0.52, 0.32), rgb(0.48, 0.32, 0.18)], from: r.origin, to: CGPoint(x: r.maxX, y: r.maxY))
            c.setStrokeColor(rgb(0.35, 0.22, 0.12, 0.7).cgColor)
            c.setLineWidth(max(1, sz.width * 0.06))
            c.strokeEllipse(in: r.insetBy(dx: sz.width * 0.22, dy: sz.height * 0.22))
        }
    }

    /// The area around the field: darker grass with trees and bushes outside `field` (UIKit coordinates).
    static func surroundings(size: CGSize, field: CGRect, tile: CGFloat) -> SKTexture {
        let key = "bg-\(Int(field.minX))-\(Int(field.minY))-\(Int(field.width))-\(Int(tile))"
        return texture(key, size) { c, sz in
            linear(c, [rgb(0.17, 0.33, 0.17), rgb(0.12, 0.25, 0.13)], from: .zero, to: CGPoint(x: 0, y: sz.height))
            var rng = SeededRNG(seed: 4242)
            grassBlades(c, sz, &rng, density: 0.9, dark: true)
            // mown border right around the fence
            ellipse(c, field.insetBy(dx: -tile * 0.9, dy: -tile * 0.9), rgb(0.22, 0.42, 0.2, 0.0))
            let keepOut = field.insetBy(dx: -tile * 0.55, dy: -tile * 0.55)
            var placed: [CGRect] = []
            let target = Int(min(60, (sz.width * sz.height) / (tile * tile * 1.3)))
            var tries = 0
            while placed.count < target && tries < 600 {
                tries += 1
                let big = rnd(&rng, 0, 1) > 0.4
                let r = tile * (big ? rnd(&rng, 0.38, 0.6) : rnd(&rng, 0.18, 0.28))
                let p = CGPoint(x: rnd(&rng, -r, sz.width + r), y: rnd(&rng, -r, sz.height + r))
                let box = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                if box.intersects(keepOut) { continue }
                if placed.contains(where: { $0.insetBy(dx: r * 0.4, dy: r * 0.4).intersects(box.insetBy(dx: r * 0.4, dy: r * 0.4)) }) { continue }
                placed.append(box)
                // shadow (sun from the top-left)
                ellipse(c, box.offsetBy(dx: r * 0.25, dy: r * 0.3), rgb(0, 0, 0, 0.28))
                if big {
                    let greens = [rgb(0.12, 0.35, 0.15), rgb(0.17, 0.45, 0.19), rgb(0.25, 0.55, 0.24)]
                    for (k, g) in greens.enumerated() {
                        let inset = CGFloat(k) * r * 0.2
                        let off = -CGFloat(k) * r * 0.08
                        ellipse(c, box.insetBy(dx: inset, dy: inset).offsetBy(dx: off, dy: off), g)
                    }
                    for _ in 0..<3 {
                        let lr = r * 0.22
                        ellipse(c, CGRect(x: p.x + rnd(&rng, -r * 0.5, r * 0.2), y: p.y + rnd(&rng, -r * 0.5, r * 0.2), width: lr, height: lr), rgb(0.4, 0.7, 0.35, 0.5))
                    }
                } else {
                    ellipse(c, box, rgb(0.2, 0.45, 0.2))
                    ellipse(c, box.insetBy(dx: r * 0.3, dy: r * 0.3).offsetBy(dx: -r * 0.15, dy: -r * 0.15), rgb(0.32, 0.6, 0.3))
                    if rnd(&rng, 0, 1) > 0.6 {
                        ellipse(c, CGRect(x: p.x - r * 0.2, y: p.y - r * 0.3, width: r * 0.22, height: r * 0.22), rgb(0.85, 0.25, 0.3))
                    }
                }
            }
        }
    }

    static func cloudShadow(_ s: CGFloat) -> SKTexture {
        texture("cloud", CGSize(width: s * 2, height: s * 1.3)) { c, sz in
            for (cx, cy, r) in [(0.35, 0.55, 0.32), (0.6, 0.45, 0.36), (0.75, 0.6, 0.25)] {
                radial(c, [rgb(0, 0, 0, 0.5), rgb(0, 0, 0, 0)], center: CGPoint(x: sz.width * cx, y: sz.height * cy), radius: sz.width * r)
            }
        }
    }

    static func softShadow(_ s: CGFloat) -> SKTexture {
        texture("shadow", CGSize(width: s, height: s * 0.5)) { c, sz in
            c.scaleBy(x: 1, y: 0.5)
            radial(c, [rgb(0, 0, 0, 0.5), rgb(0, 0, 0, 0.25), rgb(0, 0, 0, 0)], center: CGPoint(x: sz.width / 2, y: sz.height), radius: sz.width / 2)
        }
    }

    static func glow(_ color: UIColor, key: String, _ s: CGFloat) -> SKTexture {
        texture("glow-\(key)", CGSize(width: s, height: s)) { c, sz in
            radial(c, [color, color.withAlphaComponent(0.5), color.withAlphaComponent(0)], center: CGPoint(x: sz.width / 2, y: sz.height / 2), radius: sz.width / 2)
        }
    }

    // MARK: Drone

    /// The drone's frame, hull and canopy, seen from above with the front at the top.
    static func droneBody(_ d: CGFloat) -> SKTexture {
        texture("drone", CGSize(width: d, height: d)) { c, sz in
            let w = sz.width
            let mid = CGPoint(x: w / 2, y: w / 2)
            let hubs = [CGPoint(x: w * 0.2, y: w * 0.2), CGPoint(x: w * 0.8, y: w * 0.2), CGPoint(x: w * 0.2, y: w * 0.8), CGPoint(x: w * 0.8, y: w * 0.8)]
            c.setLineCap(.round)
            // arms
            for h in hubs {
                c.setStrokeColor(rgb(0.16, 0.18, 0.22).cgColor)
                c.setLineWidth(w * 0.085)
                c.move(to: mid); c.addLine(to: h); c.strokePath()
                c.setStrokeColor(rgb(0.36, 0.4, 0.47).cgColor)
                c.setLineWidth(w * 0.03)
                c.move(to: mid); c.addLine(to: h); c.strokePath()
            }
            // motor hubs
            for h in hubs {
                let r = w * 0.075
                ellipse(c, CGRect(x: h.x - r, y: h.y - r, width: r * 2, height: r * 2), rgb(0.12, 0.13, 0.16))
                c.saveGState()
                c.addEllipse(in: CGRect(x: h.x - r * 0.75, y: h.y - r * 0.75, width: r * 1.5, height: r * 1.5))
                c.clip()
                linear(c, [rgb(0.75, 0.78, 0.82), rgb(0.35, 0.38, 0.42)], from: CGPoint(x: h.x - r, y: h.y - r), to: CGPoint(x: h.x + r, y: h.y + r))
                c.restoreGState()
            }
            // hull
            let hull = CGRect(x: w * 0.31, y: w * 0.26, width: w * 0.38, height: w * 0.5)
            let hullPath = UIBezierPath(roundedRect: hull, cornerRadius: w * 0.13).cgPath
            c.saveGState()
            c.addPath(hullPath)
            c.clip()
            linear(c, [rgb(0.3, 0.34, 0.42), rgb(0.14, 0.16, 0.21)], from: CGPoint(x: hull.minX, y: hull.minY), to: CGPoint(x: hull.maxX, y: hull.maxY))
            // racing stripes
            c.setFillColor(rgb(0.24, 0.86, 0.52, 0.9).cgColor)
            c.fill(CGRect(x: hull.minX + hull.width * 0.12, y: hull.minY, width: hull.width * 0.08, height: hull.height))
            c.fill(CGRect(x: hull.maxX - hull.width * 0.2, y: hull.minY, width: hull.width * 0.08, height: hull.height))
            c.restoreGState()
            c.addPath(hullPath)
            c.setStrokeColor(rgb(0.08, 0.09, 0.12).cgColor)
            c.setLineWidth(w * 0.018)
            c.strokePath()
            // glass canopy (front)
            let dome = CGRect(x: w * 0.38, y: w * 0.3, width: w * 0.24, height: w * 0.2)
            c.saveGState()
            c.addEllipse(in: dome)
            c.clip()
            radial(c, [rgb(0.55, 0.95, 0.85), rgb(0.1, 0.45, 0.5), rgb(0.03, 0.15, 0.2)], center: CGPoint(x: dome.midX - dome.width * 0.15, y: dome.midY - dome.height * 0.2), radius: dome.width * 0.7)
            c.restoreGState()
            c.setStrokeColor(rgb(1, 1, 1, 0.7).cgColor)
            c.setLineWidth(w * 0.015)
            c.addArc(center: CGPoint(x: dome.midX, y: dome.midY), radius: dome.width * 0.36, startAngle: .pi * 1.15, endAngle: .pi * 1.45, clockwise: false)
            c.strokePath()
            // battery bay + seed hopper at the back
            let bay = CGRect(x: w * 0.4, y: w * 0.56, width: w * 0.2, height: w * 0.14)
            c.addPath(UIBezierPath(roundedRect: bay, cornerRadius: w * 0.03).cgPath)
            c.setFillColor(rgb(0.08, 0.1, 0.13).cgColor)
            c.fillPath()
            for k in 0..<3 {
                c.setFillColor(rgb(0.24, 0.86, 0.52, 0.85 - CGFloat(k) * 0.2).cgColor)
                c.fill(CGRect(x: bay.minX + bay.width * (0.15 + CGFloat(k) * 0.25), y: bay.minY + bay.height * 0.3, width: bay.width * 0.17, height: bay.height * 0.4))
            }
            // nose chevron
            c.setStrokeColor(rgb(0.24, 0.86, 0.52).cgColor)
            c.setLineWidth(w * 0.025)
            c.move(to: CGPoint(x: w * 0.44, y: w * 0.255))
            c.addLine(to: CGPoint(x: w * 0.5, y: w * 0.205))
            c.addLine(to: CGPoint(x: w * 0.56, y: w * 0.255))
            c.strokePath()
        }
    }

    /// Motion-blurred rotor disc.
    static func rotorDisc(_ d: CGFloat) -> SKTexture {
        texture("rotordisc", CGSize(width: d, height: d)) { c, sz in
            radial(c, [rgb(0.85, 0.9, 0.95, 0.05), rgb(0.85, 0.9, 0.95, 0.22), rgb(0.85, 0.9, 0.95, 0.05)],
                   center: CGPoint(x: sz.width / 2, y: sz.height / 2), radius: sz.width / 2)
            c.setStrokeColor(rgb(0.9, 0.95, 1, 0.35).cgColor)
            c.setLineWidth(max(1, sz.width * 0.03))
            c.strokeEllipse(in: CGRect(origin: .zero, size: sz).insetBy(dx: sz.width * 0.04, dy: sz.width * 0.04))
        }
    }

    /// A two-blade propeller.
    static func propeller(_ d: CGFloat) -> SKTexture {
        texture("prop", CGSize(width: d, height: d)) { c, sz in
            let w = sz.width
            c.translateBy(x: w / 2, y: w / 2)
            for side in [-1.0, 1.0] {
                let blade = UIBezierPath()
                blade.move(to: .zero)
                blade.addQuadCurve(to: CGPoint(x: w * 0.47 * CGFloat(side), y: 0), controlPoint: CGPoint(x: w * 0.25 * CGFloat(side), y: -w * 0.1))
                blade.addQuadCurve(to: .zero, controlPoint: CGPoint(x: w * 0.25 * CGFloat(side), y: w * 0.04))
                c.addPath(blade.cgPath)
                c.setFillColor(rgb(0.86, 0.88, 0.92, 0.85).cgColor)
                c.fillPath()
            }
            ellipse(c, CGRect(x: -w * 0.07, y: -w * 0.07, width: w * 0.14, height: w * 0.14), rgb(0.24, 0.86, 0.52))
        }
    }
}

private extension UIColor {
    func withBrightness(_ f: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: min(1, b * f), alpha: a)
    }
}
