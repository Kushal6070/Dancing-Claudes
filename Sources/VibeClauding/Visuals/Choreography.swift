import Foundation

// Dance moves for the pixel cutie, ported from the "Logo bounce animation" design
// (Bounce + clap, Shimmy, Disco point, Twirl hop, Hands-up wave, Tutu prance, Husky
// groove, Zapateado stomp, Sombrero + maracas, and the memes: Floss, Dab, Horse-ride
// trot, Bunny-ears sway, Vibe nod, Noodle flail) and re-timed so the big hits land on beats. All coordinates are in the mascot's own 384×240
// space: body (48,0,288,192), legs at x 72/120/240/288, arms at y 96, feet at y 240.

typealias V2 = SIMD2<Double>
typealias V3 = SIMD3<Double>

protocol Lerpable { static func lerp(_ a: Self, _ b: Self, _ t: Double) -> Self }
extension Double: Lerpable { static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t } }
extension SIMD2: Lerpable where Scalar == Double { static func lerp(_ a: Self, _ b: Self, _ t: Double) -> Self { a + (b - a) * t } }
extension SIMD3: Lerpable where Scalar == Double { static func lerp(_ a: Self, _ b: Self, _ t: Double) -> Self { a + (b - a) * t } }

enum Ease {
    case linear, inOut, out, `in`, backOut, hold
    func apply(_ u: Double) -> Double {
        switch self {
        case .linear: return u
        case .inOut: return u * u * (3 - 2 * u)
        case .out: let v = 1 - u; return 1 - v * v * v
        case .in: return u * u
        case .backOut:
            let c1 = 1.70158, c3 = c1 + 1, v = u - 1
            return 1 + c3 * v * v * v + c1 * v * v
        case .hold: return 0
        }
    }
}

struct Key<V: Lerpable> { let t: Double; let v: V; let e: Ease }

/// The ease on a key shapes the segment that starts at that key (CSS semantics).
func sample<V: Lerpable>(_ keys: [Key<V>], _ p: Double) -> V {
    var prev = keys[0]
    if p <= prev.t { return prev.v }
    for key in keys.dropFirst() {
        if p < key.t {
            let u = (p - prev.t) / max(key.t - prev.t, 1e-6)
            return V.lerp(prev.v, key.v, prev.e.apply(u))
        }
        prev = key
    }
    return prev.v
}

private func k1(_ t: Double, _ v: Double, _ e: Ease = .inOut) -> Key<Double> { Key(t: t, v: v, e: e) }
private func k2(_ t: Double, _ x: Double, _ y: Double, _ e: Ease = .inOut) -> Key<V2> { Key(t: t, v: V2(x, y), e: e) }
private func k3(_ t: Double, _ x: Double, _ y: Double, _ z: Double, _ e: Ease = .inOut) -> Key<V3> { Key(t: t, v: V3(x, y, z), e: e) }

/// 0 → 1 → 0 over one cycle, eased like CSS ease-in-out.
@inline(__always) private func bump(_ c: Double) -> Double { 0.5 - 0.5 * cos(2 * .pi * c) }
/// Phase within the n-th subdivision of the loop.
@inline(__always) private func cyc(_ p: Double, _ n: Double) -> Double { Choreographer.fract(p * n) }

struct Pose {
    var lift = V2.zero               // outer translate (jump / bob)
    var sway = V3.zero               // tx, ty, degrees around the feet
    var squash = V3(1, 1, 0)         // sx, sy, degrees around the feet
    var spin = 1.0                   // scaleX around the body center (twirl)
    var armL = V2.zero
    var armR = V2.zero
    var legL = 0.0
    var legR = 0.0
    var eyeX = 0.0
    var happy = 0.0                  // 0 = open eyes, 1 = ^ ^ eyes
    var sleepy = 0.0                 // 1 = closed — — eyes
    var blush = 1.0
    var clap = V2(0, 1)              // opacity, scale of the sparks above the head
    var sparkL = V3(0, 1, 0)         // opacity, scale, degrees
    var sparkR = V3(0, 1, 0)
    var sparkPos = V2(-64, -30)      // left spark origin; right one is mirrored
    var puff = V2.zero               // landing dust: opacity, spread
    var shadow = V2(1, 1)            // scaleX, opacity
    var shadowX = 0.0

    // Limbs
    var armRotL = 0.0, armRotR = 0.0      // degrees around the arm's bottom centre
    var armShadeL = 0.0, armShadeR = 0.0  // 1 = darker clay, for an arm crossing in front of the body
    var armsBehind = 0.0                  // > 0.5 draws the arms behind the body (floss)
    var legLX = 0.0, legRX = 0.0
    var skew = 0.0                        // skewX degrees around the feet (noodle jelly)

    // Props and faces
    var hat = V2.zero                     // sombrero bob: dy, degrees
    var shades = 0.0                      // sunglasses opacity
    var tongue = V3(0, 0, 1)              // opacity, dx, scaleY
    var googly = 0.0                      // googly eyes (replace the normal eyes)
    var googlyL = V2.zero, googlyR = V2.zero
    var mouth = V2(0, 1)                  // opacity, scaleY
    var maracas = V2.zero                 // opacity, shake degrees
    var notes = V2.zero                   // opacity, phase 0…1

