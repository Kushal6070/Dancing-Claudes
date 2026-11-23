import Accelerate
import Foundation
import QuartzCore

/// Everything the visuals need from the audio, copied out under a lock.
struct AudioSnapshot {
    static let bandCount = 64

    var spectrum = [Float](repeating: 0, count: AudioSnapshot.bandCount)
    var bass: Float = 0
    var mid: Float = 0
    var treble: Float = 0
    var level: Float = 0
    var bpm: Double = 110
    var phase: Double = 0                     // beats elapsed (continuous)
    var phaseTime: CFTimeInterval = CACurrentMediaTime()
    var lastKickTime: CFTimeInterval = -100
    var kickStrength: Float = 0
    var isActive = false                      // music detected right now
    var confidence: Float = 0

    /// Beat clock extrapolated to `t` so 120 Hz rendering stays smooth between audio hops.
    func beat(at t: CFTimeInterval) -> Double { phase + (t - phaseTime) * bpm / 60 }

    /// Decaying pulse after each detected kick/onset.
    func kick(at t: CFTimeInterval) -> Float {
        let dt = max(0, t - lastKickTime)
        return kickStrength * Float(exp(-dt * 6.5))
    }
}

/// FFT spectrum + spectral-flux onset detection + autocorrelation tempo + a beat PLL.
final class BeatAnalyzer {
    private let fftSize = 2048
    private let log2n: vDSP_Length = 11
    private let hop = 512
    private let fftSetup: FFTSetup

    private let window: UnsafeMutablePointer<Float>
    private let ring: UnsafeMutablePointer<Float>
    private let frame: UnsafeMutablePointer<Float>
    private let real: UnsafeMutablePointer<Float>
    private let imag: UnsafeMutablePointer<Float>
    private let mags: UnsafeMutablePointer<Float>
    private let logMags: UnsafeMutablePointer<Float>
    private let prevLog: UnsafeMutablePointer<Float>

    private var ringPos = 0
    private var pending = 0
    private var sampleRate: Double = 0
    private var bandBins: [(lo: Int, hi: Int, weight: Float, fc: Float)] = []
    private var smoothBands = [Float](repeating: 0, count: AudioSnapshot.bandCount)
    private var agcPeak: Float = 1e-4
    private var bassPeak: Float = 1e-4, midPeak: Float = 1e-4, treblePeak: Float = 1e-4
    private var bass: Float = 0, mid: Float = 0, treble: Float = 0, level: Float = 0

    // Onsets & tempo
    private var fluxHistory: [Float] = []
    private var envelope: [Float] = []
    private var f1: Float = 0, f2: Float = 0
    private var framesSinceOnset = 1000
    private var framesSinceTempo = 0
    private var bpm: Double = 110
    private var pendingBpm: Double = 0
    private var pendingCount = 0
    private var confidence: Float = 0
    private var phase: Double = 0
    private var activeFrames = 0
    private var silentFrames = 10_000
    private var lastKickTime: CFTimeInterval = -100
    private var kickStrength: Float = 0

    /// Below this RMS we treat the input as silence. Mic input needs a higher floor.
    var silenceThreshold: Float = 0.0006

    private let feedLock = NSLock()
    private let stateLock = NSLock()
    private var state = AudioSnapshot()

