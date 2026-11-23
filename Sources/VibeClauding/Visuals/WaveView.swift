import MetalKit
import QuartzCore
import SwiftUI

/// Full-window Metal background: twirling neon helix ribbons, beat rings,
/// a spectrum skyline and a scrolling grid floor, all driven by the analyzer.
struct WaveBackground: NSViewRepresentable {
    let analyzer: BeatAnalyzer
    /// Floor horizon as a fraction of the height from the top (shared with the stage layout).
    var horizon: Double = Stage.horizon
    var paused = false

    func makeCoordinator() -> WaveRenderer { WaveRenderer(analyzer: analyzer) }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.coordinator.horizon = Float(horizon)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.horizon = Float(horizon)
        if view.isPaused != paused { view.isPaused = paused }
    }
}

private struct WaveUniforms {
    var res: SIMD2<Float>
    var time: Float
    var bass: Float
    var mid: Float
    var treble: Float
    var kick: Float
    var level: Float
    var beat: Float
    var spin: Float
    var active: Float
    var horizon: Float
    var energy: Float
    var pad: Float = 0
}

final class WaveRenderer: NSObject, MTKViewDelegate {
    private let analyzer: BeatAnalyzer
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private let start = CACurrentMediaTime()
    private var last = CACurrentMediaTime()
    private var spin: Float = 0
    private var smooth = (bass: Float(0), mid: Float(0), treble: Float(0), level: Float(0), energy: Float(0), active: Float(0))
    private var spectrum = [Float](repeating: 0, count: AudioSnapshot.bandCount)
    var horizon: Float = 0.64

    init(analyzer: BeatAnalyzer) {
        self.analyzer = analyzer
    }

    func attach(to view: MTKView) {
        guard let device = view.device else { return }
        queue = device.makeCommandQueue()
        do {
            // Compiled at runtime from source, so no offline Metal toolchain is needed.
            let library = try device.makeLibrary(source: WaveShader.source, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "wave_vertex")
            desc.fragmentFunction = library.makeFunction(name: "wave_fragment")
            desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            NSLog("Dancing Claudes: shader failed to compile: \(error)")
        }
        view.delegate = self
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipeline, let queue,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }

        let now = CACurrentMediaTime()
        let dt = Float(min(0.05, now - last))
        last = now
        let snap = analyzer.snapshot()
        let k = 1 - exp(-dt * 12)
        let activeTarget: Float = snap.isActive ? 1 : 0
        smooth.bass += (snap.bass * activeTarget - smooth.bass) * k
        smooth.mid += (snap.mid * activeTarget - smooth.mid) * k
        smooth.treble += (snap.treble * activeTarget - smooth.treble) * k
        smooth.level += (snap.level * activeTarget - smooth.level) * k
        smooth.active += (activeTarget - smooth.active) * (1 - exp(-dt * 2))
        let energyTarget = (smooth.bass * 0.5 + smooth.mid * 0.3 + smooth.treble * 0.2)
        smooth.energy += (energyTarget - smooth.energy) * (1 - exp(-dt * 4))
        for i in 0..<spectrum.count {
            spectrum[i] += (snap.spectrum[i] * activeTarget - spectrum[i]) * k
        }
        let kick = snap.kick(at: now) * activeTarget
        // The twirl speeds up with energy and gets a shove on every kick.
        spin += dt * (0.35 + 1.4 * smooth.energy + 3.2 * kick)

        var u = WaveUniforms(
            res: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            time: Float(now - start),
            bass: smooth.bass, mid: smooth.mid, treble: smooth.treble,
            kick: kick, level: smooth.level,
            beat: Float(snap.beat(at: now).truncatingRemainder(dividingBy: 4096)),
            spin: spin, active: smooth.active, horizon: horizon, energy: smooth.energy)

        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<WaveUniforms>.stride, index: 0)
        spectrum.withUnsafeBytes { raw in
            enc.setFragmentBytes(raw.baseAddress!, length: raw.count, index: 1)
        }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}

enum WaveShader {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct VOut { float4 pos [[position]]; float2 uv; };

