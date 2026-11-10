import SwiftUI
import SpriteKit
import UIKit

/// Small pictures of each world for the menus, composed from the same art the levels use.
enum WorldArt {
    private static var cache: [String: UIImage] = [:]

    static func thumbnail(_ kind: WorldKind, size: CGSize) -> UIImage {
        let key = "\(kind.rawValue)-\(Int(size.width))x\(Int(size.height))"
        if let img = cache[key] { return img }
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            switch kind {
            case .farm: drawFarm(ctx.cgContext, size)
            case .warehouse: drawWarehouse(ctx.cgContext, size)
            }
        }
        cache[key] = img
        return img
    }

    private static func image(_ texture: SKTexture) -> UIImage { UIImage(cgImage: texture.cgImage()) }

    private static func drawFarm(_ c: CGContext, _ size: CGSize) {
        let rows = 3
        let t = ceil(size.height / CGFloat(rows))
        let cols = Int(ceil(size.width / t))
        // Which tiles are soil, and what's growing on them (column, row, crop, stage).
        let plots: [(Int, Int, CropKind, Int)] = [(1, 1, .wheat, 3), (2, 1, .wheat, 3), (3, 1, .carrot, 3), (1, 2, .wheat, 2), (2, 2, .pumpkin, 3), (3, 2, .carrot, 1)]
        for y in 0..<rows {
            for x in 0..<cols {
                let rect = CGRect(x: CGFloat(x) * t, y: CGFloat(y) * t, width: t, height: t)
                let plot = plots.first { $0.0 == x && $0.1 == y }
                if let plot {
                    image(FarmArt.soil((x + y) % 2, wet: plot.3 < 3, t)).draw(in: rect)
                    image(FarmArt.crop(plot.2, stage: plot.3, t)).draw(in: rect)
                } else {
                    image(FarmArt.grass((x * 3 + y) % 4, t)).draw(in: rect)
                    if x == cols - 1 && y == 0 { image(FarmArt.pond(t)).draw(in: rect) }
                    if x == 0 && y == 2 { image(FarmArt.rock(1, t)).draw(in: rect) }
                }
            }
        }
        // The drone hovering over the field.
        let d = t * 1.15
        let center = CGPoint(x: t * 4.2, y: t * 1.25)
        image(FarmArt.softShadow(d)).draw(in: CGRect(x: center.x - d * 0.4, y: center.y + d * 0.05, width: d * 0.95, height: d * 0.5))
        image(FarmArt.droneBody(d)).draw(in: CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d))
        for (hx, hy) in [(-0.3, -0.3), (0.3, -0.3), (-0.3, 0.3), (0.3, 0.3)] {
            let r = d * 0.42
            let p = CGPoint(x: center.x + d * CGFloat(hx), y: center.y + d * CGFloat(hy))
            image(FarmArt.rotorDisc(r)).draw(in: CGRect(x: p.x - r / 2, y: p.y - r / 2, width: r, height: r))
        }
    }

    private static func drawWarehouse(_ c: CGContext, _ size: CGSize) {
        let rows = 3
        let t = ceil(size.height / CGFloat(rows))
        let cols = Int(ceil(size.width / t))
        let bays: [Int: String] = [0: "green", 1: "red", 2: "blue"]
        for y in 0..<rows {
            for x in 0..<cols {
                let rect = CGRect(x: CGFloat(x) * t, y: CGFloat(y) * t, width: t, height: t)
                if y == 0, let color = bays[x] {
                    image(WarehouseArt.bay(color, t)).draw(in: rect)
                } else if x == 3 && y >= 1 {
                    image(WarehouseArt.rack(y, t)).draw(in: rect)
                } else {
                    image(WarehouseArt.concrete((x * 3 + y) % 4, t)).draw(in: rect)
                }
            }
        }
        image(WarehouseArt.crate("red", hidden: false, t)).draw(in: CGRect(x: t * 0, y: t * 2, width: t, height: t))
        image(WarehouseArt.crate("blue", hidden: true, t)).draw(in: CGRect(x: t * 4, y: t * 2, width: t, height: t))
        image(WarehouseArt.crate("green", hidden: false, t)).draw(in: CGRect(x: t * 5, y: t * 1, width: t, height: t))
        let d = t * 1.05
        image(WarehouseArt.softShadow(d)).draw(in: CGRect(x: t * 1.5 - d / 2 + 3, y: t * 1.55 - d / 2 + 4, width: d, height: d))
        image(WarehouseArt.loader(d)).draw(in: CGRect(x: t * 1.5 - d / 2, y: t * 1.55 - d / 2, width: d, height: d))
        image(WarehouseArt.crate("blue", hidden: false, t)).draw(in: CGRect(x: t * 1.5 - d * 0.31, y: t * 1.55 - d * 0.62, width: d * 0.62, height: d * 0.62))
    }
}

/// A world's picture, or a tinted placeholder for worlds that aren't built yet.
struct WorldThumbnail: View {
    let world: WorldInfo
    var height: CGFloat = 104

    var body: some View {
        GeometryReader { geo in
            if let kind = world.kind {
                Image(uiImage: WorldArt.thumbnail(kind, size: CGSize(width: max(60, geo.size.width), height: height)))
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: height)
                    .clipped()
            } else {
                ZStack {
                    LinearGradient(colors: [Theme.panelHi, Theme.bg], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: world.symbol)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Theme.dim.opacity(0.35))
                }
            }
        }
        .frame(height: height)
    }
}
