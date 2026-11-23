// Renders the app icon (black squircle, neon twist, pixel cutie) into an .iconset folder.
// Usage: swift scripts/make_icon.swift <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func render(_ px: Int) -> Data {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    // Squircle plate
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.addPath(path); ctx.setFillColor(color(0x000000)); ctx.fillPath()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()

    // Neon twisting ribbon behind the mascot
    let palette: [UInt32] = [0x1AE6FF, 0x734DFF, 0xFF38C7, 0xFF8052]
    for i in 0..<14 {
        let v = CGFloat(i) / 13 - 0.5
        let c = palette[i % palette.count]
        ctx.setStrokeColor(color(c, 0.25 + 0.55 * (1 - abs(v) * 1.4)))
        ctx.setLineWidth(5)
        ctx.setShadow(offset: .zero, blur: 18, color: color(c, 0.9))
        ctx.beginPath()
        for xi in 0...120 {
            let x = 100 + CGFloat(xi) / 120 * 824
            let u = (x - 512) / 824
            let tw = u * 7.5
            let y = 610 + 46 * sin(u * 5) + v * 210 * cos(tw)
            if xi == 0 { ctx.move(to: CGPoint(x: x, y: y)) } else { ctx.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.strokePath()
    }
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Floor glow
    let glow = CGGradient(colorsSpace: cs, colors: [color(0xD97757, 0.55), color(0xD97757, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 250), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 250), endRadius: 260, options: [])

    // Pixel cutie (mascot space 384×240, flipped into CG coords), arms up mid-wave.
    let m: CGFloat = 1.45
    let ox = 512 - 192 * m, oy: CGFloat = 270
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: UInt32) {
        ctx.setFillColor(color(c))
        ctx.fill(CGRect(x: ox + x * m, y: oy + (240 - y - h) * m, width: w * m, height: h * m))
    }
    let body: UInt32 = 0xD97757
    for x in [CGFloat(72), 120, 240, 288] { r(x, 190, 24, 50, body) }
    r(48, 0, 288, 192, body)
    for ox2 in [CGFloat(90), CGFloat(258)] { // happy ^ ^ eyes
        r(ox2, 66, 12, 12, 0xFFFFFF); r(ox2 + 12, 54, 12, 12, 0xFFFFFF); r(ox2 + 24, 66, 12, 12, 0xFFFFFF)
    }
    r(48 + 18, 108, 36, 12, 0xF2A68C); r(48 + 234, 108, 36, 12, 0xF2A68C)
    r(0, 96, 50, 48, body); r(334, 96, 50, 48, body)
    ctx.restoreGState()

    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
print("Wrote \(out.path)")