    vertex VOut wave_vertex(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        VOut o;
        o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0);
        o.uv = float2(p.x, 1.0 - p.y);
        return o;
    }

    struct U {
        float2 res;
        float time; float bass; float mid; float treble; float kick; float level;
        float beat; float spin; float active; float horizon; float energy; float pad;
    };

    static float3 neon(float t) {
        float3 a = float3(0.10, 0.90, 1.00);   // electric cyan
        float3 b = float3(0.45, 0.30, 1.00);   // ultraviolet
        float3 c = float3(1.00, 0.22, 0.78);   // hot magenta
        float3 d = float3(1.00, 0.50, 0.32);   // clay orange (the cuties' color)
        t = fract(t) * 4.0;
        if (t < 1.0) return mix(a, b, t);
        if (t < 2.0) return mix(b, c, t - 1.0);
        if (t < 3.0) return mix(c, d, t - 2.0);
        return mix(d, a, t - 3.0);
    }

    static float spec(constant float* s, float x) {
        float f = clamp(x, 0.0, 1.0) * 63.0;
        int i = int(f);
        int j = min(i + 1, 63);
        return mix(s[i], s[j], f - float(i));
    }

    static float2 rot(float2 p, float a) {
        float c = cos(a), s = sin(a);
        return float2(c * p.x - s * p.y, s * p.x + c * p.y);
    }

    // Thin luminous line: hard core plus a soft halo.
    static float glowLine(float d, float w, float halo) {
        float core = w / (d + w);
        return core * core * core + halo * core;
    }

    // The whole light show, evaluated at p (also used for the floor reflection).
    static float3 waves(float2 p, constant U& u, constant float* sp, float halfW, float hz) {
        float t = u.time;
        float e = u.energy;
        float pulse = u.kick;
        float3 col = float3(0.0);

        float2 c = float2(0.0, hz + 0.27);
        float2 hp = rot(p - c, sin(t * 0.09) * 0.10);
        float x = hp.x;
        float env = smoothstep(halfW + 0.02, halfW * 0.04, abs(x));
        if (env <= 0.0) return col;
        // Blurred spectrum lookup so the ribbon swells smoothly instead of jittering.
        float sx = clamp(abs(x) / halfW, 0.0, 1.0) * 0.8;
        float s = 0.0;
        for (int j = -3; j <= 3; j++) s += spec(sp, sx + float(j) * 0.03);
        s /= 7.0;
        float gain = 0.45 + 0.55 * u.level + 0.45 * pulse;

        // Spine: a slow travelling wave the ribbon rides on.
        float spine = (0.025 + 0.05 * u.bass + 0.04 * s + 0.025 * pulse)
                    * sin(x * 2.1 - t * 1.05 - u.spin * 0.45) * env;

        // 1) Twisting ribbon made of parallel light filaments.
        float tw = x * (2.8 + 0.9 * sin(t * 0.17)) - u.spin;
        float ct = cos(tw), st = sin(tw);
        float width = (0.05 + 0.065 * u.bass + 0.055 * s + 0.03 * pulse) * env;
        const int N = 22;
        for (int i = 0; i < N; i++) {
            float v = float(i) / float(N - 1) - 0.5;
            float y = spine + v * width * 2.0 * ct;
            float depth = v * st + 0.5;                      // 0 = far side, 1 = near side
            float d = abs(hp.y - y);
            float edge = 1.0 + 1.6 * step(0.49, abs(v));     // brighter silhouette lines
            float w = 0.0009 + 0.0013 * depth;
            float br = (0.12 + 0.88 * depth) * edge;
            col += neon(0.52 + v * 0.55 + t * 0.03 + x * 0.07) * glowLine(d, w, 0.018) * br * env * gain;
        }

        // 2) Helix strands orbiting the ribbon, carrying pulses of light ("data").
        float R = width * 1.5 + 0.025;
        const int H = 6;
        for (int i = 0; i < H; i++) {
            float fi = float(i) / float(H);
            float ang = x * 4.4 - t * 1.6 - u.spin * 1.3 + fi * 6.2831853;
            float y = spine + R * sin(ang);
            float depth = 0.5 + 0.5 * cos(ang);
            float d = abs(hp.y - y);
            float3 hc = neon(fi * 0.5 + 0.05 + t * 0.04);
            col += hc * glowLine(d, 0.0010 + 0.0012 * depth, 0.03) * (0.10 + 0.9 * depth) * env * gain;
            float run = fract(x * 3.0 - t * (0.9 + 1.6 * e) + fi * 0.37);
            float packet = smoothstep(0.90, 1.0, run) * smoothstep(1.0, 0.985, run);
            col += mix(hc, float3(1.0), 0.6) * packet * exp(-d * 260.0) * depth * env * (0.8 + 1.5 * pulse);
        }

        // 3) Outer echo: two faint wide sine traces that breathe with the mids.
        for (int i = 0; i < 2; i++) {
            float fi = float(i);
            float y = spine * 0.4 + (0.11 + 0.04 * u.mid + 0.02 * fi) * sin(x * (1.6 + fi * 0.7) + t * (0.6 - fi * 1.1) + u.spin * 0.3);
            col += neon(0.3 + fi * 0.4 + t * 0.02) * glowLine(abs(hp.y - y), 0.0008, 0.02) * 0.35 * env * (0.4 + 0.6 * u.mid);
        }

        // 4) A shockwave ring from behind the dancers on every beat.
        float r = length(p - c);
        float bf = fract(u.beat);
        float rr = bf * 0.9;
        float ring = exp(-abs(r - rr) * 90.0) * pow(1.0 - bf, 2.0);
        col += neon(0.05 + t * 0.05) * ring * (0.05 + 0.35 * e + 0.45 * pulse) * u.active;

        // Core glow at the twist center.
        col += neon(t * 0.05) * exp(-length(hp * float2(0.6, 2.2)) * 9.0) * (0.04 + 0.35 * pulse) * u.active;
        return col;
    }

    fragment float4 wave_fragment(VOut in [[stage_in]],
                                  constant U& u [[buffer(0)]],
                                  constant float* sp [[buffer(1)]]) {
        float2 frag = in.uv * u.res;
        float2 p = (frag - 0.5 * u.res) / u.res.y;
        p.y = -p.y;
        float aspect = u.res.x / u.res.y;
        float halfW = aspect * 0.5;
        float hz = 0.5 - u.horizon;

        float3 col = float3(0.0);   // pure black stage
        if (p.y >= hz) {
            col = waves(p, u, sp, halfW, hz);
        } else {
            // Glossy black floor: a rippled, fading mirror of the waves.
            float dy = hz - p.y;
            float2 m = float2(p.x + 0.003 * sin(p.y * 140.0 + u.time * 3.0), hz + dy);
            col = waves(m, u, sp, halfW, hz) * 0.30 * exp(-dy * 3.5);
        }
        // Hairline horizon.
        float3 hcol = neon(0.1 + u.time * 0.03);
        col += hcol * exp(-abs(p.y - hz) * 600.0) * (0.12 + 0.35 * u.energy + 0.3 * u.kick)
             * smoothstep(halfW, 0.0, abs(p.x));

        col = 1.0 - exp(-col * 1.4);
        return float4(col, 1.0);
    }
    """
}
