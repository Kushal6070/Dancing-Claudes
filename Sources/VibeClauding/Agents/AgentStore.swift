import AppKit
import Darwin
import Foundation
import Observation

// MARK: - Model

enum AgentStatus: String {
    case working, needsYou, idle

    init(raw: String?) {
        switch raw {
        case "busy": self = .working
        case "waiting", "blocked": self = .needsYou
        default: self = .idle
        }
    }

    var label: String {
        switch self {
        case .working: "Working"
        case .needsYou: "Needs you"
        case .idle: "Idle"
        }
    }

    var sortRank: Int {
        switch self {
        case .needsYou: 0
        case .working: 1
        case .idle: 2
        }
    }
}

struct SubAgent: Identifiable, Hashable {
    let id: String
    let summary: String
    let kind: String
}

struct Agent: Identifiable, Equatable {
    let id: String              // Claude Code session id
    let pid: Int32
    let name: String            // e.g. "sync-9d"
    let cwd: String
    let entrypoint: String
    let startedAt: Date
    var status: AgentStatus
    var statusSince: Date
    var title: String?          // AI or custom session title
    var activity: String?       // "Editing App.swift", "$ npm test"
    var lastPrompt: String?
    var subagents: [SubAgent] = []

    var project: String {
        let last = (cwd as NSString).lastPathComponent
        return last.isEmpty ? cwd : last
    }

    /// Stable small integer used to give every agent its own choreography offset.
    var seed: Int {
        var h: UInt64 = 1469598103934665603
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Int(h % 997)
    }
}

// MARK: - Store

/// Watches `~/.claude/sessions/*.json` (one file per running Claude Code process)
/// and the matching transcripts to learn what every agent is doing right now.
@Observable
final class AgentStore {
    private(set) var agents: [Agent] = []
    private(set) var lastScan: Date = .distantPast

    var workingCount: Int { agents.filter { $0.status == .working }.count }
    var needsYouCount: Int { agents.filter { $0.status == .needsYou }.count }
    var idleCount: Int { agents.filter { $0.status == .idle }.count }

    @ObservationIgnored private let scanner = SessionScanner()
    @ObservationIgnored private var timer: DispatchSourceTimer?
    @ObservationIgnored private let queue = DispatchQueue(label: "vibe.agents", qos: .utility)

    init() { start() }

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(1000), leeway: .milliseconds(150))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let found = self.scanner.scan()
            DispatchQueue.main.async {
                if found != self.agents { self.agents = found }
                self.lastScan = Date()
            }
        }
        t.resume()
        timer = t
    }

    func open(_ agent: Agent) {
        IDELauncher.open(agent)
    }
}

// MARK: - Scanner (runs on a background queue)

private struct SessionFile: Decodable {
    let pid: Int32
    let sessionId: String
    let cwd: String?
    let startedAt: Double?
    let kind: String?
    let entrypoint: String?
    let name: String?
    let status: String?
    let statusUpdatedAt: Double?
    let spare: Bool?
}

final class SessionScanner {
    let claudeDir: URL
    private let fm = FileManager.default
    private var transcriptCache: [String: CachedTranscript] = [:]
    private var titleCache: [String: String] = [:]
    private var missingTranscript: [String: Date] = [:]
    private var finishedSubagents = Set<String>()
    private var subagentMeta: [String: (summary: String, kind: String)] = [:]
    private var subagentResults: [String: (at: Date, list: [SubAgent])] = [:]

    private struct CachedTranscript {
        var url: URL
        var mtime: Date
        var parsedAt: Date
        var info: TranscriptInfo
    }