    static func lerp(_ a: Pose, _ b: Pose, _ t: Double) -> Pose {
        var o = Pose()
        o.lift = .lerp(a.lift, b.lift, t); o.sway = .lerp(a.sway, b.sway, t)
        o.squash = .lerp(a.squash, b.squash, t); o.spin = .lerp(a.spin, b.spin, t)
        o.armL = .lerp(a.armL, b.armL, t); o.armR = .lerp(a.armR, b.armR, t)
        o.legL = .lerp(a.legL, b.legL, t); o.legR = .lerp(a.legR, b.legR, t)
        o.eyeX = .lerp(a.eyeX, b.eyeX, t); o.happy = .lerp(a.happy, b.happy, t)
        o.sleepy = .lerp(a.sleepy, b.sleepy, t); o.blush = .lerp(a.blush, b.blush, t)
        o.clap = .lerp(a.clap, b.clap, t); o.sparkL = .lerp(a.sparkL, b.sparkL, t)
        o.sparkR = .lerp(a.sparkR, b.sparkR, t); o.sparkPos = .lerp(a.sparkPos, b.sparkPos, t)
        o.puff = .lerp(a.puff, b.puff, t); o.shadow = .lerp(a.shadow, b.shadow, t)
        o.shadowX = .lerp(a.shadowX, b.shadowX, t)
        o.armRotL = .lerp(a.armRotL, b.armRotL, t); o.armRotR = .lerp(a.armRotR, b.armRotR, t)
        o.armShadeL = .lerp(a.armShadeL, b.armShadeL, t); o.armShadeR = .lerp(a.armShadeR, b.armShadeR, t)
        o.armsBehind = .lerp(a.armsBehind, b.armsBehind, t)
        o.legLX = .lerp(a.legLX, b.legLX, t); o.legRX = .lerp(a.legRX, b.legRX, t)
        o.skew = .lerp(a.skew, b.skew, t)
        o.hat = .lerp(a.hat, b.hat, t); o.shades = .lerp(a.shades, b.shades, t)
        o.tongue = .lerp(a.tongue, b.tongue, t); o.googly = .lerp(a.googly, b.googly, t)
        o.googlyL = .lerp(a.googlyL, b.googlyL, t); o.googlyR = .lerp(a.googlyR, b.googlyR, t)
        o.mouth = .lerp(a.mouth, b.mouth, t); o.maracas = .lerp(a.maracas, b.maracas, t)
        o.notes = .lerp(a.notes, b.notes, t)
        return o
    }

    /// Scales motion (not faces or sparkles) toward rest; >1 exaggerates.
    func amplified(_ k: Double) -> Pose {
        let rest = Pose()
        var o = self
        o.lift = rest.lift + (lift - rest.lift) * k
        o.sway = rest.sway + (sway - rest.sway) * k
        o.squash = rest.squash + (squash - rest.squash) * k
        o.armL = armL * k; o.armR = armR * k
        o.legL = legL * k; o.legR = legR * k
        o.shadow = V2(1 + (shadow.x - 1) * k, 1 + (shadow.y - 1) * k)
        o.shadowX = shadowX * k
        o.armRotL = armRotL * k; o.armRotR = armRotR * k
        o.legLX = legLX * k; o.legRX = legRX * k
        o.skew = skew * k
        return o
    }
}

enum Dance: CaseIterable {
    case bounce, shimmy, disco, twirl, wave, snooze
    case prance, husky, stomp, maracas
    case floss, dab, horse, ears, vibe, noodle

    /// How many beats one loop of the move takes (must divide the 8-beat section).
    var beats: Double {
        switch self {
        case .bounce, .disco, .twirl, .husky, .stomp, .dab, .horse, .vibe: 4
        case .shimmy, .wave, .prance, .maracas, .floss, .ears: 2
        case .snooze, .noodle: 8
        }
    }

    func pose(_ p: Double) -> Pose {
        switch self {
        case .bounce: Moves.bounce(p)
        case .shimmy: Moves.shimmy(p)
        case .disco: Moves.disco(p)
        case .twirl: Moves.twirl(p)
        case .wave: Moves.wave(p)
        case .snooze: Moves.snooze(p)
        case .prance: Moves.prance(p)
        case .husky: Moves.husky(p)
        case .stomp: Moves.stomp(p)
        case .maracas: Moves.maracas(p)
        case .floss: Moves.floss(p)
        case .dab: Moves.dab(p)
        case .horse: Moves.horse(p)
        case .ears: Moves.ears(p)
        case .vibe: Moves.vibe(p)
        case .noodle: Moves.noodle(p)
        }
    }
}

private enum Moves {
    // MARK: Bounce + clap (4 beats: crouch on 1, claps on 2& and 3, land on 4)
    static let bJump = [k1(0, 0), k1(0.06, 0, .out), k1(0.25, -112), k1(0.5, -120, .in), k1(0.75, 0, .out), k1(0.82, -22, .in), k1(0.875, 0), k1(1, 0)]
    static let bSquash = [k3(0, 1.1, 0.86, 0), k3(0.06, 1.1, 0.86, 0), k3(0.14, 0.94, 1.08, 0), k3(0.25, 1, 1, 0), k3(0.70, 0.96, 1.05, 0),
                          k3(0.75, 1.12, 0.84, -3), k3(0.81, 0.97, 1.04, 3), k3(0.875, 1.06, 0.93, -2), k3(0.94, 1, 1, 1), k3(1, 1.1, 0.86, 0)]
    static let bArm = [k2(0, 0, 8), k2(0.06, 0, 8), k2(0.18, 40, -140), k2(0.28, 118, -168), k2(0.375, 144, -168), k2(0.44, 120, -172),
                       k2(0.5, 144, -168), k2(0.58, 110, -160), k2(0.72, 0, 0), k2(0.78, 0, 6), k2(1, 0, 8)]
    static let bHappy = [k1(0, 0, .linear), k1(0.2, 0, .linear), k1(0.24, 1, .linear), k1(0.62, 1, .linear), k1(0.66, 0, .linear), k1(1, 0)]
    static let bBlush = [k1(0, 0.55), k1(0.2, 0.55), k1(0.26, 1), k1(0.62, 1), k1(0.68, 0.55), k1(1, 0.55)]
    static let bClapA = [k1(0, 0, .linear), k1(0.36, 0, .linear), k1(0.375, 1, .linear), k1(0.42, 0, .linear), k1(0.485, 0, .linear),
                         k1(0.5, 1, .linear), k1(0.55, 0, .linear), k1(1, 0)]
    static let bClapS = [k1(0, 0.4, .linear), k1(0.36, 0.4, .linear), k1(0.375, 1, .linear), k1(0.42, 1.3, .linear), k1(0.485, 0.4, .linear),
                         k1(0.5, 1, .linear), k1(0.55, 1.3, .linear), k1(1, 1.3)]
    static let bShadow = [k2(0, 1.08, 1), k2(0.06, 1.08, 1), k2(0.25, 0.55, 0.45), k2(0.5, 0.55, 0.45), k2(0.75, 1.1, 1),
                          k2(0.82, 0.88, 0.8), k2(0.875, 1.04, 1), k2(1, 1.08, 1)]

