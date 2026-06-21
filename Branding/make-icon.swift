// Gera o app icon do ScratchMate (identidade "Caret") via CoreGraphics e empacota
// num .icns. Rodar: swift Branding/make-icon.swift Branding
// Desenho conforme o design spec: bracket grafite `[` abraçando `::` âmbar aceso.
import AppKit
import Foundation

func color(_ hex: String, _ a: CGFloat = 1) -> NSColor {
    var s = hex; if s.hasPrefix("#") { s.removeFirst() }
    var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF)/255,
                   green: CGFloat((v >> 8) & 0xFF)/255,
                   blue: CGFloat(v & 0xFF)/255, alpha: a)
}

/// Desenha o ícone full-color num bitmap de lado S (pixels).
func drawIcon(_ S: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    // Padding macOS: o conteúdo (squircle) ocupa ~83% central.
    let pad = S * 0.085
    let art = S - 2 * pad
    func mx(_ x: CGFloat) -> CGFloat { pad + x / 1024 * art }              // x e tamanhos
    func my(_ y: CGFloat) -> CGFloat { pad + (1024 - y) / 1024 * art }     // y (flip top-left -> bottom-left)
    func ml(_ l: CGFloat) -> CGFloat { l / 1024 * art }
    // Rect a partir de coords top-left do spec (x, yTop, w, h).
    func rect(_ x: CGFloat, _ yTop: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: mx(x), y: my(yTop + h), width: ml(w), height: ml(h))
    }
    func rounded(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
    }

    let squircle = rounded(rect(0, 0, 1024, 1024), ml(229))

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()

    // 1. Fundo: gradiente vertical (topo elevado -> base).
    NSGradient(colors: [color("#15171C"), color("#1E212A")])?
        .draw(in: NSRect(x: 0, y: 0, width: S, height: S), angle: 90)

    // 2. Glow radial âmbar (faz o `::` parecer aceso). Antes do glyph.
    let glowCenter = NSPoint(x: mx(626), y: my(512))
    NSGradient(colors: [color("#FFB454", 0.22), color("#FFB454", 0)])?
        .draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: ml(360), options: [])

    // 3. Bracket `[` grafite (abre e não fecha).
    color("#252932").setFill()
    for r in [rect(300, 312, 52, 400), rect(300, 312, 152, 52), rect(300, 660, 152, 52)] {
        rounded(r, ml(14)).fill()
    }

    // 4. `::` quatro quadrados âmbar incandescentes (grid 2x2) com sombra/glow.
    let squares = [rect(520, 332, 128, 128), rect(520, 564, 128, 128),
                   rect(732, 332, 128, 128), rect(732, 564, 128, 128)]
    let radius = ml(128 * 0.28)
    for sq in squares {
        let path = rounded(sq, radius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color("#FFB454", 0.30)
        shadow.shadowBlurRadius = ml(28)
        shadow.shadowOffset = .zero
        shadow.set()
        color("#FFB454").setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        // Gradiente de incandescência por cima (deep embaixo -> bright em cima).
        NSGradient(colors: [color("#E8853A"), color("#FFB454"), color("#FFD08A")])?
            .draw(in: path, angle: 90)
    }

    // 5. Caret vivo opcional (só em tamanhos grandes).
    if S >= 256 {
        color("#FFB454").setFill()
        rounded(rect(900, 332, 14, 360), ml(6)).fill()
    }

    NSGraphicsContext.restoreGraphicsState()

    // 6. Hairline (contorno-tela), por cima, inset.
    let hair = rounded(rect(0, 0, 1024, 1024).insetBy(dx: ml(2), dy: ml(2)), ml(227))
    color("#2B2F38").setStroke()
    hair.lineWidth = ml(4)
    hair.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: URL(fileURLWithPath: path))
}

// --- main ---
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Branding"
let fm = FileManager.default
let iconset = "\(outDir)/ScratchMate.iconset"
try? fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let sizes: [(name: String, px: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    writePNG(drawIcon(px), to: "\(iconset)/\(name).png")
}
// Preview avulsa 1024 pra inspeção.
writePNG(drawIcon(1024), to: "\(outDir)/ScratchMate-1024.png")

// Empacota em .icns.
let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconset, "-o", "\(outDir)/ScratchMate.icns"]
task.launch(); task.waitUntilExit()
print(task.terminationStatus == 0 ? "OK: \(outDir)/ScratchMate.icns" : "iconutil falhou")
