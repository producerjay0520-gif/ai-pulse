import XCTest
@testable import AIPulseCore

final class HookInputParserTests: XCTestCase {

    func testParsesClaudePreToolUseBash() throws {
        let json = """
        {"session_id":"abc123","cwd":"/Users/me/proj","permission_mode":"default",
         "hook_event_name":"PreToolUse","tool_name":"Bash",
         "tool_input":{"command":"npm test","timeout":120000},"tool_use_id":"toolu_01"}
        """
        let event = try XCTUnwrap(HookInputParser.parse(
            data: Data(json.utf8), agent: .claude,
            env: ["__CFBundleIdentifier": "com.apple.Terminal", "TERM_PROGRAM": "Apple_Terminal"]
        ))
        XCTAssertEqual(event.event, "PreToolUse")
        XCTAssertEqual(event.sessionId, "abc123")
        XCTAssertEqual(event.cwd, "/Users/me/proj")
        XCTAssertEqual(event.tool, "Bash")
        XCTAssertEqual(event.detail, "npm test")
        XCTAssertEqual(event.toolUseId, "toolu_01")
        XCTAssertEqual(event.hostApp, "com.apple.Terminal")
        XCTAssertNil(event.paths)
    }

    func testParsesTodoWrite() throws {
        let json = """
        {"session_id":"s","hook_event_name":"PreToolUse","tool_name":"TodoWrite",
         "tool_input":{"todos":[
           {"content":"A","status":"completed","activeForm":"Doing A"},
           {"content":"B","status":"in_progress","activeForm":"Doing B"},
           {"content":"C","status":"pending","activeForm":"Doing C"}]}}
        """
        let event = try XCTUnwrap(HookInputParser.parse(data: Data(json.utf8), agent: .claude))
        XCTAssertEqual(event.todos?.count, 3)
        XCTAssertEqual(event.todos?[1].status, "in_progress")
    }

    func testParsesCodexApplyPatchFiles() throws {
        let patch = "*** Begin Patch\\n*** Update File: src/main.rs\\n@@\\n-a\\n+b\\n*** Add File: src/new.rs\\n+x\\n*** End Patch"
        let json = """
        {"session_id":"c1","cwd":"/r","hook_event_name":"PreToolUse","tool_name":"apply_patch",
         "tool_input":{"command":"\(patch)"},"turn_id":"t1","model":"some-model"}
        """
        let event = try XCTUnwrap(HookInputParser.parse(data: Data(json.utf8), agent: .codex))
        XCTAssertEqual(event.paths, ["src/main.rs", "src/new.rs"])
        XCTAssertEqual(event.detail, "main.rs, new.rs")
        XCTAssertEqual(event.model, "some-model")
    }

    func testCodexShellArrayCommand() {
        let detail = HookInputParser.toolDetail(tool: "shell", input: ["command": ["bash", "-lc", "cargo test"]])
        XCTAssertEqual(detail, "cargo test")
    }

    func testRejectsInvalidInput() {
        XCTAssertNil(HookInputParser.parse(data: Data("not json".utf8), agent: .claude))
        XCTAssertNil(HookInputParser.parse(data: Data("{\"session_id\":\"x\"}".utf8), agent: .claude))
    }

    func testClip() {
        XCTAssertEqual(HookInputParser.clip("a\nb", 10), "a b")
        XCTAssertEqual(HookInputParser.clip("abcdefghij", 5), "abcd…")
        XCTAssertNil(HookInputParser.clip("   ", 5))
    }
}