    static func bounce(_ p: Double) -> Pose {
        var o = Pose()
        o.lift = V2(0, sample(bJump, p))
        o.squash = sample(bSquash, p)
        let a = sample(bArm, p); o.armL = a; o.armR = V2(-a.x, a.y)
        o.happy = sample(bHappy, p)
        o.blush = sample(bBlush, p)
        o.clap = V2(sample(bClapA, p), sample(bClapS, p))
        o.shadow = sample(bShadow, p)
        return o
    }

    // MARK: Shimmy (2 beats: squash on each beat, lean on the "and")
    static let sSway = [k3(0, 0, 0, 0), k3(0.25, -28, -8, -7), k3(0.5, 0, 0, 0), k3(0.75, 28, -8, 7), k3(1, 0, 0, 0)]
    static let sBop = [k3(0, 1.06, 0.93, 0), k3(0.25, 0.97, 1.04, 0), k3(0.5, 1.06, 0.93, 0), k3(0.75, 0.97, 1.04, 0), k3(1, 1.06, 0.93, 0)]
    static let sLegL = [k1(0, 0), k1(0.2, -16), k1(0.4, 0), k1(1, 0)]
    static let sLegR = [k1(0, 0), k1(0.5, 0), k1(0.7, -16), k1(0.9, 0), k1(1, 0)]
    static let sArmL = [k2(0, 0, 0), k2(0.25, -8, -84), k2(0.5, 0, 0), k2(1, 0, 0)]
    static let sArmR = [k2(0, 0, 0), k2(0.5, 0, 0), k2(0.75, 8, -84), k2(1, 0, 0)]
    static let sSparkL = [k3(0, 0, 0.4, 0, .linear), k3(0.16, 0, 0.4, 0, .linear), k3(0.25, 1, 1, 45, .linear), k3(0.36, 0, 1.2, 90, .linear), k3(1, 0, 1.2, 90)]
    static let sSparkR = [k3(0, 0, 0.4, 0, .linear), k3(0.66, 0, 0.4, 0, .linear), k3(0.75, 1, 1, -45, .linear), k3(0.86, 0, 1.2, -90, .linear), k3(1, 0, 1.2, -90)]
    static let sShadow = [k1(0, 0), k1(0.25, -28), k1(0.5, 0), k1(0.75, 28), k1(1, 0)]

    static func shimmy(_ p: Double) -> Pose {
        var o = Pose()
        o.sway = sample(sSway, p)
        o.squash = sample(sBop, p)
        o.legL = sample(sLegL, p); o.legR = sample(sLegR, p)
        o.armL = sample(sArmL, p); o.armR = sample(sArmR, p)
        o.happy = 1
        o.sparkL = sample(sSparkL, p); o.sparkR = sample(sSparkR, p)
        o.sparkPos = V2(-64, -30)
        o.shadowX = sample(sShadow, p)
        o.shadow = V2(1.04 - abs(o.shadowX) / 280, 1)
        return o
    }

    // MARK: Disco point (4 beats: bop every beat, switch arms on 3)
    static let dBop = [k1(0, 0), k1(0.125, -16), k1(0.25, 0), k1(0.375, -16), k1(0.5, 0), k1(0.625, -16), k1(0.75, 0), k1(0.875, -16), k1(1, 0)]
    static let dTilt = [k1(0, -6), k1(0.44, -6), k1(0.5, 6), k1(0.94, 6), k1(1, -6)]
    static let dArmL = [k2(0, -22, -110), k2(0.44, -22, -110, .backOut), k2(0.5, 6, 44), k2(0.94, 6, 44, .backOut), k2(1, -22, -110)]
    static let dArmR = [k2(0, -6, 44), k2(0.44, -6, 44, .backOut), k2(0.5, 22, -110), k2(0.94, 22, -110, .backOut), k2(1, -6, 44)]
    static let dEye = [k1(0, -10), k1(0.44, -10), k1(0.5, 10), k1(0.94, 10), k1(1, -10)]
    static let dSparkL = [k3(0, 0, 0.4, 0, .linear), k3(0.08, 1, 1, 45, .linear), k3(0.2, 0.25, 0.7, 45, .linear), k3(0.3, 1, 1.1, 90, .linear), k3(0.44, 0, 0.4, 135, .linear), k3(1, 0, 0.4, 135)]
    static let dSparkR = [k3(0, 0, 0.4, 0, .linear), k3(0.5, 0, 0.4, 0, .linear), k3(0.58, 1, 1, -45, .linear), k3(0.7, 0.25, 0.7, -45, .linear), k3(0.8, 1, 1.1, -90, .linear), k3(0.94, 0, 0.4, -135, .linear), k3(1, 0, 0.4, -135)]
    static let dShadow = [k2(0, 1.04, 1), k2(0.125, 0.86, 0.7), k2(0.25, 1.04, 1), k2(0.375, 0.86, 0.7), k2(0.5, 1.04, 1),
                          k2(0.625, 0.86, 0.7), k2(0.75, 1.04, 1), k2(0.875, 0.86, 0.7), k2(1, 1.04, 1)]