    init() {
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        func alloc(_ n: Int) -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: n)
            p.initialize(repeating: 0, count: n)
            return p
        }
        window = alloc(fftSize); ring = alloc(fftSize); frame = alloc(fftSize)
        real = alloc(fftSize / 2); imag = alloc(fftSize / 2)
        mags = alloc(fftSize / 2); logMags = alloc(fftSize / 2); prevLog = alloc(fftSize / 2)
        vDSP_hann_window(window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
        for p in [window, ring, frame, real, imag, mags, logMags, prevLog] { p.deallocate() }
    }

    func snapshot() -> AudioSnapshot {
        stateLock.lock(); defer { stateLock.unlock() }
        return state
    }

    /// Called when the audio source stops so visuals relax instead of freezing mid-pulse.
    func markSilent() {
        stateLock.lock()
        let now = CACurrentMediaTime()
        state.phase = state.beat(at: now)
        state.phaseTime = now
        state.isActive = false
        state.level = 0; state.bass = 0; state.mid = 0; state.treble = 0
        state.spectrum = [Float](repeating: 0, count: AudioSnapshot.bandCount)
        stateLock.unlock()
        feedLock.lock()
        phase = state.phase
        silentFrames = 10_000
        activeFrames = 0
        feedLock.unlock()
    }

    // MARK: Feeding

    /// Mono samples in, any thread (but one at a time).
    func feed(_ samples: UnsafePointer<Float>, count: Int, sampleRate sr: Double) {
        feedLock.lock(); defer { feedLock.unlock() }
        if sr != sampleRate { configure(sampleRate: sr) }
        var i = 0
        while i < count {
            let n = min(count - i, fftSize - ringPos, hop - pending)
            (ring + ringPos).update(from: samples + i, count: n)
            ringPos = (ringPos + n) % fftSize
            pending += n
            i += n
            if pending >= hop {
                pending = 0
                analyzeFrame()
            }
        }
    }

    private func configure(sampleRate sr: Double) {
        sampleRate = sr
        let nyquist = sr / 2
        let binHz = sr / Double(fftSize)
        let lo = 30.0, hi = min(16_000.0, nyquist * 0.95)
        bandBins = (0..<AudioSnapshot.bandCount).map { b in
            let f0 = lo * pow(hi / lo, Double(b) / Double(AudioSnapshot.bandCount))
            let f1 = lo * pow(hi / lo, Double(b + 1) / Double(AudioSnapshot.bandCount))
            let i0 = max(1, Int(f0 / binHz))
            let i1 = max(i0 + 1, Int(f1 / binHz))
            let fc = Float(sqrt(f0 * f1))
            // +3 dB/octave tilt so treble isn't invisible next to the kick drum.
            return (i0, min(i1, fftSize / 2), sqrt(fc / 60), fc)
        }
    }

    // MARK: Analysis (one hop)

    private func analyzeFrame() {
        let n = fftSize, half = fftSize / 2
        let tail = n - ringPos
        frame.update(from: ring + ringPos, count: tail)
        (frame + tail).update(from: ring, count: ringPos)

        var rms: Float = 0
        vDSP_rmsqv(frame, 1, &rms, vDSP_Length(n))
        vDSP_vmul(frame, 1, window, 1, frame, 1, vDSP_Length(n))

        var split = DSPSplitComplex(realp: real, imagp: imag)
        frame.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
            vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
        }
        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        vDSP_zvabs(&split, 1, mags, 1, vDSP_Length(half))
        var scale = 1 / Float(n)
        vDSP_vsmul(mags, 1, &scale, mags, 1, vDSP_Length(half))
        mags[0] = 0

        // --- bands with AGC
        var raw = [Float](repeating: 0, count: AudioSnapshot.bandCount)
        var peak: Float = 0
        for (b, r) in bandBins.enumerated() {
            var sum: Float = 0
            vDSP_meanv(mags + r.lo, 1, &sum, vDSP_Length(r.hi - r.lo))
            raw[b] = sum * r.weight
            peak = max(peak, raw[b])
        }
        agcPeak = max(peak, agcPeak * 0.9975, 2e-5)

        var bassRaw: Float = 0, midRaw: Float = 0, trebleRaw: Float = 0
        var bc = 0, mc = 0, tc = 0
        for b in 0..<AudioSnapshot.bandCount {
            let v = min(1, sqrt(raw[b] / agcPeak))
            let s = smoothBands[b]
            smoothBands[b] = v > s ? s + (v - s) * 0.55 : s + (v - s) * 0.12
            let fc = bandBins[b].fc
            if fc < 160 { bassRaw += raw[b]; bc += 1 } else if fc < 2200 { midRaw += raw[b]; mc += 1 } else { trebleRaw += raw[b]; tc += 1 }
        }
        bassRaw /= Float(max(bc, 1)); midRaw /= Float(max(mc, 1)); trebleRaw /= Float(max(tc, 1))
        bassPeak = max(bassRaw, bassPeak * 0.997, 1e-5)
        midPeak = max(midRaw, midPeak * 0.997, 1e-5)
        treblePeak = max(trebleRaw, treblePeak * 0.997, 1e-5)
        func follow(_ cur: Float, _ target: Float) -> Float { target > cur ? cur + (target - cur) * 0.6 : cur + (target - cur) * 0.15 }
        bass = follow(bass, min(1, bassRaw / bassPeak))
        mid = follow(mid, min(1, midRaw / midPeak))
        treble = follow(treble, min(1, trebleRaw / treblePeak))
        level = follow(level, min(1, rms * 6))

        // --- activity / silence
        let loud = rms > silenceThreshold
        if loud { activeFrames += 1; silentFrames = 0 } else { silentFrames += 1; if silentFrames > 40 { activeFrames = 0 } }
        let fps = sampleRate / Double(hop)
        let active = activeFrames > Int(fps * 0.3) && silentFrames < Int(fps * 1.5)

        // --- spectral flux (log magnitude, floor tied to AGC so noise doesn't count)
        var floorV = agcPeak * 1e-3
        vDSP_vthr(mags, 1, &floorV, logMags, 1, vDSP_Length(half))
        var count = Int32(half)
        vvlogf(logMags, logMags, &count)
        let binHz = sampleRate / Double(fftSize)
        let lowCut = Int(200 / binHz), highCut = min(half, Int(5000 / binHz))
        var flux: Float = 0
        for i in 1..<highCut {
            let d = logMags[i] - prevLog[i]
            if d > 0 { flux += i < lowCut ? d * 2.5 : d }
        }
        prevLog.update(from: logMags, count: half)
        if !loud { flux = 0 }

        fluxHistory.append(flux)
        if fluxHistory.count > Int(fps) { fluxHistory.removeFirst(fluxHistory.count - Int(fps)) }
        var mean: Float = 0, std: Float = 0
        fluxHistory.withUnsafeBufferPointer { p in
            vDSP_normalize(p.baseAddress!, 1, nil, 1, &mean, &std, vDSP_Length(p.count))
        }
        envelope.append(max(0, flux - mean))
        if envelope.count > 560 { envelope.removeFirst(envelope.count - 560) }

        // --- beat clock advance
        let hopDur = Double(hop) / sampleRate
        phase += hopDur * bpm / 60
        framesSinceOnset += 1

        // --- peak pick on the previous frame (1 hop of latency)
        let threshold = mean + 1.35 * std + 0.5
        let minGap = Int(fps * 0.24)
        let now = CACurrentMediaTime()
        if active, f1 > threshold, f1 > f2, f1 >= flux, framesSinceOnset > minGap {
            framesSinceOnset = 0
            let strength = min(1, 0.45 + (f1 - mean) / (std * 4 + 1e-3) * 0.4 + bass * 0.3)
            kickStrength = strength
            lastKickTime = now - hopDur
            // Nudge the PLL toward the onset if it's near a predicted beat.
            let frac = phase - phase.rounded()
            if abs(frac) < 0.32 {
                let gain = confidence > 0.25 ? 0.22 : 0.45
                phase -= frac * gain
            }
        }
        f2 = f1; f1 = flux

        // --- tempo every ~0.25 s
        framesSinceTempo += 1
        if framesSinceTempo >= 24, active, envelope.count >= 300 {
            framesSinceTempo = 0
            estimateTempo(fps: fps)
        }

        // --- publish
        stateLock.lock()
        state.spectrum = smoothBands
        state.bass = bass; state.mid = mid; state.treble = treble; state.level = level
        state.bpm = bpm
        state.phase = phase
        state.phaseTime = now
        state.lastKickTime = lastKickTime
        state.kickStrength = kickStrength
        state.isActive = active
        state.confidence = confidence
        stateLock.unlock()
    }

    private func estimateTempo(fps: Double) {
        let env = envelope
        let n = env.count
        let lagMin = Int(60 * fps / 185), lagMax = Int(60 * fps / 68)
        guard lagMax * 2 < n else { return }

        func acf(_ lag: Int) -> Float {
            var s: Float = 0
            env.withUnsafeBufferPointer { p in
                vDSP_dotpr(p.baseAddress! + lag, 1, p.baseAddress!, 1, &s, vDSP_Length(n - lag))
            }
            return s / Float(n - lag)
        }
        let zero = acf(0)
        guard zero > 1e-6 else { return }

        var scores = [Float](repeating: 0, count: lagMax + 2)
        var bestLag = lagMin
        var best: Float = -1
        for lag in lagMin...lagMax {
            let bpmC = 60 * fps / Double(lag)
            let prior = Float(exp(-0.5 * pow(log2(bpmC / 118) / 0.55, 2)))
            let s = (acf(lag) + 0.5 * acf(lag * 2)) * prior
            scores[lag] = s
            if s > best { best = s; bestLag = lag }
        }
        // Parabolic refinement for sub-hop precision.
        var lagF = Double(bestLag)
        if bestLag > lagMin && bestLag < lagMax {
            let a = scores[bestLag - 1], b = scores[bestLag], c = scores[bestLag + 1]
            let denom = a - 2 * b + c
            if abs(denom) > 1e-9 { lagF += Double(0.5 * (a - c) / denom) }
        }
        let candidate = 60 * fps / lagF
        confidence = min(1, max(0, best / zero))

        if abs(candidate - bpm) / bpm < 0.06 {
            bpm += (candidate - bpm) * 0.25
            pendingCount = 0
        } else if abs(candidate - pendingBpm) / max(pendingBpm, 1) < 0.06 {
            pendingCount += 1
            pendingBpm = candidate
            if pendingCount >= 3 { bpm = candidate; pendingCount = 0 }
        } else {
            pendingBpm = candidate
            pendingCount = 1
        }
    }
}
