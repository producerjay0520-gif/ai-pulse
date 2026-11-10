import Foundation

/// 실제 에이전트 연결 없이 UI 전체를 확인하기 위한 Mock 이벤트 스크립트.
/// 실제 훅 이벤트와 같은 PulseEvent 를 만들어 같은 리듀서로 흘려보낸다.
///
/// 시나리오 (64초 반복):
///  - ai-pulse     : Claude Code (체크리스트 진행률, 테스트, 승인 요청 → 완료) + Codex (패치·테스트 → 완료)
///  - landing-page : Claude Code (빌드 실패 → 오류)
///  - data-pipeline: Codex (대기 → 승인 요청 → 완료)
public enum DemoScript {
    public static let loopLength: Double = 64

    public struct Item: Sendable {
        public let at: Double
        public let event: PulseEvent
    }

    public static let timeline: [Item] = build()

    private static func build() -> [Item] {
        var items: [Item] = []

        func add(
            _ at: Double, _ agent: AgentKind, _ sid: String, _ cwd: String, _ name: String,
            tool: String? = nil, toolId: String? = nil, detail: String? = nil, notification: String? = nil,
            todos: [TodoItem]? = nil, paths: [String]? = nil, model: String? = nil
        ) {
            let event = PulseEvent(
                agent: agent, ts: 0, event: name, sessionId: sid, cwd: cwd,
                tool: tool, toolUseId: toolId, detail: detail, paths: paths,
                notificationType: notification, todos: todos, model: model
            )
            items.append(Item(at: at, event: event))
        }

        func plan(_ done: Int, _ titles: [(String, String)]) -> [TodoItem] {
            titles.enumerated().map { index, pair in
                let status = index < done ? "completed" : (index == done ? "in_progress" : "pending")
                return TodoItem(content: pair.0, status: status, activeForm: pair.1)
            }
        }

        let pulse = "/Users/demo/Developer/ai-pulse"
        let landing = "/Users/demo/Developer/landing-page"
        let pipeline = "/Users/demo/Developer/data-pipeline"
        let steps = [
            ("요청 분석", "요청 분석 중"),
            ("설계 및 계획", "설계 및 계획 중"),
            ("코드 구현", "코드 구현 중"),
            ("테스트 및 검증", "테스트 및 검증 중"),
            ("정리 및 완료", "정리 중"),
        ]

        // Claude Code · ai-pulse
        let a = "demo-claude-pulse"
        add(0, .claude, a, pulse, "SessionStart", detail: "startup", model: "claude-opus-5-5")
        add(1, .claude, a, pulse, "UserPromptSubmit", detail: "앱 컴포넌트 구현")
        add(3, .claude, a, pulse, "PreToolUse", tool: "TodoWrite", todos: plan(0, steps))
        add(5, .claude, a, pulse, "PreToolUse", tool: "Read", detail: "Sources/AIPulse/PopoverView.swift")
        add(7, .claude, a, pulse, "PreToolUse", tool: "TodoWrite", todos: plan(1, steps))
        add(8, .claude, a, pulse, "PreToolUse", tool: "Edit", detail: "Sources/AIPulse/PopoverView.swift", paths: ["Sources/AIPulse/PopoverView.swift"])
        add(10, .claude, a, pulse, "PostToolUse", tool: "Edit", paths: ["Sources/AIPulse/PopoverView.swift"])
        add(12, .claude, a, pulse, "PreToolUse", tool: "TodoWrite", todos: plan(2, steps))
        add(14, .claude, a, pulse, "PreToolUse", tool: "Write", detail: "Sources/AIPulse/SessionRow.swift", paths: ["Sources/AIPulse/SessionRow.swift"])
        add(17, .claude, a, pulse, "PostToolUse", tool: "Write", paths: ["Sources/AIPulse/SessionRow.swift"])
        add(19, .claude, a, pulse, "PreToolUse", tool: "TodoWrite", todos: plan(3, steps))
        add(20, .claude, a, pulse, "PreToolUse", tool: "Bash", toolId: "t-a1", detail: "swift test --filter SessionReducerTests")
        add(27, .claude, a, pulse, "PostToolUse", tool: "Bash", toolId: "t-a1")
        add(29, .claude, a, pulse, "PreToolUse", tool: "TodoWrite", todos: plan(4, steps))
        add(31, .claude, a, pulse, "PermissionRequest", tool: "Bash", detail: "git push origin feature/popover")
        add(31.2, .claude, a, pulse, "Notification", detail: "Claude needs your permission to use Bash", notification: "permission_prompt")
        add(42, .claude, a, pulse, "PostToolUse", tool: "Bash")
        add(44, .claude, a, pulse, "PreToolUse", tool: "TodoWrite", todos: plan(5, steps))
        add(46, .claude, a, pulse, "Stop", detail: "팝오버와 세션 목록 UI 구현을 마쳤습니다. 테스트 12개 통과.")

        // Codex · ai-pulse (같은 프로젝트의 두 번째 세션)
        let b = "demo-codex-pulse"
        add(2, .codex, b, pulse, "SessionStart", detail: "startup")
        add(4, .codex, b, pulse, "UserPromptSubmit", detail: "이벤트 테일러 성능 개선")
        add(6, .codex, b, pulse, "PreToolUse", tool: "Bash", detail: "rg -n \"readNew\" Sources")
        add(11, .codex, b, pulse, "PreToolUse", tool: "apply_patch", detail: "EventLog.swift", paths: ["Sources/AIPulseCore/EventLog.swift"])
        add(13, .codex, b, pulse, "PostToolUse", tool: "apply_patch", paths: ["Sources/AIPulseCore/EventLog.swift"])
        add(21, .codex, b, pulse, "PreToolUse", tool: "Bash", toolId: "t-b1", detail: "swift test")
        add(28, .codex, b, pulse, "PostToolUse", tool: "Bash", toolId: "t-b1")
        add(30, .codex, b, pulse, "PreToolUse", tool: "apply_patch", detail: "EventLogTests.swift", paths: ["Tests/AIPulseCoreTests/EventLogTests.swift"])
        add(33, .codex, b, pulse, "PostToolUse", tool: "apply_patch", paths: ["Tests/AIPulseCoreTests/EventLogTests.swift"])
        add(38, .codex, b, pulse, "Stop", detail: "readNew 호출당 파일 열기를 1회로 줄였습니다.")

        // Claude Code · landing-page (오류 시나리오)
        let c = "demo-claude-landing"
        add(0, .claude, c, landing, "SessionStart", detail: "startup", model: "claude-sonnet-5-5")
        add(5, .claude, c, landing, "UserPromptSubmit", detail: "히어로 섹션 반응형 레이아웃 수정")
        add(7, .claude, c, landing, "PreToolUse", tool: "Grep", detail: "hero")
        add(12, .claude, c, landing, "PreToolUse", tool: "Edit", detail: "src/components/Hero.tsx", paths: ["src/components/Hero.tsx"])
        add(14, .claude, c, landing, "PostToolUse", tool: "Edit", paths: ["src/components/Hero.tsx"])
        add(18, .claude, c, landing, "PreToolUse", tool: "Bash", toolId: "t-c1", detail: "npm run build")
        add(25, .claude, c, landing, "PostToolUseFailure", tool: "Bash", toolId: "t-c1", detail: "Type error: Property 'size' does not exist")
        add(34, .claude, c, landing, "StopFailure", detail: "API 요청 한도 초과 (rate_limit)")

        // Codex · data-pipeline (대기 → 승인 → 완료)
        let d = "demo-codex-pipeline"
        add(0, .codex, d, pipeline, "SessionStart", detail: "startup")
        add(26, .codex, d, pipeline, "UserPromptSubmit", detail: "오래된 파티션 정리 스크립트 실행")
        add(28, .codex, d, pipeline, "PreToolUse", tool: "Bash", detail: "ls data/partitions | head")
        add(32, .codex, d, pipeline, "PermissionRequest", tool: "Bash", detail: "python scripts/cleanup.py --apply")
        add(50, .codex, d, pipeline, "PostToolUse", tool: "Bash")
        add(56, .codex, d, pipeline, "Stop", detail: "파티션 14개를 정리했습니다.")

        return items.sorted { $0.at < $1.at }
    }
}

