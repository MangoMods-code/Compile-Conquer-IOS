import SpriteKit
import UIKit

/// Code-drawn textures for the warehouse: concrete floor, racks, bays, crates and the loader.
enum WarehouseArt {
    private static var cache: [String: SKTexture] = [:]
    static func clearCache() { cache.removeAll() }

    private static func texture(_ key: String, _ size: CGSize, _ draw: (CGContext, CGSize) -> Void) -> SKTexture {
        let k = "\(key)-\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
        if let t = cache[k] { return t }
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext, size) }
        let t = SKTexture(image: image)
        cache[k] = t
        return t
    }

    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }

    static func color(_ name: String) -> UIColor {
        switch name {
        case "red": return rgb(0.9, 0.33, 0.27)
        case "blue": return rgb(0.25, 0.52, 0.92)
        case "green": return rgb(0.25, 0.76, 0.43)
        case "yellow": return rgb(0.96, 0.77, 0.2)
        default: return rgb(0.6, 0.6, 0.62)
        }
    }

    private static func linear(_ c: CGContext, _ colors: [UIColor], from: CGPoint, to: CGPoint) {
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil) else { return }
        c.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func radial(_ c: CGContext, _ colors: [UIColor], center: CGPoint, radius: CGFloat) {
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil) else { return }
        c.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    private static func rnd(_ rng: inout SeededRNG, _ a: CGFloat, _ b: CGFloat) -> CGFloat { CGFloat.random(in: a...b, using: &rng) }

    private static func roundRect(_ c: CGContext, _ r: CGRect, _ radius: CGFloat, fill: UIColor) {
        c.addPath(UIBezierPath(roundedRect: r, cornerRadius: radius).cgPath)
        c.setFillColor(fill.cgColor)
        c.fillPath()
    }

    // MARK: Floor

    static func concrete(_ variant: Int, _ s: CGFloat) -> SKTexture {
        texture("concrete\(variant)", CGSize(width: s, height: s)) { c, sz in
            let base = variant % 2 == 0 ? rgb(0.47, 0.48, 0.5) : rgb(0.44, 0.45, 0.47)
            linear(c, [base, base.withAlphaComponent(1).blended(0.9)], from: .zero, to: CGPoint(x: sz.width, y: sz.height))
            var rng = SeededRNG(seed: UInt64(variant * 977 + 5))
            for _ in 0..<Int(max(12, sz.width * 0.6)) {
                let r = sz.width * rnd(&rng, 0.006, 0.018)
                c.setFillColor((rnd(&rng, 0, 1) > 0.5 ? rgb(1, 1, 1, 0.12) : rgb(0, 0, 0, 0.14)).cgColor)
                c.fillEllipse(in: CGRect(x: rnd(&rng, 0, sz.width), y: rnd(&rng, 0, sz.height), width: r * 2, height: r * 2))
            }
            if variant == 3 {
                // oil stain
                radial(c, [rgb(0.15, 0.15, 0.17, 0.35), rgb(0.15, 0.15, 0.17, 0)], center: CGPoint(x: sz.width * 0.6, y: sz.height * 0.55), radius: sz.width * 0.28)
            }
            if variant == 2 {
                c.setStrokeColor(rgb(0.25, 0.25, 0.27, 0.6).cgColor)
                c.setLineWidth(max(0.8, sz.width * 0.012))
                c.move(to: CGPoint(x: sz.width * 0.1, y: sz.height * 0.3))
                c.addLine(to: CGPoint(x: sz.width * 0.3, y: sz.height * 0.38))
                c.addLine(to: CGPoint(x: sz.width * 0.42, y: sz.height * 0.32))
                c.strokePath()
            }
            // slab seams
            c.setStrokeColor(rgb(0.2, 0.2, 0.22, 0.45).cgColor)
            c.setLineWidth(1)
            c.stroke(CGRect(origin: .zero, size: sz).insetBy(dx: 0.5, dy: 0.5))
            // painted lane dots in the corners
            c.setFillColor(rgb(0.95, 0.8, 0.25, 0.5).cgColor)
            let d = max(1.5, sz.width * 0.03)
            for (x, y) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)] {
                c.fill(CGRect(x: x * sz.width - d / 2, y: y * sz.height - d / 2, width: d, height: d))
            }
        }
    }

    static func rack(_ variant: Int, _ s: CGFloat) -> SKTexture {
        texture("rack\(variant)", CGSize(width: s, height: s)) { c, sz in
            let w = sz.width
            c.setFillColor(rgb(0.16, 0.17, 0.2).cgColor)
            c.fill(CGRect(origin: .zero, size: sz))
            let inner = CGRect(origin: .zero, size: sz).insetBy(dx: w * 0.06, dy: w * 0.06)
            // shelf deck
            c.setFillColor(rgb(0.3, 0.32, 0.36).cgColor)
            c.fill(inner)
            // boxes stored on the shelf
            var rng = SeededRNG(seed: UInt64(variant * 61 + 9))
            let boxColors = [rgb(0.72, 0.55, 0.36), rgb(0.66, 0.5, 0.32), rgb(0.8, 0.64, 0.42)]
            for k in 0..<3 {
                let bw = w * rnd(&rng, 0.22, 0.3), bh = w * rnd(&rng, 0.3, 0.38)
                let r = CGRect(x: inner.minX + w * 0.05 + CGFloat(k) * w * 0.28, y: inner.minY + w * rnd(&rng, 0.08, 0.4), width: bw, height: bh)
                c.setFillColor(rgb(0, 0, 0, 0.3).cgColor)
                c.fill(r.offsetBy(dx: w * 0.02, dy: w * 0.03))
                c.setFillColor(boxColors[k % 3].cgColor)
                c.fill(r)
                c.setFillColor(rgb(0.9, 0.85, 0.7, 0.7).cgColor)
                c.fill(CGRect(x: r.midX - w * 0.012, y: r.minY, width: w * 0.024, height: r.height))
            }
            // orange beams and blue uprights
            c.setStrokeColor(rgb(0.95, 0.55, 0.15).cgColor)
            c.setLineWidth(w * 0.07)
            c.stroke(inner)
            let post = w * 0.14
            c.setFillColor(rgb(0.2, 0.4, 0.8).cgColor)
            for (x, y) in [(inner.minX, inner.minY), (inner.maxX, inner.minY), (inner.minX, inner.maxY), (inner.maxX, inner.maxY)] {
                c.fill(CGRect(x: x - post / 2, y: y - post / 2, width: post, height: post))
            }
        }
    }

    static func bay(_ colorName: String, _ s: CGFloat) -> SKTexture {
        texture("bay-\(colorName)", CGSize(width: s, height: s)) { c, sz in
            let w = sz.width
            let col = color(colorName)
            c.setFillColor(rgb(0.36, 0.37, 0.4).cgColor)
            c.fill(CGRect(origin: .zero, size: sz))
            // striped border
            c.saveGState()
            let outer = CGRect(origin: .zero, size: sz)
            let inner = outer.insetBy(dx: w * 0.13, dy: w * 0.13)
            let ring = UIBezierPath(rect: outer)
            ring.append(UIBezierPath(rect: inner).reversing())
            c.addPath(ring.cgPath)
            c.clip()
            c.setFillColor(rgb(0.12, 0.12, 0.14).cgColor)
            c.fill(outer)
            c.setFillColor(col.cgColor)
            var x = -w
            while x < w * 2 {
                c.move(to: CGPoint(x: x, y: 0))
                c.addLine(to: CGPoint(x: x + w * 0.12, y: 0))
                c.addLine(to: CGPoint(x: x + w * 0.12 + w, y: w))
                c.addLine(to: CGPoint(x: x + w, y: w))
                c.closePath()
                x += w * 0.24
            }
            c.fillPath()
            c.restoreGState()
            // pad
            c.setFillColor(col.withAlphaComponent(0.28).cgColor)
            c.fill(inner)
            // arrow pointing into the bay
            c.setFillColor(col.withAlphaComponent(0.9).cgColor)
            let ax = inner.midX, ay = inner.midY
            c.move(to: CGPoint(x: ax - w * 0.14, y: ay - w * 0.04))
            c.addLine(to: CGPoint(x: ax, y: ay + w * 0.12))
            c.addLine(to: CGPoint(x: ax + w * 0.14, y: ay - w * 0.04))
            c.closePath()
            c.fillPath()
            c.fill(CGRect(x: ax - w * 0.05, y: ay - w * 0.16, width: w * 0.1, height: w * 0.13))
        }
    }

    // MARK: Crates

    static func crate(_ colorName: String, hidden: Bool, _ s: CGFloat) -> SKTexture {
        texture("crate-\(hidden ? "hidden" : colorName)", CGSize(width: s, height: s)) { c, sz in
            let w = sz.width
            let box = CGRect(x: w * 0.12, y: w * 0.12, width: w * 0.76, height: w * 0.76)
            c.setFillColor(rgb(0, 0, 0, 0.3).cgColor)
            c.fill(box.offsetBy(dx: w * 0.05, dy: w * 0.06))
            c.saveGState()
            c.addPath(UIBezierPath(roundedRect: box, cornerRadius: w * 0.05).cgPath)
            c.clip()
            linear(c, [rgb(0.82, 0.64, 0.42), rgb(0.66, 0.49, 0.3)], from: box.origin, to: CGPoint(x: box.maxX, y: box.maxY))
            // flaps and tape
            c.setStrokeColor(rgb(0.5, 0.36, 0.2, 0.7).cgColor)
            c.setLineWidth(max(1, w * 0.015))
            c.move(to: CGPoint(x: box.minX, y: box.midY)); c.addLine(to: CGPoint(x: box.maxX, y: box.midY)); c.strokePath()
            c.setFillColor(rgb(0.93, 0.86, 0.7, 0.85).cgColor)
            c.fill(CGRect(x: box.midX - w * 0.06, y: box.minY, width: w * 0.12, height: box.height))
            c.restoreGState()
            c.setStrokeColor(rgb(0.4, 0.28, 0.15).cgColor)
            c.setLineWidth(max(1, w * 0.025))
            c.addPath(UIBezierPath(roundedRect: box, cornerRadius: w * 0.05).cgPath)
            c.strokePath()
            // label sticker
            let label = CGRect(x: box.midX - w * 0.19, y: box.midY - w * 0.17, width: w * 0.38, height: w * 0.34)
            roundRect(c, label.insetBy(dx: -w * 0.025, dy: -w * 0.025), w * 0.06, fill: .white)
            roundRect(c, label, w * 0.05, fill: hidden ? rgb(0.35, 0.36, 0.4) : color(colorName))
            if hidden {
                let text = "?" as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: w * 0.28, weight: .black), .foregroundColor: UIColor.white]
                let size = text.size(withAttributes: attrs)
                text.draw(at: CGPoint(x: label.midX - size.width / 2, y: label.midY - size.height / 2), withAttributes: attrs)
            } else {
                // barcode lines
                c.setFillColor(rgb(1, 1, 1, 0.8).cgColor)
                for k in 0..<5 {
                    let bw = w * (k % 2 == 0 ? 0.025 : 0.015)
                    c.fill(CGRect(x: label.minX + w * 0.06 + CGFloat(k) * w * 0.055, y: label.minY + label.height * 0.25, width: bw, height: label.height * 0.5))
                }
            }
        }
    }

    // MARK: Loader

    /// The forklift seen from above, forks pointing up (North).
    static func loader(_ d: CGFloat) -> SKTexture {
        texture("loader", CGSize(width: d, height: d)) { c, sz in
            let w = sz.width
            // forks
            c.setFillColor(rgb(0.55, 0.57, 0.6).cgColor)
            c.fill(CGRect(x: w * 0.3, y: w * 0.02, width: w * 0.08, height: w * 0.36))
            c.fill(CGRect(x: w * 0.62, y: w * 0.02, width: w * 0.08, height: w * 0.36))
            // mast
            roundRect(c, CGRect(x: w * 0.22, y: w * 0.3, width: w * 0.56, height: w * 0.1), w * 0.02, fill: rgb(0.25, 0.27, 0.3))
            c.setFillColor(rgb(0.45, 0.47, 0.5).cgColor)
            c.fill(CGRect(x: w * 0.25, y: w * 0.32, width: w * 0.5, height: w * 0.025))
            // tires
            for (x, y) in [(0.16, 0.42), (0.74, 0.42), (0.16, 0.72), (0.74, 0.72)] {
                roundRect(c, CGRect(x: w * x, y: w * y, width: w * 0.1, height: w * 0.18), w * 0.03, fill: rgb(0.08, 0.08, 0.09))
            }
            // body
            let body = CGRect(x: w * 0.24, y: w * 0.38, width: w * 0.52, height: w * 0.52)
            c.saveGState()
            c.addPath(UIBezierPath(roundedRect: body, cornerRadius: w * 0.1).cgPath)
            c.clip()
            linear(c, [rgb(1, 0.82, 0.25), rgb(0.92, 0.66, 0.1)], from: body.origin, to: CGPoint(x: body.maxX, y: body.maxY))
            // counterweight
            c.setFillColor(rgb(0.2, 0.21, 0.24).cgColor)
            c.fill(CGRect(x: body.minX, y: body.maxY - w * 0.12, width: body.width, height: w * 0.12))
            c.restoreGState()
            c.setStrokeColor(rgb(0.45, 0.32, 0.05).cgColor)
            c.setLineWidth(max(1, w * 0.02))
            c.addPath(UIBezierPath(roundedRect: body, cornerRadius: w * 0.1).cgPath)
            c.strokePath()
            // overhead guard (cab roof) with grid
            let roof = CGRect(x: w * 0.3, y: w * 0.44, width: w * 0.4, height: w * 0.3)
            roundRect(c, roof, w * 0.04, fill: rgb(0.14, 0.15, 0.18, 0.92))
            c.setStrokeColor(rgb(0.45, 0.47, 0.52).cgColor)
            c.setLineWidth(max(0.8, w * 0.012))
            for k in 1..<4 {
                let x = roof.minX + roof.width * CGFloat(k) / 4
                c.move(to: CGPoint(x: x, y: roof.minY)); c.addLine(to: CGPoint(x: x, y: roof.maxY)); c.strokePath()
            }
            // amber beacon
            radial(c, [rgb(1, 0.65, 0.1), rgb(1, 0.55, 0.05, 0)], center: CGPoint(x: w * 0.5, y: w * 0.82), radius: w * 0.07)
        }
    }

    static func glow(_ color: UIColor, key: String, _ s: CGFloat) -> SKTexture {
        texture("glow-\(key)", CGSize(width: s, height: s)) { c, sz in
            radial(c, [color, color.withAlphaComponent(0.4), color.withAlphaComponent(0)], center: CGPoint(x: sz.width / 2, y: sz.height / 2), radius: sz.width / 2)
        }
    }

    static func softShadow(_ s: CGFloat) -> SKTexture {
        texture("wshadow", CGSize(width: s, height: s)) { c, sz in
            radial(c, [rgb(0, 0, 0, 0.45), rgb(0, 0, 0, 0)], center: CGPoint(x: sz.width / 2, y: sz.height / 2), radius: sz.width / 2)
        }
    }

    // MARK: Surroundings

    /// Walls around the floor and a dim loading area outside them (UIKit coordinates).
    static func surroundings(size: CGSize, field: CGRect, tile: CGFloat) -> SKTexture {
        let key = "wbg-\(Int(field.minX))-\(Int(field.minY))-\(Int(field.width))-\(Int(field.height))-\(Int(tile))"
        return texture(key, size) { c, sz in
            linear(c, [rgb(0.13, 0.14, 0.16), rgb(0.09, 0.1, 0.12)], from: .zero, to: CGPoint(x: 0, y: sz.height))
            var rng = SeededRNG(seed: 777)
            // painted parking lines outside
            c.setStrokeColor(rgb(0.95, 0.8, 0.25, 0.12).cgColor)
            c.setLineWidth(2)
            var x: CGFloat = 0
            while x < sz.width { c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x + tile * 0.6, y: sz.height)); c.strokePath(); x += tile * 1.4 }

            // pallets and barrels outside the walls
            let keepOut = field.insetBy(dx: -tile * 0.6, dy: -tile * 0.6)
            var placed: [CGRect] = []
            var tries = 0
            while placed.count < 30 && tries < 400 {
                tries += 1
                let r = tile * rnd(&rng, 0.25, 0.4)
                let p = CGPoint(x: rnd(&rng, 0, sz.width), y: rnd(&rng, 0, sz.height))
                let box = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                if box.intersects(keepOut) || placed.contains(where: { $0.intersects(box) }) { continue }
                placed.append(box)
                c.setFillColor(rgb(0, 0, 0, 0.35).cgColor)
                c.fill(box.offsetBy(dx: r * 0.15, dy: r * 0.2))
                if rnd(&rng, 0, 1) > 0.5 {
                    // pallet with boxes
                    c.setFillColor(rgb(0.55, 0.42, 0.28).cgColor)
                    c.fill(box)
                    c.setFillColor(rgb(0.4, 0.3, 0.2).cgColor)
                    for k in 0..<3 { c.fill(CGRect(x: box.minX, y: box.minY + CGFloat(k) * box.height * 0.42, width: box.width, height: box.height * 0.12)) }
                    c.setFillColor(rgb(0.75, 0.6, 0.4).cgColor)
                    c.fill(box.insetBy(dx: r * 0.25, dy: r * 0.25))
                } else {
                    // barrels
                    let col = [rgb(0.2, 0.45, 0.75), rgb(0.75, 0.25, 0.2), rgb(0.25, 0.55, 0.3)][Int(rnd(&rng, 0, 2.99))]
                    c.setFillColor(col.cgColor)
                    c.fillEllipse(in: box.insetBy(dx: r * 0.1, dy: r * 0.1))
                    c.setStrokeColor(rgb(1, 1, 1, 0.25).cgColor)
                    c.setLineWidth(max(1, r * 0.08))
                    c.strokeEllipse(in: box.insetBy(dx: r * 0.35, dy: r * 0.35))
                }
            }

            // walls
            let wallW = max(6, tile * 0.22)
            let wall = field.insetBy(dx: -wallW, dy: -wallW)
            c.setFillColor(rgb(0.26, 0.27, 0.3).cgColor)
            c.fill(wall)
            c.setFillColor(rgb(0, 0, 0, 0.5).cgColor)
            c.fill(wall.insetBy(dx: wallW * 0.35, dy: wallW * 0.35))
            // hazard stripe along the inner edge
            c.saveGState()
            let band = UIBezierPath(rect: field.insetBy(dx: -wallW * 0.35, dy: -wallW * 0.35))
            band.append(UIBezierPath(rect: field).reversing())
            c.addPath(band.cgPath)
            c.clip()
            c.setFillColor(rgb(0.1, 0.1, 0.1).cgColor)
            c.fill(wall)
            c.setFillColor(rgb(0.98, 0.78, 0.15).cgColor)
            var sx = wall.minX - wall.height
            while sx < wall.maxX {
                c.move(to: CGPoint(x: sx, y: wall.minY))
                c.addLine(to: CGPoint(x: sx + wallW * 0.5, y: wall.minY))
                c.addLine(to: CGPoint(x: sx + wallW * 0.5 + wall.height, y: wall.maxY))
                c.addLine(to: CGPoint(x: sx + wall.height, y: wall.maxY))
                c.closePath()
                sx += wallW
            }
            c.fillPath()
            c.restoreGState()
        }
    }
}

private extension UIColor {
    func blended(_ f: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * f, green: g * f, blue: b * f, alpha: a)
    }
}
