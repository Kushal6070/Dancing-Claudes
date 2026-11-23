import SwiftUI

/// Draws the pixel cutie into a SwiftUI `GraphicsContext`.
/// Local mascot space is 384×240 with feet at y = 240; the canvas reserves room
/// around it for raised arms, sparkles, the alert badge and the floor reflection.
enum CutieRenderer {
    static let body = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
    static let blushColor = Color(red: 0xF2 / 255, green: 0xA6 / 255, blue: 0x8C / 255)
    static let eyeColor = Color.white

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

    private static func drawMascot(_ g: GraphicsContext, pose: Pose, look: Look, simple: Bool) {
        var base = g
        base.opacity = look.dim

        // Landing dust (twirl) stays on the ground.
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
            // Clap sparks above the head.
            if pose.clap.x > 0.01 {
                var c = lift
                c.opacity *= pose.clap.x
                c.translateBy(x: 192, y: -60)
                c.scaleBy(x: pose.clap.y, y: pose.clap.y)
                c.translateBy(x: -192, y: 60)
                rect(c, 186, -124, 12, 28, body)
                rect(c, 146, -108, 12, 12, body)
                rect(c, 226, -108, 12, 12, body)
            }
            drawStatusBadge(lift, pose: pose, look: look)
        }

        var b = lift
        // sway: translate then rotate around the feet
        b.translateBy(x: 192 + pose.sway.x, y: 240 + pose.sway.y)
        b.rotate(by: .degrees(pose.sway.z))
        // squash & tilt around the feet
        b.scaleBy(x: pose.squash.x, y: pose.squash.y)
        b.rotate(by: .degrees(pose.squash.z))
        b.translateBy(x: -192, y: -240)
        // twirl: horizontal flip around the body center
        b.translateBy(x: 192, y: 120)
        b.scaleBy(x: abs(pose.spin) < 0.02 ? 0.02 : pose.spin, y: 1)
        b.translateBy(x: -192, y: -120)

        // Legs (left pair, right pair)
        rect(b, 72, 190 + pose.legL, 24, 50, body)
        rect(b, 120, 190 + pose.legL, 24, 50, body)
        rect(b, 240, 190 + pose.legR, 24, 50, body)
        rect(b, 288, 190 + pose.legR, 24, 50, body)
        // Body
        rect(b, 48, 0, 288, 192, body)

        // Face only when facing us (the twirl shows the back for a moment).
        if pose.spin > 0 {
            var f = b
            f.translateBy(x: 48, y: 0)
            let openAmt = max(0, 1 - pose.happy - pose.sleepy)
            if openAmt > 0.01 {
                var e = f
                e.opacity *= openAmt
                let blink = blinkScale(time: look.time, seed: look.seed)
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
            var bl = f
            bl.opacity *= pose.blush
            rect(bl, 18, 108, 36, 12, blushColor)
            rect(bl, 234, 108, 36, 12, blushColor)
        }

        // Arms
        rect(b, 0 + pose.armL.x, 96 + pose.armL.y, 50, 48, body)
        rect(b, 334 + pose.armR.x, 96 + pose.armR.y, 50, 48, body)
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
            rect(e, 180, -172 + bob, 24, 52, c)
            rect(e, 180, -110 + bob, 24, 20, c)
        case .idle:
            for i in 0..<2 {
                let ph = (look.time / 3.4 + Double(i) * 0.5 + Double(look.seed % 5) * 0.11).truncatingRemainder(dividingBy: 1)
                var z = g
                z.opacity *= sin(ph * .pi) * 0.85
                let sc = 0.7 + ph * 0.7
                z.translateBy(x: 322 + ph * 40 + Double(i) * 6, y: -10 - ph * 120)
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