/// DemoScript 를 실시간으로 재생한다.
public final class DemoScenario {
    private var loopStart: Date?
    private var lastOffset: Double = -1
    /// 마지막 advance 에서 루프가 처음부터 다시 시작했는지
    public private(set) var didReset = false

    public init() {}

    public func reset() {
        loopStart = nil
        lastOffset = -1
    }

    /// now 까지 도래한 이벤트를 반환한다.
    public func advance(now: Date) -> [PulseEvent] {
        didReset = false
        if loopStart == nil {
            loopStart = now
            lastOffset = -1
            didReset = true
        }
        var offset = now.timeIntervalSince(loopStart!)
        if offset >= DemoScript.loopLength || offset < 0 {
            loopStart = now
            offset = 0
            lastOffset = -1
            didReset = true
        }
        let base = loopStart!.timeIntervalSince1970
        let due = DemoScript.timeline.filter { $0.at > lastOffset && $0.at <= offset }
        lastOffset = offset
        return due.map { item in
            var event = item.event
            event.ts = base + item.at
            return event
        }
    }

    /// 스크립트를 offset 초 시점까지 재생한 스냅샷 (설정 화면 미리보기용)
    public static func snapshot(at offset: Double, now: Date = Date()) -> [String: AgentSession] {
        var sessions: [String: AgentSession] = [:]
        let base = now.timeIntervalSince1970 - offset
        for item in DemoScript.timeline where item.at <= offset {
            var event = item.event
            event.ts = base + item.at
            SessionReducer.apply(event, to: &sessions)
        }
        return sessions
    }
}
