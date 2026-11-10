import Foundation

/// 리듀서가 앱에 요청하는 부수 효과 (알림 등)
public enum PulseEffect: Equatable, Sendable {
    case completed(sessionKey: String)
    case needsApproval(sessionKey: String)
    case failed(sessionKey: String)
}

/// 이벤트 → 세션 상태 전이. 순수 함수라 Mock 데이터와 실제 훅 이벤트가 같은 경로를 탄다.
public enum SessionReducer {

    public static func key(for event: PulseEvent) -> String {
        "\(event.agent.rawValue):\(event.sessionId)"
    }

    @discardableResult
    public static func apply(_ event: PulseEvent, to sessions: inout [String: AgentSession]) -> [PulseEffect] {
        let key = key(for: event)
        let date = event.date
        var s = sessions[key] ?? AgentSession(
            key: key,
            agent: event.agent,
            sessionId: event.sessionId,
            cwd: event.cwd ?? "",
            startedAt: date
        )
        var effects: [PulseEffect] = []

        s.lastEventAt = max(s.lastEventAt, date)
        if s.cwd.isEmpty, let cwd = event.cwd { s.cwd = cwd }
        if let model = event.model { s.model = model }
        if let host = event.hostApp { s.hostApp = host }
        if let term = event.termProgram { s.termProgram = term }

        switch event.event {
        case "SessionStart":
            s.endedAt = nil
            if event.detail == "clear" {
                s.todos = []
                s.tasks = [:]
                s.prompt = nil
            }
            if !s.state.isActive { s.state = .idle }
            s.step = event.detail == "resume" ? "세션 재개" : "세션 시작"

        case "UserPromptSubmit":
            beginTurn(&s, at: date)
            if let prompt = event.detail { s.prompt = prompt }
            if !s.todos.isEmpty, s.todos.allSatisfy(\.isCompleted) {
                s.todos = []
                s.todoStartedAt = [:]
                s.todoDurations = [:]
            }
            s.lastTodoMark = nil
            if !s.tasks.isEmpty, s.tasks.values.allSatisfy({ $0 }) { s.tasks = [:] }
            s.state = .thinking
            s.step = "요청 분석 중"

        case "PreToolUse":
            if !s.state.isActive { beginTurn(&s, at: date) }
            applyToolStart(event, to: &s)

        case "PermissionRequest":
            if !s.state.isActive { beginTurn(&s, at: date) }
            if s.state != .awaitingApproval { effects.append(.needsApproval(sessionKey: key)) }
            s.state = .awaitingApproval
            s.step = "승인 필요 · " + toolSummary(event)

        case "PostToolUse":
            if s.state == .awaitingApproval {
                s.state = .thinking
                s.step = "승인됨 · 계속 진행"
            }
            if let paths = event.paths { s.filesEdited.formUnion(paths) }
            if let id = event.toolUseId { s.pendingTestToolIds.remove(id) }

        case "PostToolUseFailure":
            if s.state == .awaitingApproval { s.state = .thinking }
            if let id = event.toolUseId, s.pendingTestToolIds.remove(id) != nil {
                s.testsFailed += 1
                s.step = "테스트 실패 · " + (event.detail ?? "결과 확인 중")
            } else if let detail = event.detail {
                s.step = "툴 실패 · " + detail
            }

        case "Notification":
            switch event.notificationType {
            case "permission_prompt":
                if s.state != .awaitingApproval { effects.append(.needsApproval(sessionKey: key)) }
                if !s.state.isActive { beginTurn(&s, at: date) }
                s.state = .awaitingApproval
                s.step = "승인 필요 · " + (event.detail ?? "터미널 확인")
            case "agent_needs_input", "elicitation_dialog":
                if s.state != .awaitingApproval { effects.append(.needsApproval(sessionKey: key)) }
                s.state = .awaitingApproval
                s.step = "입력 필요 · " + (event.detail ?? "터미널 확인")
            case "agent_completed":
                if s.state.isActive {
                    finishTurn(&s, at: date)
                    s.state = .done
                    s.step = "작업 완료"
                    effects.append(.completed(sessionKey: key))
                }
            case "idle_prompt":
                // 사용자 입력 대기 알림. Stop 을 놓쳤다면 여기서 정리한다.
                if s.state.isActive && s.state != .awaitingApproval {
                    finishTurn(&s, at: date)
                    s.state = .done
                    s.step = "입력 대기"
                }
            default:
                break
            }

        case "Stop":
            if s.state.isActive || s.turnStartedAt != nil {
                effects.append(.completed(sessionKey: key))
            }
            finishTurn(&s, at: date)
            s.state = .done
            s.step = "작업 완료"
            if let message = event.detail { s.lastMessage = message }
            s.activeSubagents = 0

        case "StopFailure":
            finishTurn(&s, at: date)
            s.state = .error
            s.step = "오류 · " + (event.detail ?? "API 오류")
            s.activeSubagents = 0
            effects.append(.failed(sessionKey: key))

        case "Interrupt":
            finishTurn(&s, at: date)
            s.state = .error
            s.step = "중단됨"
            s.activeSubagents = 0

        case "SubagentStart":
            s.activeSubagents += 1
            s.step = "서브에이전트 실행 · " + (event.detail ?? "작업 위임")

        case "SubagentStop":
            s.activeSubagents = max(0, s.activeSubagents - 1)

        case "TaskCreated":
            if let id = event.taskId { s.tasks[id] = false }

        case "TaskCompleted":
            if let id = event.taskId { s.tasks[id] = true }

        case "PreCompact":
            s.step = "컨텍스트 정리 중"

        case "PulseReport":
            effects += applyReport(event, to: &s, key: key)

        case "SessionEnd":
            s.endedAt = date
            if s.state.isActive {
                finishTurn(&s, at: date)
                s.state = .idle
            }
            s.step = "세션 종료"

        default:
            break
        }

        sessions[key] = s
        return effects
    }

