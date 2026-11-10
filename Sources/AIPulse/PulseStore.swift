import SwiftUI
import AppKit
import Observation
import AIPulseCore

/// 같은 프로젝트(저장소)에 속한 세션 묶음
struct ProjectGroup: Identifiable {
    let id: String          // 프로젝트 루트 경로
    let name: String
    let sessions: [AgentSession]

    var topState: ActivityState {
        sessions.map(\.state).max { $0.priority < $1.priority } ?? .idle
    }
}

/// 앱 전체 상태. 이벤트 로그를 0.5초마다 tail 해서 리듀서에 흘려보낸다.
@MainActor
@Observable
final class PulseStore {
    static let shared = PulseStore()

    private(set) var liveSessions: [String: AgentSession] = [:]
    private(set) var demoSessions: [String: AgentSession] = [:]
    private(set) var demoMode: Bool
    private(set) var hookStatus = HookStatus.check()
    /// 알림을 끈 세션
    private(set) var mutedKeys: Set<String> = []

    private let tailer = EventTailer(url: PulsePaths.eventsFile)
    private let demo = DemoScenario()
    private let resolver = ProjectResolver()
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    private let launchTime = Date().timeIntervalSince1970
    @ObservationIgnored private var tickCount = 0

    init() {
        demoMode = UserDefaults.standard.bool(forKey: Prefs.demoMode)
    }

    // MARK: - Lifecycle

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func setDemoMode(_ on: Bool) {
        demoMode = on
        UserDefaults.standard.set(on, forKey: Prefs.demoMode)
        demo.reset()
        demoSessions = [:]
    }

    func refreshHookStatus() {
        let status = HookStatus.check()
        if status != hookStatus { hookStatus = status }
    }

    private func tick() {
        let events = tailer.readNew()
        if !events.isEmpty {
            let ordered = events.enumerated()
                .sorted { ($0.element.ts, $0.offset) < ($1.element.ts, $1.offset) }
                .map(\.element)
            for event in ordered {
                let effects = SessionReducer.apply(event, to: &liveSessions)
                // 앱 시작 전에 일어난 일(로그 재생)로는 알림을 보내지 않는다
                if event.ts >= launchTime - 3 { handle(effects) }
            }
            tailer.compactIfNeeded()
        }

        if demoMode {
            let demoEvents = demo.advance(now: Date())
            if demo.didReset { demoSessions = [:] }
            for event in demoEvents {
                SessionReducer.apply(event, to: &demoSessions)
            }
        }

        tickCount += 1
        if tickCount % 20 == 0 {   // 10초마다
            prune()
            refreshHookStatus()
        }
    }

    /// 종료 후 30분 지난 세션, 12시간 이상 조용한 세션을 목록에서 제거
    private func prune() {
        let now = Date()
        let stale = liveSessions.filter { _, s in
            let quiet = now.timeIntervalSince(s.lastEventAt)
            return (s.isEnded && quiet > 30 * 60) || quiet > 12 * 3600
        }
        for key in stale.keys { liveSessions.removeValue(forKey: key) }
    }

    func toggleMute(_ session: AgentSession) {
        if mutedKeys.contains(session.key) { mutedKeys.remove(session.key) } else { mutedKeys.insert(session.key) }
    }

    func isMuted(_ session: AgentSession) -> Bool { mutedKeys.contains(session.key) }

    /// 정렬된 전체 세션 (프로젝트 우선순위 → 세션 우선순위)
    var orderedSessions: [AgentSession] { projects.flatMap(\.sessions) }

    func dismiss(_ session: AgentSession) {
        if demoMode {
            demoSessions.removeValue(forKey: session.key)
        } else {
            liveSessions.removeValue(forKey: session.key)
        }
    }

    // MARK: - Effects

