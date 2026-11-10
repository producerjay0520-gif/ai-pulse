import Foundation
import AIPulseCore

/// ~/.claude/settings.json 과 ~/.codex/hooks.json 에 AI Pulse 훅을 등록/제거한다.
/// - 다른 키와 다른 훅은 건드리지 않는다.
/// - 수정 전 원본을 `<파일>.aipulse-backup` 으로 복사한다.
/// - 다시 실행하면 기존 AI Pulse 항목을 지우고 새로 넣는다 (경로가 바뀌어도 안전).
enum Installer {
    static let marker = "aipulse-hook"

    struct Target {
        let name: String
        let agent: String
        let file: URL
        let events: [String]
        /// matcher 를 지정할 이벤트 (툴 이벤트)
        let matcherEvents: Set<String>
        /// timeout 을 짧게 두거나 생략해야 하는 이벤트
        let shortBudgetEvents: Set<String>
        let note: String?
    }

    /// AIPULSE_TEST_HOME 으로 바꿔서 실제 설정을 건드리지 않고 테스트할 수 있다
    static var home: URL {
        if let override = ProcessInfo.processInfo.environment["AIPULSE_TEST_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
    }

    static var claude: Target {
        Target(
            name: "Claude Code",
            agent: "claude",
            file: home.appendingPathComponent(".claude/settings.json"),
            events: [
                "SessionStart", "SessionEnd", "UserPromptSubmit",
                "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest",
                "Notification", "Stop", "StopFailure",
                "SubagentStart", "SubagentStop", "TaskCreated", "TaskCompleted", "PreCompact",
            ],
            matcherEvents: ["PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest"],
            shortBudgetEvents: ["SessionEnd"],
            note: "새로 시작하는 Claude Code 세션부터 적용됩니다. 실행 중인 세션은 /hooks 에서 확인하거나 재시작하세요."
        )
    }

    static var codex: Target {
        Target(
            name: "Codex",
            agent: "codex",
            file: home.appendingPathComponent(".codex/hooks.json"),
            events: [
                "SessionStart", "SessionEnd", "UserPromptSubmit",
                "PreToolUse", "PermissionRequest", "PostToolUse",
                "Stop", "Interrupt", "SubagentStart", "SubagentStop", "PreCompact",
            ],
            matcherEvents: [],
            shortBudgetEvents: ["SessionEnd", "Interrupt"],
            note: "Codex 는 새 훅을 신뢰해야 실행합니다. Codex 를 실행한 뒤 /hooks 에서 AI Pulse 훅을 신뢰(trust)하세요."
        )
    }

    static var selfPath: String {
        let raw = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
        return URL(fileURLWithPath: raw).resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func targets(for name: String) -> [Target]? {
        switch name {
        case "all": return [claude, codex]
        case "claude": return [claude]
        case "codex": return [codex]
        default: return nil
        }
    }

    static func run(install: Bool, target: String) -> Int32 {
        guard let list = targets(for: target) else {
            print("알 수 없는 대상: \(target) (claude | codex | all)")
            return 1
        }
        var status: Int32 = 0
        for t in list {
            if update(t, install: install) != 0 { status = 1 }
        }
        return status
    }

    static func update(_ t: Target, install: Bool) -> Int32 {
        let fm = FileManager.default
        var root: [String: Any] = [:]

        if fm.fileExists(atPath: t.file.path) {
            guard let data = try? Data(contentsOf: t.file) else {
                print("✗ \(t.name): \(t.file.path) 을 읽을 수 없습니다.")
                return 1
            }
            if !data.isEmpty {
                guard let object = try? JSONSerialization.jsonObject(with: data),
                      let dict = object as? [String: Any] else {
                    print("✗ \(t.name): \(t.file.path) 이 올바른 JSON 이 아니어서 수정하지 않았습니다.")
                    return 1
                }
                root = dict
            }
            let backup = URL(fileURLWithPath: t.file.path + ".aipulse-backup")
            try? fm.removeItem(at: backup)
            do {
                try fm.copyItem(at: t.file, to: backup)
            } catch {
                print("✗ \(t.name): 백업을 만들지 못해 수정하지 않았습니다 (\(error.localizedDescription)).")
                return 1
            }
        } else if !install {
            print("• \(t.name): 설정 파일이 없어 제거할 항목이 없습니다.")
            return 0
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]

        // 1) 기존 AI Pulse 핸들러 제거
        var removed = 0
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            var kept: [[String: Any]] = []
            for group in groups {
                guard let handlers = group["hooks"] as? [[String: Any]] else {
                    kept.append(group)
                    continue
                }
                let others = handlers.filter { !((($0["command"] as? String) ?? "").contains(marker)) }
                removed += handlers.count - others.count
                if others.isEmpty && !handlers.isEmpty { continue }
                var g = group
                g["hooks"] = others
                kept.append(g)
            }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }

        // 2) 새 핸들러 추가
        if install {
            let commandLine = "\(shellQuote(selfPath)) \(t.agent)"
            for event in t.events {
                var handler: [String: Any] = ["type": "command", "command": commandLine]
                if !t.shortBudgetEvents.contains(event) { handler["timeout"] = 5 }
                var group: [String: Any] = ["hooks": [handler]]
                if t.matcherEvents.contains(event) { group["matcher"] = "*" }
                var groups = hooks[event] as? [[String: Any]] ?? []
                groups.append(group)
                hooks[event] = groups
            }
        }

        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }

        do {
            try fm.createDirectory(at: t.file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes])
            try data.write(to: t.file, options: .atomic)
        } catch {
            print("✗ \(t.name): 저장 실패 (\(error.localizedDescription))")
            return 1
        }

        if install {
            print("✓ \(t.name): \(t.events.count)개 이벤트 훅을 \(t.file.path) 에 등록했습니다.")
            if let note = t.note { print("  \(note)") }
        } else {
            print("✓ \(t.name): AI Pulse 훅 \(removed)개를 제거했습니다.")
        }
        return 0
    }

    static func isInstalled(_ t: Target) -> Bool {
        guard let text = try? String(contentsOf: t.file, encoding: .utf8) else { return false }
        return text.contains(marker)
    }

    static func printStatus() {
        for t in [claude, codex] {
            print("\(isInstalled(t) ? "✓" : "–") \(t.name): \(t.file.path)")
        }
        print("이벤트 로그: \(PulsePaths.eventsFile.path)")
        print("훅 실행 파일: \(selfPath)")
    }
}
