import Foundation

/// Claude Code / Codex 훅이 stdin 으로 넘기는 JSON 을 PulseEvent 로 변환한다.
///
/// 두 제공자 모두 공통 필드(session_id, cwd, hook_event_name)와
/// 툴 이벤트 필드(tool_name, tool_input, tool_use_id)를 사용하므로 하나의 파서로 처리한다.
/// 알 수 없는 필드는 무시하고, 필수 필드(hook_event_name)가 없으면 nil 을 반환한다.
public enum HookInputParser {

    public static func parse(
        data: Data,
        agent: AgentKind,
        env: [String: String] = [:],
        now: Date = Date()
    ) -> PulseEvent? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any]
        else { return nil }
        return parse(dict: dict, agent: agent, env: env, now: now)
    }

    public static func parse(
        dict: [String: Any],
        agent: AgentKind,
        env: [String: String] = [:],
        now: Date = Date()
    ) -> PulseEvent? {
        guard let name = dict["hook_event_name"] as? String, !name.isEmpty else { return nil }
        let sessionId = (dict["session_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"

        var event = PulseEvent(agent: agent, ts: now.timeIntervalSince1970, event: name, sessionId: sessionId)
        event.cwd = dict["cwd"] as? String
        event.tool = dict["tool_name"] as? String
        event.toolUseId = dict["tool_use_id"] as? String
        event.notificationType = dict["notification_type"] as? String
        event.model = modelName(dict["model"])
        event.hostApp = nonEmpty(env["__CFBundleIdentifier"])
        event.termProgram = nonEmpty(env["TERM_PROGRAM"])

        let input = dict["tool_input"] as? [String: Any]

        switch name {
        case "UserPromptSubmit":
            event.detail = clip(dict["prompt"] as? String, 120)
        case "Notification":
            event.detail = clip(dict["message"] as? String, 160)
        case "Stop", "SubagentStop":
            event.detail = clip(dict["last_assistant_message"] as? String, 160)
        case "StopFailure", "PostToolUseFailure":
            event.detail = clip(describe(dict["error"]) ?? describe(dict["message"]), 160)
        case "SubagentStart":
            event.detail = clip(dict["agent_type"] as? String, 60)
        case "SessionStart":
            event.detail = dict["source"] as? String
        case "SessionEnd":
            event.detail = dict["reason"] as? String
        case "TaskCreated", "TaskCompleted":
            event.taskId = firstString(dict, keys: ["task_id", "taskId", "id"])
            event.detail = clip(firstString(dict, keys: ["task_subject", "subject", "title", "description"]), 100)
        default:
            break
        }

        if let tool = event.tool, let input {
            if tool == "TodoWrite" {
                event.todos = parseTodos(input["todos"])
            }
            if event.detail == nil {
                event.detail = toolDetail(tool: tool, input: input)
            }
            let paths = editedPaths(tool: tool, input: input)
            if !paths.isEmpty { event.paths = paths }
        }

        return event
    }

    // MARK: - Tool details

    static func toolDetail(tool: String, input: [String: Any]) -> String? {
        let lowered = tool.lowercased()
        if lowered.contains("patch") {
            if let files = patchFiles(in: input), !files.isEmpty {
                return clip(files.map(lastPathComponent).joined(separator: ", "), 100)
            }
        }
        if let command = input["command"] as? String {
            return clip(command, 100)
        }
        if let parts = input["command"] as? [String] {
            return clip(stripShellWrapper(parts).joined(separator: " "), 100)
        }
        for key in ["file_path", "notebook_path", "path", "pattern", "url", "query", "description", "prompt"] {
            if let value = input[key] as? String, !value.isEmpty {
                return clip(value, 100)
            }
        }
        return nil
    }

    static func editedPaths(tool: String, input: [String: Any]) -> [String] {
        let lowered = tool.lowercased()
        if lowered.contains("patch") {
            return patchFiles(in: input) ?? []
        }
        guard ToolClassifier.classify(tool: tool, detail: nil) == .write else { return [] }
        for key in ["file_path", "notebook_path", "path"] {
            if let value = input[key] as? String, !value.isEmpty { return [value] }
        }
        return []
    }

    /// apply_patch 형식("*** Update File: path")에서 파일 경로 추출
    static func patchFiles(in input: [String: Any]) -> [String]? {
        var text = ""
        for key in ["command", "input", "patch"] {
            if let s = input[key] as? String { text += s + "\n" }
            if let parts = input[key] as? [String] { text += parts.joined(separator: "\n") + "\n" }
        }
        guard !text.isEmpty else { return nil }
        var files: [String] = []
        let prefixes = ["*** Update File: ", "*** Add File: ", "*** Delete File: "]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for prefix in prefixes where trimmed.hasPrefix(prefix) {
                let path = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                if !path.isEmpty, !files.contains(path) { files.append(path) }
            }
        }
        return files.isEmpty ? nil : files
    }

    /// ["bash", "-lc", "npm test"] → ["npm test"]
    static func stripShellWrapper(_ parts: [String]) -> [String] {
        if parts.count >= 3, ["bash", "sh", "zsh", "/bin/bash", "/bin/sh", "/bin/zsh"].contains(parts[0]),
           parts[1].hasPrefix("-"), parts[1].contains("c") {
            return Array(parts.dropFirst(2))
        }
        return parts
    }

    static func parseTodos(_ value: Any?) -> [TodoItem]? {
        guard let array = value as? [[String: Any]] else { return nil }
        let items = array.compactMap { item -> TodoItem? in
            guard let content = item["content"] as? String else { return nil }
            let status = (item["status"] as? String) ?? "pending"
            return TodoItem(
                content: clip(content, 100) ?? content,
                status: status,
                activeForm: clip(item["activeForm"] as? String, 100)
            )
        }
        return items
    }

    // MARK: - Helpers

    static func modelName(_ value: Any?) -> String? {
        if let s = value as? String { return nonEmpty(s) }
        if let d = value as? [String: Any] {
            return nonEmpty(d["display_name"] as? String) ?? nonEmpty(d["id"] as? String)
        }
        return nil
    }

    static func describe(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let d = value as? [String: Any] {
            return (d["message"] as? String) ?? (d["type"] as? String)
        }
        return nil
    }

    static func firstString(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let s = dict[key] as? String, !s.isEmpty { return s }
            if let n = dict[key] as? NSNumber { return n.stringValue }
        }
        return nil
    }

    static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    static func lastPathComponent(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// 한 줄로 만들고 최대 길이로 자른다.
    public static func clip(_ text: String?, _ maxLength: Int) -> String? {
        guard let text else { return nil }
        let singleLine = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !singleLine.isEmpty else { return nil }
        if singleLine.count <= maxLength { return singleLine }
        return String(singleLine.prefix(max(1, maxLength - 1))) + "…"
    }
}
