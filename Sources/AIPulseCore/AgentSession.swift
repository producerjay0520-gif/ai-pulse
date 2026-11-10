import Foundation

/// UI에 표시하는 세션 활동 상태. 인수인계서의 7가지 상태와 1:1 대응한다.
public enum ActivityState: String, Codable, CaseIterable, Sendable {
    case idle               // 대기
    case thinking           // 분석 중
    case writing            // 코드 작성
    case testing            // 테스트
    case awaitingApproval   // 승인 대기
    case done               // 완료
    case error              // 오류 / 중단

    public var label: String {
        switch self {
        case .idle: return "대기"
        case .thinking: return "분석 중"
        case .writing: return "코드 작성"
        case .testing: return "테스트"
        case .awaitingApproval: return "승인 대기"
        case .done: return "완료"
        case .error: return "오류"
        }
    }

    /// 에이전트가 턴을 진행 중인지 (사용자 입력을 기다리지 않는 상태 + 승인 대기)
    public var isActive: Bool {
        switch self {
        case .thinking, .writing, .testing, .awaitingApproval: return true
        case .idle, .done, .error: return false
        }
    }

    /// 목록 정렬·메뉴바 아이콘 우선순위. 승인 요청이 항상 최우선 (UX 원칙 4).
    public var priority: Int {
        switch self {
        case .awaitingApproval: return 6
        case .error: return 5
        case .writing, .testing, .thinking: return 4
        case .done: return 2
        case .idle: return 1
        }
    }
}

/// 하나의 에이전트 실행 세션 (Claude Code 세션 1개 또는 Codex 세션 1개).
/// 프로젝트는 세션의 작업 디렉터리를 기준으로 앱 레이어에서 묶는다.
public struct AgentSession: Identifiable, Equatable, Sendable {
    public var id: String { key }

    public let key: String
    public let agent: AgentKind
    public let sessionId: String
    /// 세션이 처음 보고한 작업 디렉터리 (프로젝트 식별 기준)
    public var cwd: String

    public var state: ActivityState = .idle
    /// 현재 활동 한 줄 설명 (예: "코드 작성 · PopoverView.swift")
    public var step: String = "세션 시작"
    /// 마지막 사용자 요청 요약
    public var prompt: String?
    /// 마지막 완료 메시지 요약
    public var lastMessage: String?

    public var todos: [TodoItem] = []
    /// TaskCreated / TaskCompleted 기반 작업 목록 (id → 완료 여부)
    public var tasks: [String: Bool] = [:]

    public var startedAt: Date
    public var lastEventAt: Date
    public var turnStartedAt: Date?
    public var lastTurnDuration: TimeInterval?
    public var endedAt: Date?

    public var filesEdited: Set<String> = []
    public var testsRun: Int = 0
    public var testsFailed: Int = 0
    public var activeSubagents: Int = 0
    public var toolCalls: Int = 0
    public var pendingTestToolIds: Set<String> = []
    /// 체크리스트 항목별 시작 시각 / 소요 시간 (content 기준)
    public var todoStartedAt: [String: Date] = [:]
    public var todoDurations: [String: TimeInterval] = [:]
    public var lastTodoMark: Date?

    public var model: String?
    public var hostApp: String?
    public var termProgram: String?

    public init(key: String, agent: AgentKind, sessionId: String, cwd: String, startedAt: Date) {
        self.key = key
        self.agent = agent
        self.sessionId = sessionId
        self.cwd = cwd
        self.startedAt = startedAt
        self.lastEventAt = startedAt
    }

    public var isEnded: Bool { endedAt != nil }

    /// TodoWrite 체크리스트 또는 Task 이벤트 기반 진행률.
    /// 신뢰할 수 있는 근거가 없으면 nil (UI는 숫자 대신 활동 표시).
    public var progress: Double? {
        guard let counts = progressCounts, counts.total > 0 else { return nil }
        return Double(counts.done) / Double(counts.total)
    }

    public var progressCounts: (done: Int, total: Int)? {
        if !todos.isEmpty {
            return (todos.filter(\.isCompleted).count, todos.count)
        }
        if !tasks.isEmpty {
            return (tasks.values.filter { $0 }.count, tasks.count)
        }
        return nil
    }

    /// 체크리스트의 진행 중 항목 (현재 작업 단계)
    public var currentPlanStep: String? {
        guard let item = todos.first(where: \.isInProgress) else { return nil }
        return item.activeForm ?? item.content
    }

    /// 체크리스트 항목의 소요 시간 (완료) 또는 경과 시간 (진행 중)
    public func duration(of item: TodoItem, at now: Date) -> TimeInterval? {
        if let d = todoDurations[item.content] { return d }
        if item.isInProgress, let start = todoStartedAt[item.content] { return max(0, now.timeIntervalSince(start)) }
        return nil
    }

    /// 화면 제목: 사용자 요청 요약 → 진행 중 단계 → 기본값
    public var title: String {
        prompt ?? currentPlanStep ?? "\(agent.displayName) 세션"
    }

    /// 현재 턴의 경과 시간 (진행 중이면 now 기준, 끝났으면 마지막 턴 소요 시간)
    public func elapsed(at now: Date) -> TimeInterval? {
        if state.isActive, let start = turnStartedAt {
            return max(0, now.timeIntervalSince(start))
        }
        return lastTurnDuration
    }

    /// 체크리스트 기반 단순 선형 추정. 근거가 약하면 nil.
    public func estimatedRemaining(at now: Date) -> TimeInterval? {
        guard state.isActive,
              let counts = progressCounts, counts.total >= 3,
              let p = progress, p >= 0.2, p < 1,
              let elapsed = elapsed(at: now), elapsed > 30
        else { return nil }
        return elapsed * (1 - p) / p
    }

    public static func == (lhs: AgentSession, rhs: AgentSession) -> Bool {
        lhs.key == rhs.key && lhs.state == rhs.state && lhs.step == rhs.step &&
        lhs.prompt == rhs.prompt && lhs.lastMessage == rhs.lastMessage &&
        lhs.todos == rhs.todos && lhs.tasks == rhs.tasks &&
        lhs.lastEventAt == rhs.lastEventAt && lhs.turnStartedAt == rhs.turnStartedAt &&
        lhs.lastTurnDuration == rhs.lastTurnDuration && lhs.endedAt == rhs.endedAt &&
        lhs.filesEdited == rhs.filesEdited && lhs.testsRun == rhs.testsRun &&
        lhs.testsFailed == rhs.testsFailed && lhs.activeSubagents == rhs.activeSubagents &&
        lhs.toolCalls == rhs.toolCalls && lhs.todoDurations == rhs.todoDurations &&
        lhs.todoStartedAt == rhs.todoStartedAt &&
        lhs.cwd == rhs.cwd && lhs.model == rhs.model
    }
}
