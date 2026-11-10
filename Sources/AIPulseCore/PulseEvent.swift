import Foundation

/// 모니터링 대상 AI 코딩 에이전트 종류.
public enum AgentKind: String, Codable, CaseIterable, Sendable {
    /// Claude Code (CLI · 데스크톱 앱의 Code 탭)
    case claude
    /// OpenAI Codex CLI
    case codex
    /// Claude 앱 대화 (MCP 확장으로 보고)
    case claudeApp = "claude-app"

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .claudeApp: return "Claude"
        }
    }

    public var shortName: String {
        switch self {
        case .claude: return "Code"
        case .codex: return "Codex"
        case .claudeApp: return "Claude"
        }
    }
}

/// Claude Code의 TodoWrite 항목 (Codex 계획 항목도 같은 형태로 정규화).
public struct TodoItem: Codable, Equatable, Hashable, Sendable {
    public var content: String
    /// "pending" | "in_progress" | "completed"
    public var status: String
    public var activeForm: String?

    public init(content: String, status: String, activeForm: String? = nil) {
        self.content = content
        self.status = status
        self.activeForm = activeForm
    }

    public var isCompleted: Bool { status == "completed" }
    public var isInProgress: Bool { status == "in_progress" }
}

/// 훅 CLI가 events.jsonl 에 한 줄씩 기록하는 압축된 이벤트.
/// 원본 훅 페이로드(툴 결과, 파일 내용 등)는 크기가 크고 민감할 수 있어 필요한 필드만 남긴다.
public struct PulseEvent: Codable, Equatable, Sendable {
    public var v: Int
    public var agent: AgentKind
    /// Unix epoch seconds (소수점 포함)
    public var ts: Double
    /// hook_event_name 그대로 (예: "PreToolUse", "Stop")
    public var event: String
    public var sessionId: String
    public var cwd: String?
    public var tool: String?
    public var toolUseId: String?
    /// 명령어, 파일 경로, 알림 메시지, 프롬프트 요약 등 (한 줄, 잘라낸 값)
    public var detail: String?
    /// 수정 대상 파일 경로들 (Edit/Write/apply_patch)
    public var paths: [String]?
    public var notificationType: String?
    public var todos: [TodoItem]?
    public var taskId: String?
    public var model: String?
    /// 에이전트를 실행한 GUI 앱의 번들 ID (__CFBundleIdentifier). 터미널로 이동할 때 사용.
    public var hostApp: String?
    /// TERM_PROGRAM (Apple_Terminal, iTerm.app, vscode, ghostty ...)
    public var termProgram: String?
    /// MCP 보고(PulseReport)의 상태: working | needs_input | done | error
    public var status: String?
    /// MCP 보고의 작업 종류: thinking | writing | testing
    public var phase: String?
    /// MCP 보고의 현재 단계 설명 (또는 완료·오류 메시지)
    public var step: String?

    public init(
        agent: AgentKind,
        ts: Double,
        event: String,
        sessionId: String,
        cwd: String? = nil,
        tool: String? = nil,
        toolUseId: String? = nil,
        detail: String? = nil,
        paths: [String]? = nil,
        notificationType: String? = nil,
        todos: [TodoItem]? = nil,
        taskId: String? = nil,
        model: String? = nil,
        hostApp: String? = nil,
        termProgram: String? = nil,
        status: String? = nil,
        phase: String? = nil,
        step: String? = nil
    ) {
        self.v = 1
        self.agent = agent
        self.ts = ts
        self.event = event
        self.sessionId = sessionId
        self.cwd = cwd
        self.tool = tool
        self.toolUseId = toolUseId
        self.detail = detail
        self.paths = paths
        self.notificationType = notificationType
        self.todos = todos
        self.taskId = taskId
        self.model = model
        self.hostApp = hostApp
        self.termProgram = termProgram
        self.status = status
        self.phase = phase
        self.step = step
    }

    public var date: Date { Date(timeIntervalSince1970: ts) }
}