    init() {
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            claudeDir = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        } else {
            claudeDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        }
    }

    func scan() -> [Agent] {
        let sessionsDir = claudeDir.appendingPathComponent("sessions")
        guard let files = try? fm.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        var result: [Agent] = []
        var seen = Set<String>()

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let s = try? decoder.decode(SessionFile.self, from: data),
                  s.spare != true,
                  Self.isClaudeProcessAlive(s.pid),
                  !seen.contains(s.sessionId)
            else { continue }
            seen.insert(s.sessionId)

            let cwd = s.cwd ?? "~"
            var agent = Agent(
                id: s.sessionId,
                pid: s.pid,
                name: s.name ?? "claude-\(s.pid)",
                cwd: cwd,
                entrypoint: s.entrypoint ?? s.kind ?? "cli",
                startedAt: Date(timeIntervalSince1970: (s.startedAt ?? 0) / 1000),
                status: AgentStatus(raw: s.status),
                statusSince: Date(timeIntervalSince1970: (s.statusUpdatedAt ?? s.startedAt ?? 0) / 1000)
            )

            if let tURL = transcriptURL(sessionId: s.sessionId, cwd: cwd) {
                let info = transcriptInfo(for: s.sessionId, url: tURL)
                agent.activity = info.activity
                agent.lastPrompt = info.lastPrompt
                agent.title = info.title ?? title(for: s.sessionId, url: tURL)
                agent.subagents = runningSubagents(transcript: tURL)
            }
            result.append(agent)
        }

        // Keep a stable left-to-right order: oldest session first.
        result.sort { $0.startedAt < $1.startedAt }
        transcriptCache = transcriptCache.filter { seen.contains($0.key) }
        return result
    }

    // MARK: Liveness

    static func isClaudeProcessAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) != 0 && errno != EPERM { return false }
        // Guard against PID reuse: the process should still look like Claude Code.
        var buf = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard n > 0 else { return true } // can't inspect; trust kill()
        let path = String(cString: buf).lowercased()
        return path.contains("claude") || path.hasSuffix("/node") || path.hasSuffix("/bun")
    }

    // MARK: Transcripts

    private func projectSlug(_ cwd: String) -> String {
        String(cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    private func transcriptURL(sessionId: String, cwd: String) -> URL? {
        if let cached = transcriptCache[sessionId] { return cached.url }
        let projects = claudeDir.appendingPathComponent("projects")
        let direct = projects.appendingPathComponent(projectSlug(cwd)).appendingPathComponent("\(sessionId).jsonl")
        if fm.fileExists(atPath: direct.path) { return direct }
        // Brand-new sessions may not have a transcript yet; don't sweep every folder every second.
        if let last = missingTranscript[sessionId], Date().timeIntervalSince(last) < 15 { return nil }
        missingTranscript[sessionId] = Date()
        // Fallback: search every project folder once.
        if let dirs = try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) {
            for d in dirs {
                let candidate = d.appendingPathComponent("\(sessionId).jsonl")
                if fm.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    private func mtime(_ url: URL) -> Date? {
        (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func transcriptInfo(for sessionId: String, url: URL) -> TranscriptInfo {
        let m = mtime(url) ?? .distantPast
        // Busy transcripts change constantly; re-reading them more than every 1.5 s buys nothing visible.
        if let c = transcriptCache[sessionId], c.mtime == m || Date().timeIntervalSince(c.parsedAt) < 1.5 { return c.info }
        let info = TranscriptParser.parseTail(url)
        transcriptCache[sessionId] = CachedTranscript(url: url, mtime: m, parsedAt: Date(), info: info)
        return info
    }

    /// Titles usually live early in the transcript; scan the whole file once per session.
    private func title(for sessionId: String, url: URL) -> String? {
        if let t = titleCache[sessionId] { return t.isEmpty ? nil : t }
        let t = TranscriptParser.scanTitle(url) ?? ""
        titleCache[sessionId] = t
        return t.isEmpty ? nil : t
    }

    /// Helpers whose transcript was written in the last 90 s and whose meta isn't marked finished.
    /// Finished helpers are remembered so busy folders with hundreds of old runs stay cheap.
    private func runningSubagents(transcript: URL) -> [SubAgent] {
        let key = transcript.path
        if let cached = subagentResults[key], Date().timeIntervalSince(cached.at) < 2.5 { return cached.list }
        let dir = transcript.deletingPathExtension().appendingPathComponent("subagents")
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else {
            subagentResults[key] = (Date(), [])
            return []
        }
        let now = Date()
        var out: [SubAgent] = []
        for name in names where name.hasSuffix(".jsonl") {
            let path = dir.appendingPathComponent(name).path
            if finishedSubagents.contains(path) { continue }
            guard let m = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { continue }
            let id = String(name.dropLast(".jsonl".count))
            let metaPath = dir.appendingPathComponent(id + ".meta.json")
            var finished = false
            if let data = fm.contents(atPath: metaPath.path),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                finished = (obj["finished"] as? Bool) == true
                subagentMeta[path] = ((obj["description"] as? String) ?? "Helper", (obj["agentType"] as? String) ?? "agent")
            }
            if finished || now.timeIntervalSince(m) > 600 {
                finishedSubagents.insert(path)
                continue
            }
            guard now.timeIntervalSince(m) < 90 else { continue }
            let meta = subagentMeta[path] ?? ("Helper", "agent")
            out.append(SubAgent(id: id, summary: meta.summary, kind: meta.kind))
        }
        out.sort { $0.id < $1.id }
        subagentResults[key] = (now, out)
        return out
    }
}

// MARK: - Opening an agent's project

enum IDELauncher {
    static func open(_ agent: Agent) {
        let url = URL(fileURLWithPath: agent.cwd)
        let ws = NSWorkspace.shared
        if agent.entrypoint.contains("vscode") || agent.entrypoint.contains("ide") {
            for bundleID in ideBundleIDs(for: agent.cwd) {
                if let app = ws.urlForApplication(withBundleIdentifier: bundleID) {
                    ws.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                    return
                }
            }
        }
        ws.activateFileViewerSelecting([url])
    }

    /// Reads `~/.claude/ide/*.lock` to find which editor hosts the workspace.
    private static func ideBundleIDs(for cwd: String) -> [String] {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/ide")
        var preferred: [String] = []
        if let locks = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for lock in locks where lock.pathExtension == "lock" {
                guard let data = try? Data(contentsOf: lock),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let folders = obj["workspaceFolders"] as? [String],
                      folders.contains(where: { cwd.hasPrefix($0) }),
                      let ide = (obj["ideName"] as? String)?.lowercased() else { continue }
                if ide.contains("cursor") { preferred.append("com.todesktop.230313mzl4w4u92") }
                if ide.contains("windsurf") { preferred.append("com.exafunction.windsurf") }
                if ide.contains("insiders") { preferred.append("com.microsoft.VSCodeInsiders") }
                if ide.contains("visual studio code") { preferred.append("com.microsoft.VSCode") }
            }
        }
        return preferred + ["com.microsoft.VSCode"]
    }
}
