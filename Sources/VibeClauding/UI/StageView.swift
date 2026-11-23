import QuartzCore
import SwiftUI

enum Stage {
    /// Floor horizon as a fraction of window height (shared with the shader).
    static let horizon = 0.56
}

enum Palette {
    static let working = Color(red: 0.36, green: 0.95, blue: 0.69)
    static let needsYou = Color(red: 1.0, green: 0.71, blue: 0.28)
    static let idle = Color(red: 0.62, green: 0.64, blue: 0.72)
    static let clay = CutieRenderer.body
    static let cyan = Color(red: 0.10, green: 0.90, blue: 1.0)
    static let magenta = Color(red: 1.0, green: 0.22, blue: 0.78)

    static func status(_ s: AgentStatus) -> Color {
        switch s {
        case .working: working
        case .needsYou: needsYou
        case .idle: idle
        }
    }
}

/// Per-frame values shared by every dancer.
struct Groove {
    var beat: Double
    var kick: Double
    var energy: Double
    var time: Double
    var live: Bool
}

/// Working and waiting agents dance up front; idle ones nap in the lounge at the back.
/// When an agent's status changes it hops over to its new spot.
///
/// Performance: every dancer is drawn into ONE Canvas inside the per-frame TimelineView.
/// Bubbles, name tags and hover targets live outside it and only update when the
/// agent list or layout changes, so SwiftUI isn't diffing dozens of views 60×/s.
struct StageView: View {
    @Environment(AgentStore.self) private var store
    @Environment(WindowVisibility.self) private var visibility
    @AppStorage("cutieStyle") private var cutieStyle: CutieStyle = .regular
    let analyzer: BeatAnalyzer
    @State private var hovered: String?
    @State private var smoothEnergy = SmoothValue()
    @State private var animator = SlotAnimator()

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let agents = store.agents
            let targets = StageLayout.targets(for: agents, size: size)
            ZStack(alignment: .topLeading) {
                if agents.isEmpty {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: !visibility.isVisible)) { _ in
                        EmptyStage(size: size, groove: currentGroove(), style: cutieStyle)
                    }
                } else {
                    // Speech bubbles sit behind the dancers so big jumps pass in front.
                    ForEach(agents) { agent in
                        if let slot = targets[agent.id], !slot.lounge {
                            SpeechBubble(text: bubbleText(agent), tint: Palette.status(agent.status),
                                         emphasized: agent.status == .needsYou)
                                .frame(maxWidth: min(slot.spacing * 0.92, 280))
                                .fixedSize(horizontal: false, vertical: true)
                                .position(x: slot.x, y: slot.feetY - (240 + headroom) * slot.mascotWidth / 384 - 14)
                                .allowsHitTesting(false)
                        }
                    }

                    TimelineView(.animation(minimumInterval: 1 / 60, paused: !visibility.isVisible)) { _ in
                        let groove = currentGroove()
                        let slots = animator.step(targets, now: groove.time)
                        let hoveredID = hovered
                        let style = cutieStyle
                        Canvas { ctx, _ in
                            let ordered = agents.compactMap { a in slots[a.id].map { (a, $0) } }
                                .sorted { ($0.1.row, $0.1.x) < ($1.1.row, $1.1.x) }
                            for (agent, slot) in ordered {
                                DancerPainter.paint(ctx, agent: agent, slot: slot, groove: groove,
                                                    hovered: hoveredID == agent.id, style: style)
                            }
                        }
                        .allowsHitTesting(false)
                    }

                    ForEach(agents) { agent in
                        if let slot = targets[agent.id] {
                            AgentHotspot(agent: agent, slot: slot, hovered: hovered == agent.id, headroom: headroom,
                                         onHover: { inside in hovered = inside ? agent.id : (hovered == agent.id ? nil : hovered) },
                                         onTap: { store.open(agent) })
                        }
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .animation(.smooth(duration: 0.9), value: targets.mapValues { SlotKey($0) })
        }
    }

    /// Room above the body (local units) that speech bubbles clear; sombreros need more.
    private var headroom: Double { cutieStyle == .mexican ? 190 : 130 }

    private func bubbleText(_ agent: Agent) -> String {
        switch agent.status {
        case .working: return agent.activity ?? "Working"
        case .needsYou:
            if let a = agent.activity, a != "Thinking", a != "Writing a reply" { return "Needs you · \(a)" }
            return "Needs your input"
        case .idle: return agent.lastPrompt.map { "Last: \($0)" } ?? "Napping"
        }
    }

    private func currentGroove() -> Groove {
        let now = CACurrentMediaTime()
        let snap = analyzer.snapshot()
        let rawEnergy = snap.isActive ? Double(snap.bass * 0.55 + snap.mid * 0.3 + snap.level * 0.4) : 0.45
        let energy = smoothEnergy.update(min(1, rawEnergy), at: now)
        return Groove(beat: snap.beat(at: now),
                      kick: snap.isActive ? Double(snap.kick(at: now)) : 0,
                      energy: energy,
                      time: now,
                      live: snap.isActive)
    }
}