final class ToolClassifierTests: XCTestCase {
    func testClassification() {
        XCTAssertEqual(ToolClassifier.classify(tool: "Edit", detail: nil), .write)
        XCTAssertEqual(ToolClassifier.classify(tool: "apply_patch", detail: nil), .write)
        XCTAssertEqual(ToolClassifier.classify(tool: "TodoWrite", detail: nil), .plan)
        XCTAssertEqual(ToolClassifier.classify(tool: "Read", detail: nil), .read)
        XCTAssertEqual(ToolClassifier.classify(tool: "Bash", detail: "swift test"), .test)
        XCTAssertEqual(ToolClassifier.classify(tool: "Bash", detail: "npm run test"), .test)
        XCTAssertEqual(ToolClassifier.classify(tool: "Bash", detail: "pytest -q tests/"), .test)
        XCTAssertEqual(ToolClassifier.classify(tool: "Bash", detail: "ls -la"), .command)
        XCTAssertEqual(ToolClassifier.classify(tool: "Bash", detail: "test -f foo"), .command)
        XCTAssertEqual(ToolClassifier.classify(tool: "Bash", detail: "cat latest.txt"), .command)
    }
}

final class SessionReducerTests: XCTestCase {
    private var sessions: [String: AgentSession] = [:]
    private var clock: Double = 1_000

    private func send(_ name: String, tool: String? = nil, detail: String? = nil,
                      toolId: String? = nil, notification: String? = nil,
                      todos: [TodoItem]? = nil, agent: AgentKind = .claude, sid: String = "s1") -> [PulseEffect] {
        clock += 1
        let event = PulseEvent(agent: agent, ts: clock, event: name, sessionId: sid, cwd: "/p",
                               tool: tool, toolUseId: toolId, detail: detail,
                               notificationType: notification, todos: todos)
        return SessionReducer.apply(event, to: &sessions)
    }

    private var session: AgentSession { sessions["claude:s1"]! }

    override func setUp() {
        sessions = [:]
        clock = 1_000
    }

    func testFullTurn() {
        _ = send("SessionStart", detail: "startup")
        XCTAssertEqual(session.state, .idle)

        _ = send("UserPromptSubmit", detail: "do it")
        XCTAssertEqual(session.state, .thinking)
        XCTAssertEqual(session.prompt, "do it")
        XCTAssertNotNil(session.turnStartedAt)

        _ = send("PreToolUse", tool: "Edit", detail: "/p/a.swift")
        XCTAssertEqual(session.state, .writing)

        _ = send("PreToolUse", tool: "Bash", detail: "swift test", toolId: "t1")
        XCTAssertEqual(session.state, .testing)
        XCTAssertEqual(session.testsRun, 1)

        _ = send("PostToolUseFailure", tool: "Bash", detail: "1 failure", toolId: "t1")
        XCTAssertEqual(session.testsFailed, 1)

        let approval = send("PermissionRequest", tool: "Bash", detail: "git push")
        XCTAssertEqual(session.state, .awaitingApproval)
        XCTAssertEqual(approval, [.needsApproval(sessionKey: "claude:s1")])

        // 같은 승인 요청에 대한 Notification 은 중복 알림을 만들지 않는다
        let dup = send("Notification", notification: "permission_prompt")
        XCTAssertTrue(dup.isEmpty)

        _ = send("PostToolUse", tool: "Bash")
        XCTAssertEqual(session.state, .thinking)

        let done = send("Stop", detail: "finished")
        XCTAssertEqual(session.state, .done)
        XCTAssertEqual(done, [.completed(sessionKey: "claude:s1")])
        XCTAssertEqual(session.lastMessage, "finished")
        XCTAssertNotNil(session.lastTurnDuration)
        XCTAssertNil(session.turnStartedAt)
    }