    static func disco(_ p: Double) -> Pose {
        var o = Pose()
        o.lift = V2(0, sample(dBop, p))
        o.squash = V3(1, 1, sample(dTilt, p))
        o.armL = sample(dArmL, p); o.armR = sample(dArmR, p)
        o.eyeX = sample(dEye, p)
        o.sparkL = sample(dSparkL, p); o.sparkR = sample(dSparkR, p)
        o.sparkPos = V2(-84, -60)
        o.shadow = sample(dShadow, p)
        return o
    }

    // MARK: Twirl hop (4 beats: crouch, airborne spin, land on 3, little hop to 4)
    static let tJump = [k1(0, 0), k1(0.06, 0, .out), k1(0.25, -100, .in), k1(0.5, 0, .out), k1(0.625, -16, .in), k1(0.75, 0), k1(1, 0)]
    static let tSquash = [k3(0, 1.1, 0.86, 0), k3(0.06, 1.1, 0.86, 0), k3(0.12, 0.95, 1.06, 0), k3(0.46, 0.97, 1.04, 0), k3(0.5, 1.12, 0.85, 0),
                          k3(0.56, 0.97, 1.04, 0), k3(0.625, 1, 1, 0), k3(0.75, 1.05, 0.95, 0), k3(0.82, 1, 1, 0), k3(0.94, 1, 1, 0), k3(1, 1.1, 0.86, 0)]
    static let tSpin = [k1(0, 1), k1(0.08, 1), k1(0.16, 0.08, .linear), k1(0.25, -1), k1(0.34, 0.08, .linear), k1(0.44, 1), k1(1, 1)]
    static let tArm = [k2(0, 0, 0), k2(0.06, 0, 0), k2(0.12, -24, -36), k2(0.44, -24, -36), k2(0.52, 0, 0), k2(1, 0, 0)]
    static let tHappy = [k1(0, 0, .linear), k1(0.07, 0, .linear), k1(0.09, 1, .linear), k1(0.5, 1, .linear), k1(0.52, 0, .linear), k1(1, 0)]
    static let tPuff = [k2(0, 0, 0, .linear), k2(0.49, 0, 0, .linear), k2(0.5, 1, 0, .out), k2(0.64, 0, 1, .linear), k2(1, 0, 1)]
    static let tShadow = [k2(0, 1.08, 1), k2(0.06, 1.08, 1), k2(0.25, 0.55, 0.45), k2(0.5, 1.1, 1), k2(0.625, 0.9, 0.8), k2(0.75, 1, 1), k2(1, 1.08, 1)]

    static func twirl(_ p: Double) -> Pose {
        var o = Pose()
        o.lift = V2(0, sample(tJump, p))
        o.squash = sample(tSquash, p)
        o.spin = sample(tSpin, p)
        let a = sample(tArm, p); o.armL = a; o.armR = V2(-a.x, a.y)
        o.happy = sample(tHappy, p)
        o.puff = sample(tPuff, p)
        o.shadow = sample(tShadow, p)
        return o
    }

    // MARK: Hands-up wave (2 beats)
    static let wBob = [k1(0, 0), k1(0.25, -14), k1(0.5, 0), k1(0.75, -14), k1(1, 0)]
    static let wSway = [k1(0, 0), k1(0.25, -5), k1(0.5, 0), k1(0.75, 5), k1(1, 0)]
    static let wArmL = [k2(0, 48, -150), k2(0.25, 8, -166), k2(0.5, 48, -150), k2(0.75, 88, -166), k2(1, 48, -150)]
    static let wArmR = [k2(0, -48, -150), k2(0.25, -88, -166), k2(0.5, -48, -150), k2(0.75, -8, -166), k2(1, -48, -150)]
    static let wSparkL = [k3(0, 0, 0.4, 0, .linear), k3(0.14, 0, 0.4, 0, .linear), k3(0.25, 1, 1, 45, .linear), k3(0.38, 0, 1.2, 90, .linear), k3(1, 0, 1.2, 90)]
    static let wSparkR = [k3(0, 0, 0.4, 0, .linear), k3(0.64, 0, 0.4, 0, .linear), k3(0.75, 1, 1, -45, .linear), k3(0.88, 0, 1.2, -90, .linear), k3(1, 0, 1.2, -90)]
    static let wShadow = [k2(0, 1.04, 1), k2(0.25, 0.88, 0.75), k2(0.5, 1.04, 1), k2(0.75, 0.88, 0.75), k2(1, 1.04, 1)]

    static func wave(_ p: Double) -> Pose {
        var o = Pose()
        o.lift = V2(0, sample(wBob, p))
        o.squash = V3(1, 1, sample(wSway, p))
        o.armL = sample(wArmL, p); o.armR = sample(wArmR, p)
        o.happy = 1
        o.sparkL = sample(wSparkL, p); o.sparkR = sample(wSparkR, p)
        o.sparkPos = V2(-40, -110)
        o.shadow = sample(wShadow, p)
        return o
    }

    // MARK: Snooze (idle: slow breathing sway, eyes closed)
    static let zBreath = [k3(0, 1, 1, -1.5), k3(0.5, 1.025, 0.965, 1.5), k3(1, 1, 1, -1.5)]
    static let zArm = [k2(0, 0, 4), k2(0.5, 0, 10), k2(1, 0, 4)]

    static func snooze(_ p: Double) -> Pose {
        var o = Pose()
        o.squash = sample(zBreath, p)
        let a = sample(zArm, p); o.armL = a; o.armR = a
        o.sleepy = 1
        o.blush = 0.45
        o.shadow = V2(1, 0.8)
        return o
    }