/// Tiny reference-type smoother so per-frame reads don't trigger SwiftUI updates.
final class SmoothValue {
    private var value = 0.45
    private var last = CACurrentMediaTime()
    func update(_ target: Double, at t: CFTimeInterval) -> Double {
        let dt = min(0.1, max(0, t - last)); last = t
        value += (target - value) * (1 - exp(-dt * 3))
        return value
    }
}

// MARK: - Layout

struct StageSlot: Equatable {
    var x: CGFloat
    var feetY: CGFloat
    var mascotWidth: CGFloat
    var spacing: CGFloat
    var row: Int            // draw order: 0 = lounge (back) … 2 = front
    var lounge: Bool
    var hop: CGFloat = 0    // extra lift while walking to a new spot
}

enum StageLayout {
    static func targets(for agents: [Agent], size: CGSize) -> [String: StageSlot] {
        var out: [String: StageSlot] = [:]
        let idle = agents.filter { $0.status == .idle }
        let active = agents.filter { $0.status != .idle }

        if !idle.isEmpty {
            let sp = size.width * 0.92 / CGFloat(idle.count)
            let w = min(92, sp * 0.5, size.height * 0.105)
            for (i, a) in idle.enumerated() {
                let x = size.width / 2 + (CGFloat(i) - CGFloat(idle.count - 1) / 2) * sp
                out[a.id] = StageSlot(x: x, feetY: size.height * 0.585, mascotWidth: w, spacing: sp, row: 0, lounge: true)
            }
        }

        if !active.isEmpty {
            let maxPerRow = max(1, Int(size.width / 190))
            let rows = active.count <= maxPerRow ? 1 : 2
            let perRow = Int(ceil(Double(active.count) / Double(rows)))
            for (i, a) in active.enumerated() {
                let r = i / perRow                       // 0 = front
                let countInRow = min(perRow, active.count - r * perRow)
                let idx = i % perRow
                let feet: CGFloat = rows == 1 ? 0.875 : (r == 0 ? 0.9 : 0.77)
                let scale: CGFloat = r == 0 ? 1 : 0.8
                let sp = size.width * 0.9 / CGFloat(countInRow)
                let w = min(155, sp * 0.56, size.height * 0.19) * scale
                let stagger: CGFloat = r == 1 && countInRow == perRow && rows == 2 && active.count % 2 == 0 ? sp * 0.5 : 0
                let x = size.width / 2 + (CGFloat(idx) - CGFloat(countInRow - 1) / 2) * sp + stagger * 0.5
                out[a.id] = StageSlot(x: x, feetY: size.height * feet, mascotWidth: w, spacing: sp,
                                      row: r == 0 ? 2 : 1, lounge: false)
            }
        }
        return out
    }
}

/// Eases every cutie toward its target spot, with a little hop while it travels.
/// New agents drop in from above.
final class SlotAnimator {
    private var current: [String: StageSlot] = [:]
    private var last = CACurrentMediaTime()

