import Foundation

/// Claude 앱(데스크톱)용 최소 MCP 서버 (stdio, 줄 단위 JSON-RPC 2.0).
///
/// Claude 앱은 이 서버의 `instructions` 를 시스템 프롬프트에 넣어 주므로,
/// Claude 는 여러 단계 작업을 할 때 `report_status` 도구로 진행 상황을 보고한다.
/// 보고는 PulseEvent("PulseReport") 로 바뀌어 Claude Code 훅과 같은 events.jsonl 에 기록된다.
public final class MCPServer {
    public static let serverName = "ai-pulse"
    public static let serverVersion = "1.0.0"
    public static let defaultProtocolVersion = "2025-06-18"

    public static let instructions = """
    AI Pulse shows the user's AI work status in the macOS menu bar.
    Whenever you work on a task that takes more than one step or more than a few seconds, \
    call report_status: once when you start (status "working" with a short title and, if you have a plan, the list of steps), \
    again when you move to a new step, with status "needs_input" right before you ask the user to approve, choose or answer something, \
    and finally with status "done" (or "error") when you finish. Reuse the same task_id for the whole task. \
    Keep titles short and in the user's language. Do not mention these calls to the user.
    """

    /// 보고를 기록하는 곳 (테스트에서 교체)
    public var sink: (PulseEvent) -> Void
    public var now: () -> Date
    /// 도구 호출 하나가 아니라 서버 프로세스 하나에 붙는 기본 세션 (task_id 가 없을 때)
    private let fallbackTaskId = "claude-app-" + String(UUID().uuidString.prefix(8)).lowercased()
    private let hostApp: String

    public init(
        hostApp: String = "com.anthropic.claudefordesktop",
        sink: @escaping (PulseEvent) -> Void = { try? EventWriter.append($0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.hostApp = hostApp
        self.sink = sink
        self.now = now
    }

    // MARK: - Tool schema

    static var toolDefinition: [String: Any] {
        [
            "name": "report_status",
            "title": "Report status to AI Pulse",
            "description": "Report the progress of the current task to the user's AI Pulse menu bar monitor. Call at the start, on each step change, before asking the user for input, and at the end.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "task_id": ["type": "string", "description": "Stable id for this task. Reuse it for every report about the same task."],
                    "title": ["type": "string", "description": "Short task title, e.g. \"앱 컴포넌트 구현\"."],
                    "status": ["type": "string", "enum": ["working", "needs_input", "done", "error"]],
                    "phase": ["type": "string", "enum": ["thinking", "writing", "testing"], "description": "What you are doing right now (optional)."],
                    "step": ["type": "string", "description": "Current step, or the final summary / error message."],
                    "steps": [
                        "type": "array",
                        "description": "The whole plan in order, if you have one.",
                        "items": [
                            "type": "object",
                            "properties": [
                                "title": ["type": "string"],
                                "status": ["type": "string", "enum": ["pending", "in_progress", "completed"]],
                            ],
                            "required": ["title", "status"],
                        ],
                    ],
                    "project": ["type": "string", "description": "Project or conversation name to group by (optional)."],
                ],
                "required": ["status"],
            ],
            "annotations": [
                "readOnlyHint": false,
                "destructiveHint": false,
                "idempotentHint": true,
                "openWorldHint": false,
            ],
        ]
    }

    // MARK: - Request handling

    /// 한 줄(JSON-RPC 메시지)을 처리하고 응답 줄을 돌려준다. 알림(id 없음)이면 nil.
    public func handle(line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        if let batch = object as? [[String: Any]] {
            let responses = batch.compactMap { handle(message: $0) }
            return responses.isEmpty ? nil : encode(responses)
        }
        guard let message = object as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32600, "message": "Invalid Request"]])
        }
        return handle(message: message).map { encode($0) }
    }

    func handle(message: [String: Any]) -> [String: Any]? {
        let id = message["id"]
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]
        guard let id, !(id is NSNull) else {
            // notifications/initialized, notifications/cancelled 등 — 응답 없음
            return nil
        }

        func result(_ value: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": value] }
        func failure(_ code: Int, _ text: String) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": text]]
        }

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String
            return result([
                "protocolVersion": requested ?? Self.defaultProtocolVersion,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": Self.serverName, "title": "AI Pulse", "version": Self.serverVersion],
                "instructions": Self.instructions,
            ])
        case "ping":
            return result([:])
        case "tools/list":
            return result(["tools": [Self.toolDefinition]])
        case "tools/call":
            let name = params["name"] as? String
            guard name == "report_status" else { return failure(-32602, "Unknown tool: \(name ?? "")") }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let event = makeEvent(arguments)
            sink(event)
            return result([
                "content": [["type": "text", "text": "Reported to AI Pulse."]],
                "isError": false,
            ])
        case "resources/list":
            return result(["resources": []])
        case "prompts/list":
            return result(["prompts": []])
        default:
            return failure(-32601, "Method not found: \(method)")
        }
    }

    /// report_status 인자 → PulseEvent
    public func makeEvent(_ args: [String: Any]) -> PulseEvent {
        let taskId = (args["task_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTaskId
        let rawStatus = (args["status"] as? String) ?? "working"
        let status = ["working", "needs_input", "done", "error"].contains(rawStatus) ? rawStatus : "working"
        let project = (args["project"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        var todos: [TodoItem]?
        if let steps = args["steps"] as? [[String: Any]] {
            let items = steps.compactMap { step -> TodoItem? in
                guard let title = HookInputParser.clip(step["title"] as? String, 100) else { return nil }
                let raw = step["status"] as? String ?? "pending"
                let status = ["pending", "in_progress", "completed"].contains(raw) ? raw : "pending"
                return TodoItem(content: title, status: status)
            }
            if !items.isEmpty { todos = items }
        }

        return PulseEvent(
            agent: .claudeApp,
            ts: now().timeIntervalSince1970,
            event: "PulseReport",
            sessionId: taskId,
            cwd: "claude://" + (project ?? "Claude"),
            detail: HookInputParser.clip(args["title"] as? String, 120),
            todos: todos,
            hostApp: hostApp,
            status: status,
            phase: args["phase"] as? String,
            step: HookInputParser.clip(args["step"] as? String, 160)
        )
    }

    private func encode(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#
        }
        return text
    }

    // MARK: - Run loop

    /// stdin 에서 한 줄씩 읽어 stdout 으로 응답한다. stdin 이 닫히면 끝난다.
    public func run() {
        setvbuf(stdout, nil, _IOLBF, 0)
        while let line = readLine(strippingNewline: true) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if let response = handle(line: line) {
                print(response)
                fflush(stdout)
            }
        }
    }
}