    // MARK: - MCP 보고 (Claude 앱)

    /// Claude 앱이 aipulse-mcp 의 report_status 도구로 보낸 상태를 반영한다.
    static func applyReport(_ event: PulseEvent, to s: inout AgentSession, key: String) -> [PulseEffect] {
        let date = event.date
        if let title = event.detail.flatMap({ HookInputParser.clip($0, 120) }), s.prompt == nil || !s.state.isActive {
            s.prompt = title
        }
        if let todos = event.todos, !todos.isEmpty {
            updateTodos(todos, in: &s, at: date)
        }
        switch event.status ?? "working" {
        case "needs_input":
            if !s.state.isActive { beginTurn(&s, at: date) }
            let wasWaiting = s.state == .awaitingApproval
            s.state = .awaitingApproval
            s.step = "입력 필요 · " + (event.step ?? "Claude 앱 확인")
            return wasWaiting ? [] : [.needsApproval(sessionKey: key)]
        case "done":
            let notify = s.state.isActive || s.turnStartedAt != nil
            finishTurn(&s, at: date)
            s.state = .done
            s.step = "작업 완료"
            if let message = event.step { s.lastMessage = message }
            return notify ? [.completed(sessionKey: key)] : []
        case "error":
            finishTurn(&s, at: date)
            s.state = .error
            s.step = "오류 · " + (event.step ?? "작업 실패")
            return [.failed(sessionKey: key)]
        default:
            if !s.state.isActive { beginTurn(&s, at: date) }
            switch event.phase {
            case "writing": s.state = .writing
            case "testing": s.state = .testing
            default: s.state = .thinking
            }
            if let step = event.step, !step.isEmpty {
                s.step = step
            } else if let current = s.currentPlanStep {
                s.step = current
            } else {
                s.step = "작업 중"
            }
            return []
        }
    }

    // MARK: - Helpers

    static func beginTurn(_ s: inout AgentSession, at date: Date) {
        s.turnStartedAt = date
        s.lastTurnDuration = nil
    }

    static func finishTurn(_ s: inout AgentSession, at date: Date) {
        if let start = s.turnStartedAt {
            s.lastTurnDuration = max(0, date.timeIntervalSince(start))
        }
        s.turnStartedAt = nil
    }

    static func applyToolStart(_ event: PulseEvent, to s: inout AgentSession) {
        guard let tool = event.tool else { return }
        s.toolCalls += 1
        let category = ToolClassifier.classify(tool: tool, detail: event.detail)
        switch category {
        case .plan:
            if let todos = event.todos { updateTodos(todos, in: &s, at: event.date) }
            if s.state == .awaitingApproval || !s.state.isActive { s.state = .thinking }
            s.step = "작업 계획 업데이트"
        case .write:
            s.state = .writing
            s.step = "코드 작성 · " + fileSummary(event)
        case .test:
            s.state = .testing
            s.testsRun += 1
            if let id = event.toolUseId { s.pendingTestToolIds.insert(id) }
            s.step = "테스트 실행 · " + (event.detail ?? tool)
        case .command:
            s.state = .thinking
            s.step = "명령 실행 · " + (event.detail ?? tool)
        case .read:
            s.state = .thinking
            s.step = "살펴보는 중 · " + fileSummary(event)
        case .delegate:
            s.state = .thinking
            s.step = "작업 위임 · " + (event.detail ?? tool)
        case .other:
            s.state = .thinking
            s.step = "\(tool) 사용 중"
        }
    }

    /// 새 체크리스트를 반영하며 항목별 시작/완료 시각을 기록한다
    static func updateTodos(_ todos: [TodoItem], in s: inout AgentSession, at date: Date) {
        let previous = Dictionary(s.todos.map { ($0.content, $0) }, uniquingKeysWith: { a, _ in a })
        for item in todos {
            let before = previous[item.content]
            if item.isInProgress, s.todoStartedAt[item.content] == nil {
                s.todoStartedAt[item.content] = date
            }
            if item.isCompleted, before?.isCompleted != true, s.todoDurations[item.content] == nil {
                let start = s.todoStartedAt[item.content] ?? s.lastTodoMark ?? s.turnStartedAt ?? date
                s.todoDurations[item.content] = max(0, date.timeIntervalSince(start))
                s.lastTodoMark = date
            }
        }
        let current = Set(todos.map(\.content))
        s.todoStartedAt = s.todoStartedAt.filter { current.contains($0.key) }
        s.todoDurations = s.todoDurations.filter { current.contains($0.key) }
        s.todos = todos
    }

    static func fileSummary(_ event: PulseEvent) -> String {
        if let paths = event.paths, !paths.isEmpty {
            let names = paths.map { ($0 as NSString).lastPathComponent }
            return names.count > 2 ? "\(names[0]) 외 \(names.count - 1)개" : names.joined(separator: ", ")
        }
        if let detail = event.detail {
            return detail.contains("/") && !detail.contains(" ") ? (detail as NSString).lastPathComponent : detail
        }
        return event.tool ?? ""
    }

    static func toolSummary(_ event: PulseEvent) -> String {
        switch (event.tool, event.detail) {
        case let (tool?, detail?): return "\(tool): \(detail)"
        case let (tool?, nil): return tool
        case let (nil, detail?): return detail
        default: return "터미널 확인"
        }
    }
}
