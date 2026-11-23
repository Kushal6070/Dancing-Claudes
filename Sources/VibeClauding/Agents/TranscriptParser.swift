import Foundation

struct TranscriptInfo: Equatable {
    var activity: String?
    var lastPrompt: String?
    var title: String?
}

/// Reads the tail of a Claude Code transcript (`.jsonl`) and turns the most recent
/// entries into a short, human line like "Editing AgentStore.swift".
enum TranscriptParser {
    private static let mAssistant = Data(#""type":"assistant""#.utf8)
    private static let mUser = Data(#""type":"user""#.utf8)
    private static let mToolResult = Data(#""tool_result""#.utf8)
    private static let mTitle = Data(#"-title","#.utf8)
    private static let mLastPrompt = Data(#""type":"last-prompt""#.utf8)

    static func parseTail(_ url: URL, maxBytes: UInt64 = 768_000) -> TranscriptInfo {
        guard let lines = tailLines(url, maxBytes: maxBytes) else { return TranscriptInfo() }
        var info = TranscriptInfo()
        var examined = 0

        for line in lines.reversed() {
            examined += 1
            if examined > 400 { break }
            // Cheap substring checks first; most lines (API logs, tool output) never need JSON parsing.
            let isUser = line.range(of: mUser) != nil
            let isAssistant = !isUser && line.range(of: mAssistant) != nil
            if isUser, line.range(of: mToolResult) != nil {
                // A tool result came back; the model is chewing on it.
                if info.activity == nil { info.activity = "Thinking" }
                continue
            }
            let isTitle = !isUser && !isAssistant && line.count < 4096 && line.range(of: mTitle) != nil
            let isLastPrompt = !isUser && !isAssistant && line.range(of: mLastPrompt) != nil
            guard isUser || isAssistant || isTitle || isLastPrompt else { continue }
            if isAssistant && info.activity != nil { continue }

            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = obj["type"] as? String else { continue }

            switch type {
            case "custom-title":
                if info.title == nil, let t = obj["customTitle"] as? String { info.title = clean(t, max: 70) }
            case "ai-title":
                if info.title == nil, let t = obj["aiTitle"] as? String { info.title = clean(t, max: 70) }
            case "last-prompt":
                if info.lastPrompt == nil, let t = obj["lastPrompt"] as? String, isHumanText(t) { info.lastPrompt = clean(t, max: 140) }
            case "assistant":
                guard info.activity == nil,
                      let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] else { break }
                for block in content.reversed() {
                    let kind = block["type"] as? String
                    if kind == "tool_use" {
                        info.activity = describeTool(block["name"] as? String ?? "tool",
                                                     input: block["input"] as? [String: Any] ?? [:])
                        break
                    } else if kind == "text" {
                        info.activity = "Writing a reply"
                        break
                    } else if kind == "thinking" || kind == "redacted_thinking" {
                        info.activity = "Thinking"
                        break
                    }
                }
            case "user":
                if (obj["isMeta"] as? Bool) == true { break }
                let message = obj["message"] as? [String: Any]
                if let text = promptText(message?["content"]) {
                    if info.lastPrompt == nil { info.lastPrompt = clean(text, max: 140) }
                    if info.activity == nil { info.activity = "Reading your message" }
                }
            default:
                break
            }
            if info.activity != nil && info.lastPrompt != nil && info.title != nil { break }
        }
        return info
    }

    /// Finds the most recent title anywhere in the file (titles are written early).
    static func scanTitle(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        var found: String?
        for key in ["\"type\":\"custom-title\"", "\"type\":\"ai-title\""] {
            guard let needle = key.data(using: .utf8) else { continue }
            var searchRange = data.startIndex..<data.endIndex
            var lastLine: Data?
            while let r = data.range(of: needle, options: [], in: searchRange) {
                let start = data[..<r.lowerBound].lastIndex(of: 0x0A).map { $0 + 1 } ?? data.startIndex
                let end = data[r.upperBound...].firstIndex(of: 0x0A) ?? data.endIndex
                lastLine = data[start..<end]
                searchRange = end..<data.endIndex
            }
            if let line = lastLine,
               let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
               let t = (obj["customTitle"] as? String) ?? (obj["aiTitle"] as? String) {
                found = clean(t, max: 70)
                break // a custom title wins over the AI one
            }
        }
        return found
    }

    // MARK: Helpers

    private static func tailLines(_ url: URL, maxBytes: UInt64) -> [Data]? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        guard let size = try? fh.seekToEnd() else { return nil }
        let len = min(size, maxBytes)
        try? fh.seek(toOffset: size - len)
        guard let data = try? fh.read(upToCount: Int(len)) else { return nil }
        var parts = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        if len < size, !parts.isEmpty { parts.removeFirst() } // partial first line
        return parts.map { Data($0) }
    }

    private static func promptText(_ content: Any?) -> String? {
        if let s = content as? String { return isHumanText(s) ? s : nil }
        guard let blocks = content as? [[String: Any]] else { return nil }
        if blocks.contains(where: { ($0["type"] as? String) == "tool_result" }) { return nil }
        for b in blocks where (b["type"] as? String) == "text" {
            if let s = b["text"] as? String, isHumanText(s) { return s }
        }
        return nil
    }

    private static func isHumanText(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && !t.hasPrefix("<") && !t.hasPrefix("[Request interrupted")
    }

    static func clean(_ s: String, max: Int) -> String {
        let oneLine = s.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return oneLine.count > max ? String(oneLine.prefix(max - 1)) + "…" : oneLine
    }

    private static func base(_ path: Any?) -> String {
        guard let p = path as? String, !p.isEmpty else { return "a file" }
        return (p as NSString).lastPathComponent
    }

    static func describeTool(_ name: String, input: [String: Any]) -> String {
        switch name {
        case "Bash", "BashOutput":
            let cmd = (input["command"] as? String)?.split(separator: "\n").first.map(String.init) ?? "shell"
            return clean("$ " + cmd, max: 46)
        case "Read": return "Reading " + base(input["file_path"])
        case "Edit", "MultiEdit": return "Editing " + base(input["file_path"])
        case "Write": return "Writing " + base(input["file_path"])
        case "NotebookEdit": return "Editing " + base(input["notebook_path"])
        case "Grep": return clean("Searching “\(input["pattern"] as? String ?? "")”", max: 46)
        case "Glob": return clean("Finding \(input["pattern"] as? String ?? "files")", max: 46)
        case "WebFetch":
            let host = (input["url"] as? String).flatMap { URL(string: $0)?.host } ?? "the web"
            return "Fetching " + host
        case "WebSearch": return clean("Googling “\(input["query"] as? String ?? "")”", max: 46)
        case "Agent", "Task":
            return clean("Delegating: " + (input["description"] as? String ?? "a helper"), max: 46)
        case "TodoWrite", "TaskCreate", "TaskUpdate": return "Updating the plan"
        case "Skill": return clean("Using skill " + (input["skill"] as? String ?? ""), max: 46)
        case "AskUserQuestion": return "Has a question for you"
        case "ExitPlanMode": return "Plan ready for review"
        case "Artifact": return "Publishing an artifact"
        default:
            if name.hasPrefix("mcp__") {
                let parts = name.components(separatedBy: "__")
                var server = parts.count > 1 ? parts[1] : "mcp"
                if server.hasPrefix("claude_ai_") { server.removeFirst("claude_ai_".count) }
                let tool = (parts.count > 2 ? parts[2] : name).replacingOccurrences(of: "_", with: " ")
                return clean("\(server.replacingOccurrences(of: "_", with: " ")): \(tool)", max: 46)
            }
            return clean("Using " + name, max: 46)
        }
    }
}