    // MARK: Tutu prance (2 beats: a high knee on each "and", arms up in a V)
    static let pLift = [k1(0, 0, .out), k1(0.25, -44, .in), k1(0.5, 0, .out), k1(0.75, -44, .in), k1(1, 0)]
    static let pSquash = [k3(0, 1.08, 0.9, 0), k3(0.10, 0.96, 1.05, -2), k3(0.25, 1, 1, -5), k3(0.42, 0.98, 1.03, 0), k3(0.5, 1.08, 0.9, 0),
                          k3(0.60, 0.96, 1.05, 2), k3(0.75, 1, 1, 5), k3(0.92, 0.98, 1.03, 0), k3(1, 1.08, 0.9, 0)]
    static let pLegL = [k2(0, 0, 0), k2(0.08, 0, 0), k2(0.25, -8, -38), k2(0.42, 0, 0), k2(1, 0, 0)]
    static let pLegR = [k2(0, 0, 0), k2(0.58, 0, 0), k2(0.75, 8, -38), k2(0.92, 0, 0), k2(1, 0, 0)]
    static let pArm = [k3(0, 18, -136, -18), k3(0.25, 14, -152, -28), k3(0.5, 18, -136, -18), k3(0.75, 14, -152, -28), k3(1, 18, -136, -18)]
    static let pShadow = [k2(0, 1.08, 1), k2(0.25, 0.7, 0.55), k2(0.5, 1.08, 1), k2(0.75, 0.7, 0.55), k2(1, 1.08, 1)]

    static func prance(_ p: Double) -> Pose {
        var o = Pose()
        o.lift = V2(0, sample(pLift, p))
        o.squash = sample(pSquash, p)
        let l = sample(pLegL, p), r = sample(pLegR, p)
        o.legLX = l.x; o.legL = l.y; o.legRX = r.x; o.legR = r.y
        let a = sample(pArm, p)
        o.armL = V2(a.x, a.y); o.armRotL = a.z
        o.armR = V2(-a.x, a.y); o.armRotR = -a.z
        o.happy = 1
        o.shadow = sample(pShadow, p)
        return o
    }

    // MARK: Husky groove (4 beats: goofy lean left then right, tongue out, spin + hop to finish)
    static let hHop = [k1(0, 0), k1(0.80, 0, .out), k1(0.88, -40, .in), k1(0.97, 0), k1(1, 0)]
    static let hLean = [k3(0, 0, 0, 0), k3(0.15, -26, 0, -10), k3(0.25, -26, 0, -10), k3(0.38, 0, 0, 0), k3(0.5, 0, 0, 0),
                        k3(0.65, 26, 0, 10), k3(0.75, 26, 0, 10), k3(0.82, 0, 0, 0), k3(1, 0, 0, 0)]
    static let hBop = [k3(0, 1, 1, 0), k3(0.1, 1.08, 0.9, 0), k3(0.2, 0.97, 1.04, 0), k3(0.3, 1.08, 0.9, 0), k3(0.4, 0.97, 1.04, 0), k3(0.5, 1, 1, 0),
                       k3(0.6, 1.08, 0.9, 0), k3(0.7, 0.97, 1.04, 0), k3(0.8, 1.1, 0.88, 0), k3(0.88, 0.95, 1.06, 0), k3(0.97, 1.08, 0.9, 0), k3(1, 1, 1, 0)]
    static let hSpin = [k1(0, 1), k1(0.82, 1), k1(0.86, 0.08, .linear), k1(0.90, -1), k1(0.94, 0.08, .linear), k1(0.98, 1), k1(1, 1)]
    static let hLegL = [k2(0, 0, 0), k2(0.15, -18, -12), k2(0.25, -18, -12), k2(0.38, 0, 0), k2(0.5, 0, 0),
                        k2(0.65, -12, 0), k2(0.75, -12, 0), k2(0.82, 0, 0), k2(1, 0, 0)]
    static let hLegR = [k2(0, 0, 0), k2(0.15, 12, 0), k2(0.25, 12, 0), k2(0.38, 0, 0), k2(0.5, 0, 0),
                        k2(0.65, 18, -12), k2(0.75, 18, -12), k2(0.82, 0, 0), k2(1, 0, 0)]
    static let hArmL = [k2(0, 0, 0, .backOut), k2(0.15, -6, 34, .backOut), k2(0.25, -6, 34, .backOut), k2(0.38, -18, -50, .backOut), k2(0.5, 0, 0, .backOut),
                        k2(0.65, -26, -140, .backOut), k2(0.75, -26, -140, .backOut), k2(0.82, -20, -40, .backOut), k2(0.9, -30, -24, .backOut), k2(1, 0, 0)]
    static let hArmR = [k2(0, 0, 0, .backOut), k2(0.15, 26, -140, .backOut), k2(0.25, 26, -140, .backOut), k2(0.38, 18, -50, .backOut), k2(0.5, 0, 0, .backOut),
                        k2(0.65, 6, 34, .backOut), k2(0.75, 6, 34, .backOut), k2(0.82, 20, -40, .backOut), k2(0.9, 30, -24, .backOut), k2(1, 0, 0)]
    static let hShadow = [k3(0, 0, 1.04, 1), k3(0.2, -26, 1.1, 1), k3(0.5, 0, 1.04, 1), k3(0.7, 26, 1.1, 1),
                          k3(0.88, 0, 0.75, 0.6), k3(0.97, 0, 1.04, 1), k3(1, 0, 1.04, 1)]

    static func husky(_ p: Double) -> Pose {
        var o = Pose()
        o.lift = V2(0, sample(hHop, p))
        o.sway = sample(hLean, p)
        o.squash = sample(hBop, p)
        o.spin = sample(hSpin, p)
        let l = sample(hLegL, p), r = sample(hLegR, p)
        o.legLX = l.x; o.legL = l.y; o.legRX = r.x; o.legR = r.y
        o.armL = sample(hArmL, p); o.armR = sample(hArmR, p)
        o.happy = 1
        let wag = bump(cyc(p, 4))
        o.tongue = V3(1, -3 + 6 * wag, 1 + 0.15 * wag)
        let sh = sample(hShadow, p)
        o.shadowX = sh.x; o.shadow = V2(sh.y, sh.z)
        return o
    }

