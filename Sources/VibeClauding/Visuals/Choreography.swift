import Foundation

// Dance moves for the pixel cutie, ported from the "Logo bounce animation" design
// (Bounce + clap, Shimmy, Disco point, Twirl hop, Hands-up wave) and re-timed so
// the big hits land on beats. All coordinates are in the mascot's own 384×240
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
        return o
    }
}

enum Dance: CaseIterable {
    case bounce, shimmy, disco, twirl, wave, snooze

    /// How many beats one loop of the move takes.
    var beats: Double {
        switch self {
        case .bounce, .disco, .twirl: 4
        case .shimmy, .wave: 2
        case .snooze: 8
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
}

/// Picks each agent's move from its status and the shared beat clock.
enum Choreographer {
    private static let routine: [Dance] = [.bounce, .shimmy, .disco, .twirl]

    static func pose(status: AgentStatus, seed: Int, beat: Double, energy: Double) -> Pose {
        switch status {
        case .needsYou:
            return Dance.wave.pose(fract(beat / Dance.wave.beats)).amplified(1.1)
        case .idle:
            return Dance.snooze.pose(fract(beat / Dance.snooze.beats + Double(seed % 8) / 8))
        case .working:
            // Everyone changes move every two bars, each agent starting at a different
            // spot in the routine so the troupe never looks copy-pasted.
            let section = floor(beat / 8)
            let local = beat - section * 8
            let i = Int(section) + seed
            let cur = routine[((i % 4) + 4) % 4]
            let prev = routine[(((i - 1) % 4) + 4) % 4]
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