    func testProgressFromTodos() {
        _ = send("UserPromptSubmit")
        XCTAssertNil(session.progress)
        let todos = [
            TodoItem(content: "a", status: "completed"),
            TodoItem(content: "b", status: "in_progress", activeForm: "Doing b"),
            TodoItem(content: "c", status: "pending"),
            TodoItem(content: "d", status: "pending"),
        ]
        _ = send("PreToolUse", tool: "TodoWrite", todos: todos)
        XCTAssertEqual(session.progress ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(session.currentPlanStep, "Doing b")
    }

    func testCompletedTodosResetOnNewPrompt() {
        _ = send("UserPromptSubmit")
        _ = send("PreToolUse", tool: "TodoWrite", todos: [TodoItem(content: "a", status: "completed")])
        _ = send("Stop")
        _ = send("UserPromptSubmit")
        XCTAssertTrue(session.todos.isEmpty)
    }

    func testStopFailureIsError() {
        _ = send("UserPromptSubmit")
        let effects = send("StopFailure", detail: "rate_limit")
        XCTAssertEqual(session.state, .error)
        XCTAssertEqual(effects, [.failed(sessionKey: "claude:s1")])
    }

    func testCodexInterrupt() {
        _ = send("UserPromptSubmit", agent: .codex, sid: "c")
        _ = send("Interrupt", agent: .codex, sid: "c")
        XCTAssertEqual(sessions["codex:c"]?.state, .error)
    }

    func testSessionsAreIndependent() {
        _ = send("UserPromptSubmit", sid: "s1")
        _ = send("PermissionRequest", tool: "Bash", sid: "s2")
        XCTAssertEqual(sessions["claude:s1"]?.state, .thinking)
        XCTAssertEqual(sessions["claude:s2"]?.state, .awaitingApproval)
    }

    func testSessionEnd() {
        _ = send("UserPromptSubmit")
        _ = send("SessionEnd", detail: "exit")
        XCTAssertTrue(session.isEnded)
        XCTAssertEqual(session.state, .idle)
    }
}

final class EventLogTests: XCTestCase {
    func testWriteAndTailWithPartialLines() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("events.jsonl")
        let tailer = EventTailer(url: url)
        XCTAssertTrue(tailer.readNew().isEmpty)

        try EventWriter.append(PulseEvent(agent: .claude, ts: 1, event: "SessionStart", sessionId: "a"), to: url)
        try EventWriter.append(PulseEvent(agent: .codex, ts: 2, event: "Stop", sessionId: "b"), to: url)
        let first = tailer.readNew()
        XCTAssertEqual(first.map(\.event), ["SessionStart", "Stop"])

        // 부분 줄은 다음 읽기까지 보류된다
        let handle = try FileHandle(forWritingTo: url)
        _ = try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"v\":1,\"agent\":\"claude\",\"ts\":3,".utf8))
        XCTAssertTrue(tailer.readNew().isEmpty)
        try handle.write(contentsOf: Data("\"event\":\"Stop\",\"sessionId\":\"a\"}\n".utf8))
        try handle.close()
        XCTAssertEqual(tailer.readNew().map(\.ts), [3])

        try? FileManager.default.removeItem(at: dir)
    }
}

final class DemoScenarioTests: XCTestCase {
    func testSnapshotCoversAllStates() {
        let mid = DemoScenario.snapshot(at: 35)
        XCTAssertEqual(mid.count, 4)
        XCTAssertTrue(mid.values.contains { $0.state == .awaitingApproval })
        XCTAssertTrue(mid.values.contains { $0.state == .error })
        XCTAssertTrue(mid.values.contains { $0.progress != nil })

        let end = DemoScenario.snapshot(at: DemoScript.loopLength - 1)
        XCTAssertTrue(end.values.contains { $0.state == .done })
    }

    func testAdvanceEmitsEachEventOnce() {
        let scenario = DemoScenario()
        let start = Date(timeIntervalSince1970: 10_000)
        var total = 0
        var t = 0.0
        while t < DemoScript.loopLength - 0.5 {
            total += scenario.advance(now: start.addingTimeInterval(t)).count
            t += 0.5
        }
        XCTAssertEqual(total, DemoScript.timeline.count)
    }
}

final class MCPServerTests: XCTestCase {
    private var recorded: [PulseEvent] = []

    private func makeServer() -> MCPServer {
        MCPServer(sink: { [weak self] in self?.recorded.append($0) }, now: { Date(timeIntervalSince1970: 500) })
    }