    // MARK: Zapateado stomp (4 beats: a stomp on every beat, bounce on every half beat,
    // shuffling side to side with fists pumping and the sombrero bobbing)
    static let zTravel = [k3(0, -36, 0, -4), k3(0.5, 36, 0, 4), k3(1, -36, 0, -4)]
    static let zLeg = [k1(0, 0), k1(0.25, -20), k1(0.5, 0), k1(1, 0)]          // one beat; the right leg runs half a beat behind
    static let zRaiseL = [k2(0, 0, 0, .backOut), k2(0.42, 0, 0, .backOut), k2(0.5, -8, -112, .backOut), k2(0.92, -8, -112, .backOut), k2(1, 0, 0)]
    static let zRaiseR = [k2(0, 8, -112, .backOut), k2(0.42, 8, -112, .backOut), k2(0.5, 0, 0, .backOut), k2(0.92, 0, 0, .backOut), k2(1, 8, -112)]
    static let zBangL = [k3(0, 0, 0.4, 0, .linear), k3(0.48, 0, 0.4, 0, .linear), k3(0.56, 1, 1, 0, .linear), k3(0.62, 1, 1, 0, .linear),
                         k3(0.70, 0, 1.2, 0, .linear), k3(1, 0, 1.2, 0)]
    static let zBangR = [k3(0, 1, 1, 0, .linear), k3(0.06, 1, 1, 0, .linear), k3(0.14, 0, 1.2, 0, .linear), k3(1, 0, 1.2, 0)]

    static func stomp(_ p: Double) -> Pose {
        var o = Pose()
        let travel = sample(zTravel, p)
        let b = bump(cyc(p, 8))
        o.lift = V2(0, -14 * b)
        o.sway = travel
        o.squash = V3(1.05 - 0.07 * b, 0.94 + 0.09 * b, 0)
        let beat = cyc(p, 4)
        o.legL = sample(zLeg, beat)
        o.legR = sample(zLeg, Choreographer.fract(beat + 0.5))
        let pump = V2(0, -20 * b)
        o.armL = sample(zRaiseL, p) + pump; o.armR = sample(zRaiseR, p) + pump
        let hb = bump(beat)
        o.hat = V2(-6 * hb, -3 + 6 * hb)
        o.happy = 1
        o.sparkL = sample(zBangL, p); o.sparkR = sample(zBangR, p)
        o.sparkPos = V2(-44, -88)
        let c8 = cyc(p, 8)
        o.puff = V2(max(0, 1 - c8 / 0.8), c8 / 0.8)
        o.shadowX = travel.x
        o.shadow = V2(1.02 - 0.08 * b, 1 - 0.2 * b)
        return o
    }

    // MARK: Sombrero + maracas (2 beats: side-to-side hop, maracas shaking in triplets)
    static let mLift = [k1(0, 0, .out), k1(0.25, -26, .in), k1(0.5, 0, .out), k1(0.75, -26, .in), k1(1, 0)]
    static let mSway = [k3(0, 0, 0, 0), k3(0.25, -22, 0, -6), k3(0.5, 0, 0, 0), k3(0.75, 22, 0, 6), k3(1, 0, 0, 0)]
    static let mSquash = [k3(0, 1.05, 0.94, 0), k3(0.25, 1, 1, 0), k3(0.5, 1.05, 0.94, 0), k3(0.75, 1, 1, 0), k3(1, 1.05, 0.94, 0)]
    static let mHat = [k2(0, 0, 0), k2(0.32, -12, -4), k2(0.5, 0, 0), k2(0.82, -12, 4), k2(1, 0, 0)]
    static let mLegL = [k2(0, 0, 0), k2(0.10, 0, 0), k2(0.25, -12, -18), k2(0.40, 0, 0), k2(1, 0, 0)]
    static let mLegR = [k2(0, 0, 0), k2(0.60, 0, 0), k2(0.75, 12, -18), k2(0.90, 0, 0), k2(1, 0, 0)]
    static let mArmL = [k2(0, -10, -50), k2(0.25, -34, -112), k2(0.5, -10, -50), k2(0.75, -4, -10), k2(1, -10, -50)]
    static let mArmR = [k2(0, 10, -50), k2(0.25, 4, -10), k2(0.5, 10, -50), k2(0.75, 34, -112), k2(1, 10, -50)]
    static let mShadow = [k3(0, 0, 1.06, 1), k3(0.25, -22, 0.82, 0.7), k3(0.5, 0, 1.06, 1), k3(0.75, 22, 0.82, 0.7), k3(1, 0, 1.06, 1)]

    static func maracas(_ p: Double) -> Pose {
        var o = Pose()
        o.lift = V2(0, sample(mLift, p))
        o.sway = sample(mSway, p)
        o.squash = sample(mSquash, p)
        o.hat = sample(mHat, p)
        let l = sample(mLegL, p), r = sample(mLegR, p)
        o.legLX = l.x; o.legL = l.y; o.legRX = r.x; o.legR = r.y
        o.armL = sample(mArmL, p); o.armR = sample(mArmR, p)
        let c = cyc(p, 6)
        o.maracas = V2(1, -14 + 28 * (c < 0.5 ? 2 * c : 2 - 2 * c))
        o.happy = 1
        let sh = sample(mShadow, p)
        o.shadowX = sh.x; o.shadow = V2(sh.y, sh.z)
        return o
    }

    // MARK: The floss (2 beats: arms swing across behind the body while the hips go the other way)
    static let fUpper = [k3(0, 0, 0, 0), k3(0.25, -14, 0, -4), k3(0.5, 0, 0, 0), k3(0.75, 14, 0, 4), k3(1, 0, 0, 0)]
    static let fHips = [k1(0, 0), k1(0.25, 28), k1(0.5, 0), k1(0.75, -28), k1(1, 0)]
    static let fArmL = [k2(0, 0, 0), k2(0.25, -40, -34), k2(0.5, 0, 0), k2(0.75, 372, 30), k2(1, 0, 0)]
    static let fArmR = [k2(0, 0, 0), k2(0.25, -372, 30), k2(0.5, 0, 0), k2(0.75, 40, -34), k2(1, 0, 0)]

