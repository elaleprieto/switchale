// Genera el ícono de la app en Sources/Switchale/Assets.xcassets/AppIcon.appiconset.
// Uso: swift scripts/make-icon.swift
//
// Concepto: el panel del Window Switcher con tres Windows en fila y la segunda
// seleccionada, que es la selección inicial de una Switch Session y la Window que
// activa un Quick Switch.
import AppKit

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Sources/Switchale/Assets.xcassets/AppIcon.appiconset")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fillGradient(_ ctx: CGContext, _ path: CGPath, _ top: CGColor, _ bottom: CGColor, _ rect: CGRect) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    ctx.restoreGState()
}

/// Una Window: barra de título con los tres botones y contenido esquemático.
func drawWindow(_ ctx: CGContext, _ rect: CGRect, selected: Bool) {
    let radius = rect.width * 0.09
    let body = roundedRect(rect, radius)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -rect.height * 0.04),
                  blur: rect.height * 0.12, color: color(0x000000, selected ? 0.45 : 0.3))
    ctx.addPath(body)
    ctx.setFillColor(color(selected ? 0xFFFFFF : 0xC9CDE0))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()

    // Barra de título.
    let barHeight = rect.height * 0.2
    let bar = CGRect(x: rect.minX, y: rect.maxY - barHeight, width: rect.width, height: barHeight)
    ctx.setFillColor(color(selected ? 0xE6E9F5 : 0xADB2C9))
    ctx.fill(bar)

    let dot = barHeight * 0.36
    let dotColors: [UInt32] = selected ? [0xFF5F57, 0xFEBC2E, 0x28C840] : [0x8E93AB, 0x8E93AB, 0x8E93AB]
    for (i, hex) in dotColors.enumerated() {
        let x = rect.minX + barHeight * 0.45 + CGFloat(i) * dot * 1.55
        ctx.setFillColor(color(hex))
        ctx.fillEllipse(in: CGRect(x: x, y: bar.midY - dot / 2, width: dot, height: dot))
    }

    // Contenido: un bloque de color y líneas de texto.
    let inset = rect.width * 0.11
    let contentTop = bar.minY - inset * 0.8
    let block = CGRect(x: rect.minX + inset, y: contentTop - rect.height * 0.26,
                       width: rect.width * 0.34, height: rect.height * 0.26)
    ctx.addPath(roundedRect(block, rect.width * 0.03))
    ctx.setFillColor(color(selected ? 0x4C7DFF : 0x9DA3BE))
    ctx.fillPath()

    let lineHeight = rect.height * 0.055
    let lines: [(CGFloat, CGFloat)] = [  // (y relativo al tope del contenido, ancho relativo)
        (0.04, 0.32), (0.15, 0.26),
        (0.37, 0.78), (0.49, 0.6),
    ]
    for (dy, w) in lines {
        let x = dy < 0.3 ? block.maxX + inset * 0.6 : rect.minX + inset
        let line = CGRect(x: x, y: contentTop - rect.height * dy - lineHeight,
                          width: rect.width * w, height: lineHeight)
        ctx.addPath(roundedRect(line, lineHeight / 2))
        ctx.setFillColor(color(selected ? 0xCDD3E8 : 0xA6ABC3))
        ctx.fillPath()
    }
    ctx.restoreGState()
}

func renderIcon(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: size / 1024, y: size / 1024)

    // Cuerpo del ícono según la grilla de íconos de macOS: 824×824 centrado.
    let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let body = roundedRect(bodyRect, 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.35))
    ctx.addPath(body)
    ctx.setFillColor(color(0x1E2033))
    ctx.fillPath()
    ctx.restoreGState()
    fillGradient(ctx, body, color(0x3A3F66), color(0x161827), bodyRect)

    // Brillo sutil en el borde superior, como el vidrio del panel.
    ctx.saveGState()
    ctx.addPath(body)
    ctx.setStrokeColor(color(0xFFFFFF, 0.12))
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()

    // Tres Windows en fila; la del medio, seleccionada y un poco más grande.
    let side = CGSize(width: 196, height: 160)
    let middle = CGSize(width: 262, height: 214)
    let gap: CGFloat = 40
    let center = CGPoint(x: 512, y: 548)
    let left = CGRect(x: center.x - middle.width / 2 - gap - side.width, y: center.y - side.height / 2,
                      width: side.width, height: side.height)
    let right = CGRect(x: center.x + middle.width / 2 + gap, y: center.y - side.height / 2,
                       width: side.width, height: side.height)
    let selected = CGRect(x: center.x - middle.width / 2, y: center.y - middle.height / 2,
                          width: middle.width, height: middle.height)

    drawWindow(ctx, left, selected: false)
    drawWindow(ctx, right, selected: false)

    // Resaltado de la selección, como la celda seleccionada del panel.
    let highlight = selected.insetBy(dx: -24, dy: -24)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: color(0x4C7DFF, 0.8))
    ctx.addPath(roundedRect(highlight, 46))
    ctx.setFillColor(color(0x4C7DFF, 0.28))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(roundedRect(highlight, 46))
    ctx.setStrokeColor(color(0x6E96FF))
    ctx.setLineWidth(12)
    ctx.strokePath()

    drawWindow(ctx, selected, selected: true)

    // Título debajo de cada celda, como en el panel.
    let titleHeight: CGFloat = 22
    for (rect, isSelected) in [(left, false), (selected, true), (right, false)] {
        let width = rect.width * (isSelected ? 0.62 : 0.56)
        let top = highlight.minY - 30
        let title = CGRect(x: rect.midX - width / 2, y: top - titleHeight, width: width, height: titleHeight)
        ctx.addPath(roundedRect(title, titleHeight / 2))
        ctx.setFillColor(color(isSelected ? 0xFFFFFF : 0x8E93AB, isSelected ? 0.9 : 0.7))
        ctx.fillPath()
    }

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

// Tamaños de un AppIcon de macOS: (puntos, escala).
let slots: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                           (256, 1), (256, 2), (512, 1), (512, 2)]

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
var images: [[String: String]] = []
for (points, scale) in slots {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try renderIcon(pixels: points * scale).write(to: outputDir.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputDir.appendingPathComponent("Contents.json"))

let catalog = outputDir.deletingLastPathComponent().appendingPathComponent("Contents.json")
try #"{"info":{"author":"xcode","version":1}}"#.write(to: catalog, atomically: true, encoding: .utf8)
print("Ícono generado en \(outputDir.path)")