    func step(_ targets: [String: StageSlot], now: CFTimeInterval) -> [String: StageSlot] {
        let dt = min(0.05, max(0, now - last)); last = now
        let k = CGFloat(1 - exp(-dt * 3.2))
        var out: [String: StageSlot] = [:]
        for (id, target) in targets {
            var cur = current[id] ?? {
                var s = target
                s.feetY -= 260
                return s
            }()
            let dx = target.x - cur.x, dy = target.feetY - cur.feetY
            cur.x += dx * k
            cur.feetY += dy * k
            cur.mascotWidth += (target.mascotWidth - cur.mascotWidth) * k
            cur.spacing = target.spacing
            cur.row = target.row
            cur.lounge = target.lounge
            let dist = hypot(dx, dy)
            let walking = dist > 2 && abs(dy) < 200
            cur.hop = walking ? -abs(sin(now * 13)) * min(14, dist * 0.25) : 0
            current[id] = cur
            out[id] = cur
        }
        current = current.filter { targets[$0.key] != nil }
        return out
    }
}

// MARK: - One dancer

/// Equatable slice of a slot used to drive label animations.
struct SlotKey: Equatable {
    let x: CGFloat, y: CGFloat, w: CGFloat
    init(_ s: StageSlot) { x = s.x; y = s.feetY; w = s.mascotWidth }
}

enum DancerPainter {
    static func paint(_ ctx: GraphicsContext, agent: Agent, slot: StageSlot, groove: Groove, hovered: Bool, style: CutieStyle) {
        let sombrero = style == .mexican
        // Helpers (subagents) dance at the feet, behind their parent.
        for (i, sub) in agent.subagents.prefix(4).enumerated() {
            let mini = slot.mascotWidth * 0.34
            let side: CGFloat = i % 2 == 0 ? 1 : -1
            let dx = side * (slot.mascotWidth * 0.66 + CGFloat(i / 2) * mini * 0.95)
            let seed = agent.seed + 31 * (i + 1) + sub.id.count
            let pose = Choreographer.pose(status: .working, seed: seed, beat: groove.beat + 0.5, energy: groove.energy, style: style)
            let look = CutieRenderer.Look(status: .working, kick: groove.kick * 0.6, beat: groove.beat,
                                          time: groove.time, seed: seed, dim: 0.95, sombrero: sombrero)
            drawCutie(ctx, x: slot.x + dx, feetY: slot.feetY + slot.hop, width: mini, scale: 1, pose: pose, look: look)
        }

        let pose = Choreographer.pose(status: agent.status, seed: agent.seed, beat: groove.beat, energy: groove.energy, style: style)
        let look = CutieRenderer.Look(status: agent.status, kick: groove.kick, beat: groove.beat,
                                      time: groove.time, seed: agent.seed, dim: slot.lounge ? 0.78 : 1, sombrero: sombrero)
        drawCutie(ctx, x: slot.x, feetY: slot.feetY + slot.hop, width: slot.mascotWidth,
                  scale: hovered ? 1.07 : 1, pose: pose, look: look)
    }

    private static func drawCutie(_ ctx: GraphicsContext, x: CGFloat, feetY: CGFloat, width: CGFloat,
                                  scale: CGFloat, pose: Pose, look: CutieRenderer.Look) {
        let s = width / 384
        let w = CutieRenderer.localWidth * s, h = CutieRenderer.localHeight * s
        var c = ctx
        c.translateBy(x: x, y: feetY)
        c.scaleBy(x: scale, y: scale)
        c.translateBy(x: -w / 2, y: -CutieRenderer.feetY * s)
        CutieRenderer.draw(c, size: CGSize(width: w, height: h), pose: pose, look: look)
    }
}

/// Invisible hover/click target plus the name tag for one agent.
struct AgentHotspot: View {
    let agent: Agent
    let slot: StageSlot
    let hovered: Bool
    let headroom: Double
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    var body: some View {
        let s = slot.mascotWidth / 384
        let labelWidth = min(slot.spacing * 0.92, slot.lounge ? 170 : 280)
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: 420 * s, height: 330 * s)
                .position(x: slot.x, y: slot.feetY - 150 * s)
                .onHover(perform: onHover)
                .onTapGesture(perform: onTap)
                .help(tooltip)
                .accessibilityElement()
                .accessibilityLabel("\(agent.project), \(agent.status.label)")
                .accessibilityAddTraits(.isButton)

