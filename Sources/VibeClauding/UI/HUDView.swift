import QuartzCore
import SwiftUI

struct HUDView: View {
    @Environment(AgentStore.self) private var store
    @Environment(AudioEngine.self) private var audio
    @Binding var floatOnTop: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("VIBE CLAUDING")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(
                        LinearGradient(colors: [Palette.cyan, Palette.magenta, Palette.clay],
                                       startPoint: .leading, endPoint: .trailing))
                HStack(spacing: 10) {
                    Counter(value: store.agents.count, label: store.agents.count == 1 ? "agent" : "agents", color: .white)
                    Counter(value: store.workingCount, label: "working", color: Palette.working)
                    Counter(value: store.needsYouCount, label: "need you", color: Palette.needsYou)
                    Counter(value: store.idleCount, label: "idle", color: Palette.idle)
                }
            }

            Spacer(minLength: 12)

            BeatMeter(analyzer: audio.analyzer)

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Picker("Audio", selection: Binding(get: { audio.source }, set: { audio.setSource($0) })) {
                    ForEach(AudioSource.allCases) { s in
                        Label(s.label, systemImage: s.symbol).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 250)

                Button {
                    floatOnTop.toggle()
                } label: {
                    Image(systemName: floatOnTop ? "pin.fill" : "pin")
                        .frame(width: 22, height: 18)
                }
                .buttonStyle(.bordered)
                .help(floatOnTop ? "Stop floating above other windows" : "Float above other windows")
                .accessibilityLabel(floatOnTop ? "Unpin window" : "Pin window on top")
            }
        }
        .padding(.leading, 78) // clear the traffic lights
        .padding(.trailing, 18)
        .padding(.top, 10)
    }
}

private struct Counter: View {
    let value: Int
    let label: String
    let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
        }
        .opacity(value == 0 && label != "agents" && label != "agent" ? 0.45 : 1)
    }
}

/// Live BPM readout with four beat lamps and a LIVE / SILENT chip.
struct BeatMeter: View {
    @Environment(WindowVisibility.self) private var visibility
    let analyzer: BeatAnalyzer

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !visibility.isVisible)) { _ in
            let now = CACurrentMediaTime()
            let snap = analyzer.snapshot()
            let beat = snap.beat(at: now)
            let step = Int(floor(beat)) % 4
            let within = beat - floor(beat)
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(snap.isActive ? "\(Int(snap.bpm.rounded()))" : "--")
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("BPM")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                HStack(spacing: 5) {
                    ForEach(0..<4, id: \.self) { i in
                        let on = i == ((step % 4) + 4) % 4
                        RoundedRectangle(cornerRadius: 2)
                            .fill(on ? (i == 0 ? Palette.magenta : Palette.cyan) : Color.white.opacity(0.12))
                            .frame(width: 12, height: 12)
                            .shadow(color: on ? Palette.cyan.opacity(1 - within) : .clear, radius: 6)
                            .opacity(on ? 0.55 + 0.45 * (1 - within) : 1)
                    }
                }
                Text(snap.isActive ? "LIVE" : "SILENT")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(snap.isActive ? Color.black : .white.opacity(0.6))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(snap.isActive ? Palette.working : Color.white.opacity(0.1)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.04)).overlay(Capsule().strokeBorder(.white.opacity(0.08))))
        }
    }
}

/// Bottom hint when we can't hear anything for a while.
struct SilenceHint: View {
    @Environment(AudioEngine.self) private var audio
    @State private var tracker = SilenceTracker()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let silentFor = tracker.silentDuration(active: audio.analyzer.snapshot().isActive, source: audio.source)
            Group {
                if let err = audio.errorText {
                    hint(err, button: audio.source == .microphone ? "Open Settings" : nil)
                } else if audio.source != .off && silentFor > 8 {
                    hint(audio.source == .system
                         ? "Hearing silence. Play some music, or allow Vibe Clauding under Screen & System Audio Recording."
                         : "Hearing silence. Turn it up, or allow microphone access.",
                         button: "Open Settings")
                }
            }
        }
    }

    private func hint(_ text: String, button: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.badge.exclamationmark")
                .foregroundStyle(Palette.needsYou)
            Text(text)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
            if let button {
                Button(button) { audio.openPrivacySettings() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.8)).overlay(Capsule().strokeBorder(.white.opacity(0.1))))
    }
}

/// How long we've heard nothing since the source started. Once anything has played,
/// silence just means the music is paused, so the hint stays away.
final class SilenceTracker {
    private var startedAt = CACurrentMediaTime()
    private var lastSource: AudioSource?
    private var everHeard = false

    func silentDuration(active: Bool, source: AudioSource) -> Double {
        let now = CACurrentMediaTime()
        if source != lastSource { lastSource = source; startedAt = now; everHeard = false }
        if active { everHeard = true }
        return everHeard ? 0 : now - startedAt
    }
}