    private func handle(_ effects: [PulseEffect]) {
        guard !effects.isEmpty else { return }
        let options = DisplayOptions.current
        for effect in effects {
            switch effect {
            case .completed(let key), .needsApproval(let key), .failed(let key):
                if mutedKeys.contains(key) { continue }
            }
            switch effect {
            case .completed(let key):
                guard options.notifyCompletion, let s = liveSessions[key] else { continue }
                Notifier.shared.post(
                    title: "\(projectName(for: s)) · 작업 완료",
                    body: s.lastMessage ?? "\(s.agent.displayName) 작업이 끝났습니다.",
                    sessionKey: key
                )
            case .needsApproval(let key):
                guard options.approval, let s = liveSessions[key] else { continue }
                Notifier.shared.post(
                    title: "\(projectName(for: s)) · 승인 필요",
                    body: "\(s.agent.displayName): \(s.step)",
                    sessionKey: key
                )
            case .failed(let key):
                guard let s = liveSessions[key] else { continue }
                Notifier.shared.post(
                    title: "\(projectName(for: s)) · 오류",
                    body: s.step,
                    sessionKey: key
                )
            }
        }
    }

    // MARK: - Derived

    var sessions: [AgentSession] {
        Array((demoMode ? demoSessions : liveSessions).values)
    }

    func session(forKey key: String) -> AgentSession? {
        liveSessions[key] ?? demoSessions[key]
    }

    func projectRoot(for session: AgentSession) -> String {
        resolver.root(for: session.cwd)
    }

    func projectName(for session: AgentSession) -> String {
        let root = projectRoot(for: session)
        let name = (root as NSString).lastPathComponent
        return name.isEmpty ? "알 수 없는 프로젝트" : name
    }

    /// 승인 대기 → 오류 → 진행 중 → 완료 → 대기 순, 같은 우선순위는 최근 활동 순
    var projects: [ProjectGroup] {
        let grouped = Dictionary(grouping: sessions) { projectRoot(for: $0) }
        let groups = grouped.map { root, items -> ProjectGroup in
            let sorted = items.sorted {
                if $0.state.priority != $1.state.priority { return $0.state.priority > $1.state.priority }
                return $0.lastEventAt > $1.lastEventAt
            }
            let name = (root as NSString).lastPathComponent
            return ProjectGroup(id: root, name: name.isEmpty ? "알 수 없는 프로젝트" : name, sessions: sorted)
        }
        return groups.sorted {
            if $0.topState.priority != $1.topState.priority { return $0.topState.priority > $1.topState.priority }
            let l = $0.sessions.map(\.lastEventAt).max() ?? .distantPast
            let r = $1.sessions.map(\.lastEventAt).max() ?? .distantPast
            return l > r
        }
    }

    var pendingApprovals: Int { sessions.filter { $0.state == .awaitingApproval }.count }
    var activeCount: Int { sessions.filter { $0.state.isActive && $0.state != .awaitingApproval }.count }
    var errorCount: Int { sessions.filter { $0.state == .error }.count }
    var doneCount: Int { sessions.filter { $0.state == .done }.count }

    /// 메뉴바 아이콘에 쓸 대표 상태. 완료는 최근 10분 이내만 강조한다.
    var aggregateState: ActivityState? {
        let now = Date()
        let relevant = sessions.filter { s in
            if s.state == .done || s.state == .error {
                return now.timeIntervalSince(s.lastEventAt) < 10 * 60
            }
            return !s.isEnded
        }
        return relevant.map(\.state).max { $0.priority < $1.priority }
    }
}

/// cwd → git 루트 (없으면 cwd 그대로). 결과는 캐시한다.
final class ProjectResolver {
    private var cache: [String: String] = [:]

    func root(for cwd: String) -> String {
        if cwd.isEmpty { return "" }
        if cwd.hasPrefix("claude://") { return cwd }   // Claude 앱 보고: 파일 경로가 아님
        if let hit = cache[cwd] { return hit }
        var url = URL(fileURLWithPath: cwd).standardizedFileURL
        var result = url.path
        let fm = FileManager.default
        while url.path != "/" && !url.path.isEmpty {
            if fm.fileExists(atPath: url.appendingPathComponent(".git").path) {
                result = url.path
                break
            }
            url.deleteLastPathComponent()
        }
        cache[cwd] = result
        return result
    }
}