            if slot.lounge && hovered {
                SpeechBubble(text: agent.lastPrompt.map { "Last: \($0)" } ?? "Napping", tint: Palette.idle, emphasized: false)
                    .frame(maxWidth: 280)
                    .fixedSize(horizontal: false, vertical: true)
                    .position(x: slot.x, y: slot.feetY - (240 + headroom) * s - 14)
                    .allowsHitTesting(false)
            }

            NameTag(agent: agent, hovered: hovered, compact: slot.lounge)
                .frame(width: labelWidth)
                .position(x: slot.x, y: slot.feetY + (slot.lounge ? 16 : 36))
                .onTapGesture(perform: onTap)
        }
    }

    private var tooltip: String {
        var lines = ["\(agent.project) — \(agent.status.label)", agent.cwd]
        if let t = agent.title { lines.append("Task: \(t)") }
        if let p = agent.lastPrompt { lines.append("Last prompt: \(p)") }
        if !agent.subagents.isEmpty {
            lines.append("Helpers: " + agent.subagents.map(\.summary).joined(separator: ", "))
        }
        lines.append("Session \(agent.name) · up \(Elapsed.short(since: agent.startedAt)) · click to open")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Labels

struct SpeechBubble: View {
    let text: String
    let tint: Color
    let emphasized: Bool
    @State private var pulse = false

    var body: some View {
        let glow = emphasized && pulse ? 1.0 : 0.0
        Text(text)
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.black.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(tint.opacity(0.5 + 0.4 * glow), lineWidth: 1)
                    )
                    .shadow(color: tint.opacity(0.25 + 0.4 * glow), radius: 8)
            }
            .overlay(alignment: .bottom) {
                BubbleTail().fill(Color.black.opacity(0.8))
                    .overlay(BubbleTail().stroke(tint.opacity(0.5 + 0.4 * glow), lineWidth: 1))
                    .frame(width: 10, height: 6)
                    .offset(y: 5.5)
            }
            .task(id: emphasized) {
                pulse = false
                guard emphasized else { return }
                try? await Task.sleep(for: .milliseconds(30))
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

struct BubbleTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

struct NameTag: View {
    let agent: Agent
    let hovered: Bool
    var compact = false

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(Palette.status(agent.status)).frame(width: compact ? 5 : 7, height: compact ? 5 : 7)
                    .shadow(color: Palette.status(agent.status), radius: compact ? 2 : 4)
                Text(agent.project)
                    .font(.system(size: compact ? 10.5 : 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(compact ? 0.7 : 1))
                    .lineLimit(1)
                if compact {
                    Text(Elapsed.short(since: agent.statusSince))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                } else if !agent.subagents.isEmpty {
                    Text("+\(agent.subagents.count) helper\(agent.subagents.count == 1 ? "" : "s")")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.cyan.opacity(0.9))
                }
            }
            if !compact || hovered {
                Text(agent.title ?? agent.name)
                    .font(.system(size: compact ? 9.5 : 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(hovered ? 0.85 : 0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 4)
        .background(
            Capsule().fill(Color.black.opacity(hovered ? 0.8 : (compact ? 0.35 : 0.55)))
        )
    }
}

struct EmptyStage: View {
    let size: CGSize
    let groove: Groove
    let style: CutieStyle

    var body: some View {
        let w = min(150, size.height * 0.2)
        let s = w / 384
        let feetY = size.height * 0.8
        let pose = Choreographer.pose(status: .idle, seed: 3, beat: groove.beat, energy: groove.energy)
        let look = CutieRenderer.Look(status: .idle, kick: 0, beat: groove.beat, time: groove.time, seed: 3, dim: 0.7,
                                      sombrero: style == .mexican)
        ZStack(alignment: .topLeading) {
            Canvas { ctx, sz in CutieRenderer.draw(ctx, size: sz, pose: pose, look: look) }
                .frame(width: CutieRenderer.localWidth * s, height: CutieRenderer.localHeight * s)
                .position(x: size.width / 2, y: feetY - CutieRenderer.feetY * s + CutieRenderer.localHeight * s / 2)
            VStack(spacing: 6) {
                Text("No Claude Code agents running")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Start one with `claude` (or in your editor) and it joins the dance floor.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .position(x: size.width / 2, y: feetY + 46)
        }
    }
}

enum Elapsed {
    static func short(since date: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(date)))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86_400 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        return "\(s / 86_400)d"
    }
}
