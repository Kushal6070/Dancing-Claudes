import AVFoundation
import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import Observation

enum AudioSource: String, CaseIterable, Identifiable {
    case system, microphone, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "Mac audio"
        case .microphone: "Mic"
        case .off: "Off"
        }
    }
    var symbol: String {
        switch self {
        case .system: "hifispeaker.fill"
        case .microphone: "mic.fill"
        case .off: "speaker.slash.fill"
        }
    }
}

/// Owns the capture source and feeds the shared `BeatAnalyzer`.
@Observable
final class AudioEngine {
    private(set) var source: AudioSource
    private(set) var statusText = ""
    private(set) var errorText: String?

    @ObservationIgnored let analyzer = BeatAnalyzer()
    @ObservationIgnored private var tap: SystemAudioTap?
    @ObservationIgnored private var mic: MicCapture?

    init() {
        let saved = UserDefaults.standard.string(forKey: "audioSource").flatMap(AudioSource.init(rawValue:))
        source = saved ?? .system
        DispatchQueue.main.async { self.restart() }
    }

    func setSource(_ s: AudioSource) {
        guard s != source else { return }
        source = s
        UserDefaults.standard.set(s.rawValue, forKey: "audioSource")
        restart()
    }

    func restart() {
        tap?.stop(); tap = nil
        mic?.stop(); mic = nil
        analyzer.markSilent()
        errorText = nil

        switch source {
        case .off:
            statusText = "Audio off. Agents groove to their own beat."
        case .system:
            analyzer.silenceThreshold = 0.0004
            let t = SystemAudioTap()
            let mixer = MonoMixer()
            let analyzer = self.analyzer
            t.onBuffer = { abl, sr in
                mixer.mix(abl) { ptr, n in analyzer.feed(ptr, count: n, sampleRate: sr) }
            }
            t.onDeviceChange = { [weak self] in
                DispatchQueue.main.async { if self?.source == .system { self?.restart() } }
            }
            do {
                try t.start()
                tap = t
                statusText = "Listening to everything your Mac plays"
            } catch {
                errorText = "Couldn't tap Mac audio (\(error.localizedDescription)). Try the Mic source."
                statusText = ""
            }
        case .microphone:
            analyzer.silenceThreshold = 0.004
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    guard self.source == .microphone else { return }
                    guard granted else {
                        self.errorText = "Microphone access was denied. Enable it in System Settings › Privacy."
                        return
                    }
                    let m = MicCapture()
                    let analyzer = self.analyzer
                    m.onSamples = { ptr, n, sr in analyzer.feed(ptr, count: n, sampleRate: sr) }
                    do {
                        try m.start()
                        self.mic = m
                        self.statusText = "Listening through the microphone"
                    } catch {
                        self.errorText = "Couldn't start the microphone (\(error.localizedDescription))."
                    }
                }
            }
        }
    }

    func openPrivacySettings() {
        // System-audio-only capture lives under "Screen & System Audio Recording".
        let pane = source == .microphone ? "Privacy_Microphone" : "Privacy_ScreenCapture"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Down-mixing

/// Mixes an AudioBufferList (interleaved or not) to mono float.
final class MonoMixer {
    private var buffer = [Float](repeating: 0, count: 4096)

    func mix(_ abl: UnsafeMutableAudioBufferListPointer, _ body: (UnsafePointer<Float>, Int) -> Void) {
        guard abl.count > 0, let first = abl.first, first.mData != nil else { return }
        let ch0 = max(1, Int(first.mNumberChannels))
        let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * ch0)
        guard frames > 0 else { return }
        if buffer.count < frames { buffer = [Float](repeating: 0, count: frames) }

        buffer.withUnsafeMutableBufferPointer { out in
            for i in 0..<frames { out[i] = 0 }
            var totalChannels = 0
            for buf in abl {
                guard let data = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let ch = max(1, Int(buf.mNumberChannels))
                let n = min(frames, Int(buf.mDataByteSize) / (MemoryLayout<Float>.size * ch))
                for c in 0..<ch {
                    var idx = c
                    for i in 0..<n { out[i] += data[idx]; idx += ch }
                }
                totalChannels += ch
            }
            let g = 1 / Float(max(totalChannels, 1))
            for i in 0..<frames { out[i] *= g }
            body(UnsafePointer(out.baseAddress!), frames)
        }
    }
}

// MARK: - System audio (Core Audio process tap, macOS 14.2+)

struct CoreAudioError: LocalizedError {
    let what: String
    let status: OSStatus
    var errorDescription: String? { "\(what) failed (\(status))" }
}

private func check(_ status: OSStatus, _ what: String) throws {
    if status != noErr { throw CoreAudioError(what: what, status: status) }
}

/// Captures the global system output mix without muting it, via a private
/// process tap wrapped in a private aggregate device.
final class SystemAudioTap {
    var onBuffer: ((UnsafeMutableAudioBufferListPointer, Double) -> Void)?
    var onDeviceChange: (() -> Void)?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var sampleRate: Double = 48_000
    private let queue = DispatchQueue(label: "vibe.systemtap", qos: .userInteractive)
    private var listener: AudioObjectPropertyListenerBlock?
    private var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    func start() throws {
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.name = "Dancing Claudes"
        desc.muteBehavior = .unmuted
        desc.isPrivate = true

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(desc, &tap), "Creating the audio tap")
        tapID = tap

        let outputUID = try Self.defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Dancing Claudes Tap",
            kAudioAggregateDeviceUIDKey: "vibe-clauding-\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: desc.uuid.uuidString,
            ]],
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &agg), "Creating the aggregate device")
        aggregateID = agg

        sampleRate = (try? readTapSampleRate()) ?? 48_000

        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            guard let self else { return }
            let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            self.onBuffer?(abl, self.sampleRate)
        }, "Creating the IO proc")
        try check(AudioDeviceStart(aggregateID, procID), "Starting capture")

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.onDeviceChange?() }
        listener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, queue, block)
    }

    func stop() {
        if let block = listener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, queue, block)
            listener = nil
        }
        if aggregateID != kAudioObjectUnknown {
            if let p = procID {
                AudioDeviceStop(aggregateID, p)
                AudioDeviceDestroyIOProcID(aggregateID, p)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit { stop() }

    private func readTapSampleRate() throws -> Double {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &asbd), "Reading tap format")
        return asbd.mSampleRate > 0 ? asbd.mSampleRate : 48_000
    }

    static func defaultOutputUID() throws -> String {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device),
                  "Finding the output device")
        addr.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &uid), "Reading the output device UID")
        guard let value = uid?.takeRetainedValue() else { throw CoreAudioError(what: "Reading the output device UID", status: -1) }
        return value as String
    }
}

// MARK: - Microphone

final class MicCapture {
    var onSamples: ((UnsafePointer<Float>, Int, Double) -> Void)?
    private let engine = AVAudioEngine()
    private var mono = [Float](repeating: 0, count: 8192)

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let sr = format.sampleRate
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let channels = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength), c = Int(buffer.format.channelCount)
            guard n > 0, c > 0 else { return }
            if self.mono.count < n { self.mono = [Float](repeating: 0, count: n) }
            self.mono.withUnsafeMutableBufferPointer { out in
                for i in 0..<n {
                    var s: Float = 0
                    for ch in 0..<c { s += channels[ch][i] }
                    out[i] = s / Float(c)
                }
                self.onSamples?(UnsafePointer(out.baseAddress!), n, sr)
            }
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