    static func floss(_ p: Double) -> Pose {
        var o = Pose()
        o.lift = V2(0, -10 * bump(cyc(p, 2)))
        let upper = sample(fUpper, p)
        o.sway = upper
        let hips = sample(fHips, p) - upper.x      // legs ride on the upper body's transform
        o.legLX = hips; o.legRX = hips
        o.armL = sample(fArmL, p); o.armR = sample(fArmR, p)
        o.armsBehind = 1
        o.shadowX = -upper.x
        return o
    }

    // MARK: The dab (4 beats: dab left on 2, dab right on 4)
    static let dbBop = [k1(0, 0), k1(0.10, -18), k1(0.20, 0), k1(0.56, 0), k1(0.63, -18), k1(0.70, 0), k1(1, 0)]
    static let dbTilt = [k3(0, 0, 0, 0, .backOut), k3(0.20, 0, 0, 0, .backOut), k3(0.28, -12, 0, -14, .backOut), k3(0.46, -12, 0, -14, .backOut),
                         k3(0.54, 0, 0, 0, .backOut), k3(0.70, 0, 0, 0, .backOut), k3(0.78, 12, 0, 14, .backOut), k3(0.96, 12, 0, 14, .backOut), k3(1, 0, 0, 0)]
    static let dbArmL = [k2(0, 0, 0, .backOut), k2(0.20, 0, 0, .backOut), k2(0.28, -38, -118, .backOut), k2(0.46, -38, -118, .backOut),
                         k2(0.54, 0, 0, .backOut), k2(0.70, 0, 0, .backOut), k2(0.78, 251, -46, .backOut), k2(0.96, 251, -46, .backOut), k2(1, 0, 0)]
    static let dbArmR = [k2(0, 0, 0, .backOut), k2(0.20, 0, 0, .backOut), k2(0.28, -251, -46, .backOut), k2(0.46, -251, -46, .backOut),
                         k2(0.54, 0, 0, .backOut), k2(0.70, 0, 0, .backOut), k2(0.78, 38, -118, .backOut), k2(0.96, 38, -118, .backOut), k2(1, 0, 0)]
    static let dbShadeL = [k1(0, 0), k1(0.70, 0), k1(0.78, 1), k1(0.96, 1), k1(1, 0)]
    static let dbShadeR = [k1(0, 0), k1(0.20, 0), k1(0.28, 1), k1(0.46, 1), k1(0.54, 0), k1(1, 0)]
    static let dbHitL = [k3(0, 0, 0.4, 0, .linear), k3(0.26, 0, 0.4, 0, .linear), k3(0.30, 1, 1, 0, .linear), k3(0.38, 1, 1, 0, .linear),
                         k3(0.46, 0, 1.3, 0, .linear), k3(1, 0, 1.3, 0)]
    static let dbHitR = [k3(0, 0, 0.4, 0, .linear), k3(0.76, 0, 0.4, 0, .linear), k3(0.80, 1, 1, 0, .linear), k3(0.88, 1, 1, 0, .linear),
                         k3(0.96, 0, 1.3, 0, .linear), k3(1, 0, 1.3, 0)]

    static func dab(_ p: Double) -> Pose {
        var o = Pose()
        o.lift = V2(0, sample(dbBop, p))
        o.sway = sample(dbTilt, p)
        o.armL = sample(dbArmL, p); o.armR = sample(dbArmR, p)
        o.armShadeL = sample(dbShadeL, p); o.armShadeR = sample(dbShadeR, p)
        o.sparkL = sample(dbHitL, p); o.sparkR = sample(dbHitR, p)
        o.sparkPos = V2(-94, -54)
        return o
    }

    // MARK: Horse-ride trot (4 beats: shades on, wrists crossed, trotting every beat, lasso overhead on 3–4)
    static let hrSway = [k1(0, -18), k1(0.5, 18), k1(1, -18)]
    static let hrLeg = [k2(0, 0, 0), k2(0.25, -6, -22), k2(0.5, 0, 0), k2(1, 0, 0)]   // one beat
    static let hrArmR = [k3(0, -142, -2, 1), k3(0.44, -142, -2, 1), k3(0.50, -159, -146, 0), k3(0.60, -125, -176, 0), k3(0.70, -159, -206, 0),
                         k3(0.80, -193, -176, 0), k3(0.90, -159, -146, 0), k3(0.96, -142, -2, 1), k3(1, -142, -2, 1)]

    static func horse(_ p: Double) -> Pose {
        var o = Pose()
        let x = sample(hrSway, p)
        let b = bump(cyc(p, 8))
        o.lift = V2(0, -18 * b)
        o.sway = V3(x, 0, 0)
        o.squash = V3(1.05 - 0.07 * b, 0.94 + 0.09 * b, 0)
        let beat = cyc(p, 4)
        let l = sample(hrLeg, beat), r = sample(hrLeg, Choreographer.fract(beat + 0.5))
        o.legLX = l.x; o.legL = l.y; o.legRX = -r.x; o.legR = r.y
        o.armL = V2(142, 14); o.armShadeL = 1                 // left wrist parked across the belly
        let a = sample(hrArmR, p)
        o.armR = V2(a.x, a.y); o.armShadeR = a.z
        o.shades = 1
        let c8 = cyc(p, 8)
        o.puff = V2(0.8 * max(0, 1 - c8 / 0.8), c8 / 0.8)
        o.shadowX = x
        o.shadow = V2(1.02 - 0.08 * b, 1 - 0.2 * b)
        return o
    }

    // MARK: Bunny-ears sway (2 beats: hands on the head flapping, hips swaying)
    static let eSway = [k3(0, -24, 0, -7), k3(0.5, 24, 0, 7), k3(1, -24, 0, -7)]
    static let eLeg = [k1(0, 0), k1(0.25, -16), k1(0.5, 0), k1(1, 0)]