/// 훅 등록 여부 (설정 파일에 aipulse-hook 문자열이 있는지만 확인)
struct HookStatus: Equatable {
    var claude: Bool
    var codex: Bool
    var claudeApp: Bool

    var any: Bool { claude || codex || claudeApp }

    static func check() -> HookStatus {
        func mentionsHook(_ relativePath: String) -> Bool {
            let path = (NSHomeDirectory() as NSString).appendingPathComponent(relativePath)
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
            return text.contains("aipulse-hook")
        }
        return HookStatus(
            claude: mentionsHook(".claude/settings.json"),
            codex: mentionsHook(".codex/hooks.json") || mentionsHook(".codex/config.toml"),
            claudeApp: ClaudeAppConnector.isInstalled
        )
    }
}

/// 앱 번들 안의 aipulse-hook 을 실행해 훅을 등록/제거한다.
enum HookInstaller {
    static var hookBinaryURL: URL? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "aipulse-hook"),
           FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }
        // swift run 으로 실행한 경우: 같은 빌드 폴더
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let sibling = exe.deletingLastPathComponent().appendingPathComponent("aipulse-hook")
        return FileManager.default.isExecutableFile(atPath: sibling.path) ? sibling : nil
    }

    static func run(_ arguments: [String]) async -> (ok: Bool, output: String) {
        guard let url = hookBinaryURL else {
            return (false, "aipulse-hook 실행 파일을 찾지 못했습니다. Scripts/build-app.sh 로 앱을 빌드하세요.")
        }
        return await Task.detached { () -> (ok: Bool, output: String) in
            let process = Process()
            process.executableURL = url
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                return (false, error.localizedDescription)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus == 0, String(decoding: data, as: UTF8.self))
        }.value
    }
}

/// Claude 데스크톱 앱에 AI Pulse 확장(.mcpb)을 설치한다.
/// 확장은 앱 번들 Resources 에 들어 있고, Claude 앱으로 열면 Claude 가 설치 확인 창을 띄운다.
enum ClaudeAppConnector {
    static let bundleIdentifier = "com.anthropic.claudefordesktop"

    static var extensionURL: URL? {
        Bundle.main.url(forResource: "AIPulse", withExtension: "mcpb")
    }

    static var claudeAppURL: URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) { return url }
        for path in ["/Applications/Claude.app", NSHomeDirectory() + "/Applications/Claude.app"]
        where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// Claude 앱 설정 폴더에 ai-pulse 확장이 풀려 있는지 (설치 경로 이름은 버전에 따라 다를 수 있어 넓게 찾는다)
    static var isInstalled: Bool {
        let base = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/Claude")
        let candidates = ["Claude Extensions", "Extensions"]
        for folder in candidates {
            let dir = (base as NSString).appendingPathComponent(folder)
            if let items = try? FileManager.default.contentsOfDirectory(atPath: dir),
               items.contains(where: { $0.lowercased().contains("ai-pulse") }) {
                return true
            }
        }
        // 수동 설정(claude_desktop_config.json)으로 연결한 경우
        let config = (base as NSString).appendingPathComponent("claude_desktop_config.json")
        if let text = try? String(contentsOfFile: config, encoding: .utf8), text.contains("aipulse-mcp") {
            return true
        }
        return false
    }

    /// 결과 메시지를 돌려준다.
    @MainActor
    static func install() -> String {
        guard let ext = extensionURL else {
            return "확장 파일(AIPulse.mcpb)을 찾지 못했습니다. Scripts/build-app.sh 로 만든 앱에서 다시 시도하세요."
        }
        guard let claude = claudeAppURL else {
            TerminalJumper.reveal(path: ext.path)
            return "Claude 데스크톱 앱을 찾지 못했습니다. Finder 에 표시된 AIPulse.mcpb 를 Claude 설정 → 확장 프로그램에 끌어다 놓으세요."
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([ext], withApplicationAt: claude, configuration: configuration) { _, _ in }
        return "Claude 앱에 설치 창이 열립니다. ‘설치’를 누른 뒤 새 대화부터 진행 상황이 표시됩니다."
    }
}
