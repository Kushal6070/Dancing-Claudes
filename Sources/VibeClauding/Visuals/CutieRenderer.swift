import SwiftUI

/// Draws the pixel cutie into a SwiftUI `GraphicsContext`.
/// Local mascot space is 384×240 with feet at y = 240; the canvas reserves room
/// around it for raised arms, sparkles, the alert badge and the floor reflection.
enum CutieRenderer {
    static let body = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
    static let blushColor = Color(red: 0xF2 / 255, green: 0xA6 / 255, blue: 0x8C / 255)
    static let eyeColor = Color.white
    static let ink = Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x18 / 255)
    static let tongueColor = Color(red: 0xE8 / 255, green: 0x69 / 255, blue: 0x7A / 255)
    static let tongueLine = Color(red: 0xC9 / 255, green: 0x4F / 255, blue: 0x60 / 255)

    // Sombrero + maracas palette (from the "sombrero + maracas" design).
    static let straw = Color(red: 0xE9 / 255, green: 0xB9 / 255, blue: 0x49 / 255)
    static let strawDark = Color(red: 0xC9 / 255, green: 0x96 / 255, blue: 0x2E / 255)
    static let trimRed = Color(red: 0xC8 / 255, green: 0x40 / 255, blue: 0x2E / 255)
    static let trimGreen = Color(red: 0x2F / 255, green: 0x8F / 255, blue: 0x5B / 255)
    static let maracaBand = Color(red: 0xF4 / 255, green: 0xE4 / 255, blue: 0xC1 / 255)
    static let maracaHandle = Color(red: 0x6B / 255, green: 0x44 / 255, blue: 0x23 / 255)

    // Canvas layout in local units.
    static let padLeft = 110.0, padRight = 110.0, padTop = 255.0, padBottom = 120.0
    static let localWidth = 384 + padLeft + padRight     // 604
    static let localHeight = 240 + padTop + padBottom
    static let feetY = padTop + 240                      // from the top
    static let centerX = padLeft + 192

    struct Look {
        var status: AgentStatus
        var kick: Double          // 0…1 pulse
        var beat: Double
        var time: Double
        var seed: Int
        var dim: Double = 1       // idle cuties are a touch dimmer
        var sombrero = false      // the Mexican cudie
        var reflection = true
    }

    static func draw(_ ctx: GraphicsContext, size: CGSize, pose: Pose, look: Look) {
        let s = size.width / localWidth
        var g = ctx
        g.translateBy(x: padLeft * s, y: padTop * s)
        g.scaleBy(x: s, y: s)

        drawFloorLight(g, pose: pose, look: look)

        if look.reflection {
            // Mirror below the feet. A plain rect clip (not a gradient mask) keeps this
            // free of offscreen passes; two bands fake the fade-out cheaply.
            for (depth, alpha) in [(40.0, 0.20), (85.0, 0.08)] {
                var r = g
                r.clip(to: Path(CGRect(x: -padLeft, y: 240 + (depth == 40 ? 0 : 40), width: localWidth, height: depth == 40 ? 40 : 45)))
                r.opacity *= alpha
                r.translateBy(x: 0, y: 480)
                r.scaleBy(x: 1, y: -1)
                drawMascot(r, pose: pose, look: look, simple: true)
            }
        }

        drawMascot(g, pose: pose, look: look, simple: false)
    }

    /// A still, happy cutie fitted into `size` (used for the "Choose your Cudie" picker).
    static func drawThumbnail(_ ctx: GraphicsContext, size: CGSize, sombrero: Bool) {
        let top = sombrero ? 112.0 : 0
        let w = 384.0, h = 240 + top
        let s = min(size.width / w, size.height / h)
        var g = ctx
        g.translateBy(x: (size.width - w * s) / 2, y: (size.height - h * s) / 2)
        g.scaleBy(x: s, y: s)
        g.translateBy(x: 0, y: top)
        var pose = Pose()
        pose.happy = 1
        let look = Look(status: .working, kick: 0, beat: 0, time: 0, seed: 1, sombrero: sombrero, reflection: false)
        drawMascot(g, pose: pose, look: look, simple: false, still: true)
    }

    // MARK: Pieces

    private static func rect(_ c: GraphicsContext, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: Color) {
        c.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(color))
    }

    private static func statusColor(_ s: AgentStatus) -> Color {
        switch s {
        case .working: Color(red: 0.36, green: 0.95, blue: 0.69)
        case .needsYou: Color(red: 1.0, green: 0.71, blue: 0.28)
        case .idle: Color(red: 0.55, green: 0.57, blue: 0.66)
        }
    }

    /// Body clay darkened toward #B95E3F for an arm crossing in front of the body.
    private static func armColor(_ shade: Double) -> Color {
        let t = min(1, max(0, shade))
        guard t > 0.01 else { return body }
        return Color(red: (0xD9 + (0xB9 - 0xD9) * t) / 255,
                     green: (0x77 + (0x5E - 0x77) * t) / 255,
                     blue: (0x57 + (0x3F - 0x57) * t) / 255)
    }

    private static func drawFloorLight(_ g: GraphicsContext, pose: Pose, look: Look) {
        var c = g
        c.blendMode = .plusLighter
        let base: Color = look.status == .needsYou ? statusColor(.needsYou) : body
        let strength = look.status == .idle ? 0.10 : (0.22 + 0.45 * look.kick)
        let w = 360.0 * pose.shadow.x
        let rect = CGRect(x: 192 + pose.shadowX - w / 2, y: 222, width: w, height: 40)
        c.fill(Path(ellipseIn: rect),
               with: .radialGradient(Gradient(colors: [base.opacity(strength * pose.shadow.y), .clear]),
                                     center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: w / 2))
        // Soft aura behind the body, pulsing on the kick.
        if look.status != .idle {
            let auraR = 230.0 + 50 * look.kick
            c.fill(Path(ellipseIn: CGRect(x: 192 - auraR, y: 96 - auraR * 0.8 + pose.lift.y, width: auraR * 2, height: auraR * 1.6)),
                   with: .radialGradient(Gradient(colors: [base.opacity(0.10 + 0.22 * look.kick), .clear]),
                                         center: CGPoint(x: 192, y: 96 + pose.lift.y), startRadius: 0, endRadius: auraR))
        }
    }

    private static func plusSpark(_ c: GraphicsContext, x: Double, y: Double, spark: V3, color: Color) {
        guard spark.x > 0.01 else { return }
        var s = c
        s.opacity *= spark.x
        s.translateBy(x: x + 14, y: y + 14)
        s.rotate(by: .degrees(spark.z))
        s.scaleBy(x: spark.y, y: spark.y)
        rect(s, -4, -14, 8, 28, color)
        rect(s, -14, -4, 28, 8, color)
    }

    private static func drawMascot(_ g: GraphicsContext, pose: Pose, look: Look, simple: Bool, still: Bool = false) {
        var base = g
        base.opacity = look.dim

        // Landing dust (twirl, stomps) stays on the ground.
        if pose.puff.x > 0.01 && !simple {
            var p = base
            p.opacity *= pose.puff.x
            let dx = 36 * pose.puff.y, dy = -10 * pose.puff.y
            rect(p, 20 - dx + 0, 222 + dy + 12, 12, 12, body)
            rect(p, 20 - dx + 14, 222 + dy, 10, 10, body)
            rect(p, 336 + dx + 16, 222 + dy + 12, 12, 12, body)
            rect(p, 336 + dx + 4, 222 + dy, 10, 10, body)
        }

        var lift = base
        lift.translateBy(x: pose.lift.x, y: pose.lift.y)

        if !simple {
            // Side sparkles.
            plusSpark(lift, x: pose.sparkPos.x, y: pose.sparkPos.y, spark: pose.sparkL, color: body)
            plusSpark(lift, x: 384 - pose.sparkPos.x - 28, y: pose.sparkPos.y, spark: pose.sparkR, color: body)
            // Clap sparks above the head (higher when there's a hat in the way).
            if pose.clap.x > 0.01 {
                var c = lift
                c.opacity *= pose.clap.x
                c.translateBy(x: 192, y: -60 - (look.sombrero ? 50 : 0))
                c.scaleBy(x: pose.clap.y, y: pose.clap.y)
                c.translateBy(x: -192, y: 60)
                rect(c, 186, -124, 12, 28, body)
                rect(c, 146, -108, 12, 12, body)
                rect(c, 226, -108, 12, 12, body)
            }
            if pose.notes.x > 0.01 { drawNotes(lift, pose: pose) }
            drawStatusBadge(lift, pose: pose, look: look)
        }

        var b = lift
        // sway: translate then rotate around the feet
        b.translateBy(x: 192 + pose.sway.x, y: 240 + pose.sway.y)
        b.rotate(by: .degrees(pose.sway.z))
        // squash, tilt and jelly-skew around the feet
        b.scaleBy(x: pose.squash.x, y: pose.squash.y)
        b.rotate(by: .degrees(pose.squash.z))
        if abs(pose.skew) > 0.01 {
            b.concatenate(CGAffineTransform(a: 1, b: 0, c: tan(pose.skew * .pi / 180), d: 1, tx: 0, ty: 0))
        }
        b.translateBy(x: -192, y: -240)
        // twirl: horizontal flip around the body center
        b.translateBy(x: 192, y: 120)
        b.scaleBy(x: abs(pose.spin) < 0.02 ? 0.02 : pose.spin, y: 1)
        b.translateBy(x: -192, y: -120)

        let behind = pose.armsBehind > 0.5
        if behind { drawArms(b, pose: pose, simple: simple) }

        // Legs (left pair, right pair)
        rect(b, 72 + pose.legLX, 190 + pose.legL, 24, 50, body)
        rect(b, 120 + pose.legLX, 190 + pose.legL, 24, 50, body)
        rect(b, 240 + pose.legRX, 190 + pose.legR, 24, 50, body)
        rect(b, 288 + pose.legRX, 190 + pose.legR, 24, 50, body)
        // Body
        rect(b, 48, 0, 288, 192, body)

        // Face only when facing us (the twirl shows the back for a moment).
        if pose.spin > 0 {
            var f = b
            f.translateBy(x: 48, y: 0)
            drawFace(f, pose: pose, look: look, still: still)
        }

        if look.sombrero && !simple {
            drawSombrero(b, pose: pose, look: look)
        }

        if !behind { drawArms(b, pose: pose, simple: simple) }
    }

    private static func drawFace(_ f: GraphicsContext, pose: Pose, look: Look, still: Bool) {
        let openAmt = max(0, 1 - pose.happy - pose.sleepy - pose.googly)
        if openAmt > 0.01 {
            var e = f
            e.opacity *= openAmt
            let blink = still ? 1 : blinkScale(time: look.time, seed: look.seed)
            let h = 48 * blink
            rect(e, 48 + pose.eyeX, 48 + (48 - h) / 2, 24, h, eyeColor)
            rect(e, 216 + pose.eyeX, 48 + (48 - h) / 2, 24, h, eyeColor)
        }
        if pose.happy > 0.01 {
            var e = f
            e.opacity *= min(1, pose.happy)
            e.translateBy(x: 0, y: 6 * (1 - min(1, pose.happy)))
            for ox in [42.0, 210.0] {
                rect(e, ox, 66, 12, 12, eyeColor)
                rect(e, ox + 12, 54, 12, 12, eyeColor)
                rect(e, ox + 24, 66, 12, 12, eyeColor)
            }
        }
        if pose.sleepy > 0.01 {
            var e = f
            e.opacity *= pose.sleepy
            rect(e, 42, 84, 36, 8, eyeColor)
            rect(e, 210, 84, 36, 8, eyeColor)
        }
        if pose.googly > 0.01 {
            var e = f
            e.opacity *= min(1, pose.googly)
            let l = pose.googlyL, r = pose.googlyR
            rect(e, 40 + l.x, 40 + l.y, 40, 48, eyeColor)
            rect(e, 54 + l.x, 58 + l.y, 16, 16, ink)
            rect(e, 212 + r.x, 44 + r.y, 32, 40, eyeColor)
            rect(e, 216 + r.x, 52 + r.y, 14, 14, ink)
        }
        var bl = f
        bl.opacity *= pose.blush
        rect(bl, 18, 108, 36, 12, blushColor)
        rect(bl, 234, 108, 36, 12, blushColor)

        if pose.mouth.x > 0.01 {
            var m = f
            m.opacity *= pose.mouth.x
            m.translateBy(x: 128, y: 112)
            m.scaleBy(x: 1, y: pose.mouth.y)
            rect(m, 0, 0, 32, 28, ink)
        }
        if pose.tongue.x > 0.01 {
            var t = f
            t.opacity *= pose.tongue.x
            t.translateBy(x: 130 + pose.tongue.y, y: 120)
            t.scaleBy(x: 1, y: pose.tongue.z)
            rect(t, 0, 0, 28, 30, tongueColor)
            rect(t, 12, 4, 4, 16, tongueLine)
        }
        if pose.shades > 0.01 {
            var s = f
            s.opacity *= pose.shades
            rect(s, 30, 46, 60, 44, ink)
            rect(s, 198, 46, 60, 44, ink)
            rect(s, 90, 54, 108, 10, ink)
        }
    }

    private static func drawArms(_ b: GraphicsContext, pose: Pose, simple: Bool) {
        let maracas = simple ? V2.zero : pose.maracas
        drawArm(b, x: 0, off: pose.armL, rot: pose.armRotL, shade: pose.armShadeL, maracas: maracas, head: trimGreen)
        drawArm(b, x: 334, off: pose.armR, rot: pose.armRotR, shade: pose.armShadeR, maracas: maracas, head: trimRed)
    }

    /// One 50×48 arm, rotated around its bottom centre, with an optional maraca behind the hand.
    private static func drawArm(_ b: GraphicsContext, x: Double, off: V2, rot: Double, shade: Double, maracas: V2, head: Color) {
        var a = b
        a.translateBy(x: x + 25 + off.x, y: 144 + off.y)
        if abs(rot) > 0.01 { a.rotate(by: .degrees(rot)) }
        if maracas.x > 0.01 {
            var m = a
            m.opacity *= maracas.x
            m.translateBy(x: 0, y: -44)
            m.rotate(by: .degrees(maracas.y))
            rect(m, -18, -68, 36, 36, head)
            rect(m, -18, -54, 36, 8, maracaBand)
            rect(m, -4, -32, 8, 32, maracaHandle)
        }
        rect(a, -25, -48, 50, 48, armColor(shade))
    }

    /// The sombrero from the design, resting on the head (body top is y = 0). Drawn in body
    /// space so it sways, squashes and twirls with the cutie; it bobs with the dance, hops on
    /// the kick and sits at a slight tilt that depends on the seed.
    private static func drawSombrero(_ b: GraphicsContext, pose: Pose, look: Look) {
        // Shadow the brim casts on the head.
        rect(b, 48, 0, 288, 10, Color.black.opacity(0.18))

        var h = b
        let tilt = (look.seed % 2 == 0 ? -3.0 : 3.0) + pose.hat.y
        h.translateBy(x: 192, y: pose.hat.x - 8 * look.kick)
        h.rotate(by: .degrees(tilt))
        h.translateBy(x: -192, y: 0)

        // Crown with its red band and green studs.
        rect(h, 156, -112, 72, 12, straw)
        rect(h, 132, -100, 120, 64, straw)
        rect(h, 132, -48, 120, 14, trimRed)
        for x in [144.0, 172, 204, 232] { rect(h, x, -45, 8, 8, trimGreen) }
        // Brim with upturned tips, a darker underside and embroidered dashes.
        rect(h, 0, -34, 24, 12, straw)
        rect(h, 360, -34, 24, 12, straw)
        rect(h, 12, -22, 360, 18, straw)
        rect(h, 12, -4, 360, 6, strawDark)
        for (x, c) in [(36.0, trimRed), (84, trimGreen), (288, trimGreen), (336, trimRed)] {
            rect(h, x, -16, 12, 6, c)
        }
    }

    /// Two music notes floating up beside the head (vibe nod).
    private static func drawNotes(_ g: GraphicsContext, pose: Pose) {
        for (i, origin) in [(0, CGPoint(x: 400, y: -40)), (1, CGPoint(x: -60, y: -10))] {
            let ph = Choreographer.fract(pose.notes.y + Double(i) * 0.5)
            let alpha = ph < 0.15 ? ph / 0.15 : (ph < 0.8 ? 1 : (1 - ph) / 0.2)
            let u = 1 - (1 - ph) * (1 - ph)
            var n = g
            n.opacity *= alpha * pose.notes.x
            n.translateBy(x: origin.x + 16 * u + 18, y: origin.y - 90 * u + 26)
            n.rotate(by: .degrees(-8 + 16 * ph))
            n.translateBy(x: -18, y: -26)
            rect(n, 0, 38, 20, 14, body)
            rect(n, 14, 0, 6, 44, body)
            rect(n, 20, 0, 12, 8, body)
            rect(n, 28, 8, 8, 8, body)
        }
    }

    private static func blinkScale(time: Double, seed: Int) -> Double {
        let period = 3.2 + Double(seed % 7) * 0.45
        let ph = (time / period + Double(seed) * 0.137).truncatingRemainder(dividingBy: 1)
        guard ph < 0.045 else { return 1 }
        let u = ph / 0.045
        return max(0.12, abs(1 - 2 * u))
    }

    /// "!" for agents waiting on you, floating "z"s for sleepy idle ones.
    private static func drawStatusBadge(_ g: GraphicsContext, pose: Pose, look: Look) {
        switch look.status {
        case .needsYou:
            let c = statusColor(.needsYou)
            var e = g
            let throb = 0.65 + 0.35 * cos(look.beat * .pi * 2)
            e.opacity *= throb
            let bob = -8 * abs(sin(look.beat * .pi))
            if look.sombrero {
                // Beside the crown instead of on top of it.
                rect(e, 290, -146 + bob, 24, 52, c)
                rect(e, 290, -86 + bob, 24, 20, c)
            } else {
                rect(e, 180, -172 + bob, 24, 52, c)
                rect(e, 180, -110 + bob, 24, 20, c)
            }
        case .idle:
            for i in 0..<2 {
                let ph = (look.time / 3.4 + Double(i) * 0.5 + Double(look.seed % 5) * 0.11).truncatingRemainder(dividingBy: 1)
                var z = g
                z.opacity *= sin(ph * .pi) * 0.85
                let sc = 0.7 + ph * 0.7
                z.translateBy(x: 322 + ph * 40 + Double(i) * 6, y: -10 - (look.sombrero ? 30 : 0) - ph * 120)
                z.scaleBy(x: sc, y: sc)
                let col = Color.white.opacity(0.9)
                rect(z, 0, 0, 24, 6, col)
                rect(z, 12, 6, 6, 6, col)
                rect(z, 6, 12, 6, 6, col)
                rect(z, 0, 18, 6, 6, col)
                rect(z, 0, 24, 24, 6, col)
            }
        case .working:
            break
        }
    }
}