    static func ears(_ p: Double) -> Pose {
        var o = Pose()
        let sw = sample(eSway, p)
        o.sway = sw
        let b = bump(cyc(p, 2))
        o.lift = V2(0, -18 * b)
        o.squash = V3(1.05 - 0.07 * b, 0.95 + 0.08 * b, 0)
        o.legL = sample(eLeg, p); o.legR = sample(eLeg, Choreographer.fract(p + 0.5))
        let f = bump(cyc(p, 4))
        o.armL = V2(60, -136 - 10 * f); o.armRotL = -16 + 24 * f
        o.armR = V2(-60, -136 - 10 * f); o.armRotR = 16 - 24 * f
        o.happy = 1
        o.shadowX = sw.x
        return o
    }

    // MARK: Vibe nod (4 beats: eyes closed, nodding every beat, a foot tapping, notes floating up)
    static let vNod = [k3(0, 0, 1, 1), k3(0.30, 16, 1.05, 0.9), k3(0.62, -4, 0.99, 1.02), k3(1, 0, 1, 1)]   // one beat: dy, sx, sy
    static let vArm = [k1(0, 0), k1(0.4, 14), k1(1, 0)]
    static let vTap = [k1(0, 0), k1(0.3, -14), k1(0.6, 0), k1(1, 0)]

    static func vibe(_ p: Double) -> Pose {
        var o = Pose()
        let beat = cyc(p, 4)
        let n = sample(vNod, beat)
        o.sway = V3(0, n.x, -4 + 8 * bump(cyc(p, 2)))
        o.squash = V3(n.y, n.z, 0)
        o.legL = -n.x                                     // body nods, feet stay planted
        o.legR = -n.x + sample(vTap, beat)
        let arm = sample(vArm, beat)
        o.armL = V2(0, arm); o.armR = V2(0, arm)
        o.sleepy = 1
        o.notes = V2(1, p)
        return o
    }

    // MARK: Noodle flail (8 beats: jelly body, arms flailing out of sync, googly eyes, mouth flapping)
    static let nArmL = [k3(0, -20, -90, -20), k3(0.25, 10, 24, 15), k3(0.5, -44, -36, -35), k3(0.75, 0, -124, 10), k3(1, -20, -90, -20)]
    static let nArmR = [k3(0, 0, 20, 15), k3(0.25, 40, -110, 30), k3(0.5, -6, -50, -15), k3(0.75, 30, -10, 40), k3(1, 0, 20, 15)]
    static let nLeg = [k2(0, 0, 0), k2(0.25, -20, -18), k2(0.5, 0, 0), k2(1, 0, 0)]

    static func noodle(_ p: Double) -> Pose {
        var o = Pose()
        let beat = cyc(p, 8)
        let b = bump(beat)
        o.lift = V2(0, -22 * b)
        o.skew = -12 + 24 * b
        o.squash = V3(1.05 - 0.09 * b, 0.95 + 0.10 * b, 0)
        let l = sample(nLeg, beat), r = sample(nLeg, Choreographer.fract(beat + 0.5))
        o.legLX = l.x; o.legL = l.y; o.legRX = -r.x; o.legR = r.y
        // Odd cycle counts keep the limbs from ever lining up with the hop.
        let al = sample(nArmL, cyc(p, 5)), ar = sample(nArmR, cyc(p, 7))
        o.armL = V2(al.x, al.y); o.armRotL = al.z
        o.armR = V2(ar.x, ar.y); o.armRotR = ar.z
        o.googly = 1
        let el = bump(cyc(p, 11)), er = bump(cyc(p, 9))
        o.googlyL = V2(-6 + 12 * el, -8 + 16 * el)
        o.googlyR = V2(6 - 12 * er, 6 - 16 * er)
        o.mouth = V2(1, 0.6 + 0.6 * bump(cyc(p, 16)))
        return o
    }
}

/// Which costume and routine the troupe uses ("Choose your Cudie").
enum CutieStyle: String, CaseIterable, Identifiable {
    case regular, mexican

    var id: String { rawValue }
    var label: String {
        switch self {
        case .regular: "Regular"
        case .mexican: "Mexican"
        }
    }
}

/// Picks each agent's move from its status and the shared beat clock.
enum Choreographer {
    private static let regular: [Dance] = [.bounce, .shimmy, .floss, .disco, .prance, .dab,
                                           .twirl, .husky, .horse, .ears, .vibe, .noodle]
    /// Mexican troupe: every other move is the maracas or the zapateado stomp.
    private static let mexican: [Dance] = regular.enumerated().flatMap { i, d in
        [i % 2 == 0 ? Dance.maracas : .stomp, d]
    }

    static func pose(status: AgentStatus, seed: Int, beat: Double, energy: Double, style: CutieStyle = .regular) -> Pose {
        switch status {
        case .needsYou:
            return Dance.wave.pose(fract(beat / Dance.wave.beats)).amplified(1.1)
        case .idle:
            return Dance.snooze.pose(fract(beat / Dance.snooze.beats + Double(seed % 8) / 8))
        case .working:
            // Everyone changes move every two bars, each agent starting at a different
            // spot in the routine so the troupe never looks copy-pasted.
            let routine = style == .mexican ? mexican : regular
            let n = routine.count
            let section = floor(beat / 8)
            let local = beat - section * 8
            let i = Int(section) + seed
            let cur = routine[((i % n) + n) % n]
            let prev = routine[(((i - 1) % n) + n) % n]
            var pose = cur.pose(fract(local / cur.beats))
            if local < 0.5 {
                let from = prev.pose(fract((local + 8) / prev.beats))
                let u = local / 0.5
                pose = Pose.lerp(from, pose, u * u * (3 - 2 * u))
            }
            return pose.amplified(0.55 + 0.6 * energy)
        }
    }

    @inline(__always) static func fract(_ x: Double) -> Double { x - floor(x) }
}