    private func json(_ line: String?) throws -> [String: Any] {
        let data = try XCTUnwrap(line?.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testInitializeEchoesProtocolAndHasInstructions() throws {
        let server = makeServer()
        let response = try json(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        XCTAssertNotNil(result["instructions"] as? String)
        XCTAssertEqual(response["id"] as? Int, 1)
    }

    func testNotificationsGetNoResponse() {
        XCTAssertNil(makeServer().handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
    }

    func testToolsListAndUnknownMethod() throws {
        let server = makeServer()
        let list = try json(server.handle(line: #"{"jsonrpc":"2.0","id":"a","method":"tools/list"}"#))
        let tools = try XCTUnwrap((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["name"] as? String, "report_status")

        let unknown = try json(server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"nope"}"#))
        XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32601)

        let parse = try json(server.handle(line: "garbage"))
        XCTAssertEqual((parse["error"] as? [String: Any])?["code"] as? Int, -32700)
    }

    func testReportStatusRecordsEvent() throws {
        let server = makeServer()
        let line = #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"report_status","arguments":{"task_id":"t1","title":"앱 컴포넌트 구현","status":"working","phase":"writing","step":"PopoverView 작성","steps":[{"title":"요청 분석","status":"completed"},{"title":"코드 구현","status":"in_progress"},{"title":"테스트","status":"pending"}],"project":"ai-pulse"}}}"#
        let response = try json(server.handle(line: line))
        XCTAssertEqual((response["result"] as? [String: Any])?["isError"] as? Bool, false)
        let event = try XCTUnwrap(recorded.first)
        XCTAssertEqual(event.agent, .claudeApp)
        XCTAssertEqual(event.event, "PulseReport")
        XCTAssertEqual(event.sessionId, "t1")
        XCTAssertEqual(event.cwd, "claude://ai-pulse")
        XCTAssertEqual(event.todos?.count, 3)
        XCTAssertEqual(event.status, "working")
        XCTAssertEqual(event.phase, "writing")
    }

    func testUnknownToolIsError() throws {
        let response = try json(makeServer().handle(line: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"other"}}"#))
        XCTAssertNotNil(response["error"])
        XCTAssertTrue(recorded.isEmpty)
    }
}

final class PulseReportReducerTests: XCTestCase {
    func testClaudeAppLifecycle() {
        var sessions: [String: AgentSession] = [:]
        let server = MCPServer(sink: { _ in }, now: { Date(timeIntervalSince1970: 1_000) })
        func report(_ args: [String: Any]) -> [PulseEffect] {
            SessionReducer.apply(server.makeEvent(args), to: &sessions)
        }
        let steps: [[String: Any]] = [["title": "분석", "status": "completed"], ["title": "작성", "status": "in_progress"]]
        XCTAssertTrue(report(["task_id": "t", "title": "보고서", "status": "working", "phase": "writing", "steps": steps]).isEmpty)
        let key = "claude-app:t"
        XCTAssertEqual(sessions[key]?.state, .writing)
        XCTAssertEqual(sessions[key]?.prompt, "보고서")
        XCTAssertEqual(sessions[key]?.progress ?? -1, 0.5, accuracy: 0.001)

        XCTAssertEqual(report(["task_id": "t", "status": "needs_input", "step": "어느 쪽으로 할까요?"]), [.needsApproval(sessionKey: key)])
        XCTAssertEqual(sessions[key]?.state, .awaitingApproval)
        XCTAssertTrue(report(["task_id": "t", "status": "needs_input"]).isEmpty, "중복 승인 알림 없음")

        XCTAssertEqual(report(["task_id": "t", "status": "done", "step": "완성"]), [.completed(sessionKey: key)])
        XCTAssertEqual(sessions[key]?.state, .done)
        XCTAssertEqual(sessions[key]?.lastMessage, "완성")
    }
}
