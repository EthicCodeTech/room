import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import RoomCore

// Renders the Room app icon from the Cinnabar master vector (spec 7.3 and 7.9):
// "everyday" icon = obsidian letters + sindoor dot on a paper rounded square, radius 22%, 14% padding. Flat: no shadow or gradient.

enum Variant: String { case everyday, dark, launch }

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(size: Int, variant: Variant) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let canvas = CGFloat(size)
    // macOS icons sit in a 1024 canvas with a 824 tile, leaving room for the system's own treatment.
    let tile = canvas * 824 / 1024
    let origin = (canvas - tile) / 2
    let tileRect = CGRect(x: origin, y: origin, width: tile, height: tile)
    let radius = tile * 0.22

    let (tileColor, letters, dot): (UInt32, UInt32, UInt32) = switch variant {
    case .everyday: (Token.paper, Token.obsidian, Token.sindoor)
    case .dark: (Token.obsidian, Token.paper, Token.sindoor)
    case .launch: (Token.sindoor, Token.obsidian, Token.paper)
    }
    ctx.addPath(CGPath(roundedRect: tileRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(rgb(tileColor)); ctx.fillPath()

    // Fit the whole mark (letters + dot) inside the 14% padding box, centred.
    let logo = SVGPath.cgPath((try? SVGPath.parse(SparkTraceData.logoPath)) ?? [])
    let lb = logo.boundingBox
    let dotR = SparkTraceData.dotRadius
    let dotC = CGPoint(x: SparkTraceData.restX, y: SparkTraceData.restY)
    let full = lb.union(CGRect(x: dotC.x - dotR, y: dotC.y - dotR, width: dotR * 2, height: dotR * 2))
    let pad = tile * 0.14
    let box = tileRect.insetBy(dx: pad, dy: pad)
    let scale = min(box.width / full.width, box.height / full.height)
    let tx = box.midX - (full.minX + full.width / 2) * scale
    let ty = box.midY + (full.minY + full.height / 2) * scale     // SVG y points down; CoreGraphics y points up

    ctx.saveGState()
    ctx.translateBy(x: tx, y: ty); ctx.scaleBy(x: scale, y: -scale)
    ctx.addPath(logo); ctx.setFillColor(rgb(letters)); ctx.fillPath(using: .evenOdd)
    ctx.setFillColor(rgb(dot))
    ctx.fillEllipse(in: CGRect(x: dotC.x - dotR, y: dotC.y - dotR, width: dotR * 2, height: dotR * 2))
    ctx.restoreGState()
    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
}

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: room-icon <out.iconset> [everyday|dark|launch]"); exit(2) }
let out = URL(fileURLWithPath: args[1], isDirectory: true)
let variant = Variant(rawValue: args.count > 2 ? args[2] : "everyday") ?? .everyday
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                              ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                              ("icon_512x512", 512), ("icon_512x512@2x", 1024)]
for (name, px) in sizes { write(render(size: px, variant: variant), to: out.appendingPathComponent("\(name).png")) }
print("wrote \(sizes.count) images to \(out.path) (\(variant.rawValue))")
