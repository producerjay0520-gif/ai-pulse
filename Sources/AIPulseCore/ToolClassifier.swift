import Foundation

/// 툴 이름과 명령어로 현재 작업 단계를 추정한다.
public enum ToolCategory: Equatable, Sendable {
    case plan      // TodoWrite, update_plan
    case write     // Edit, Write, MultiEdit, apply_patch ...
    case test      // 테스트 명령 실행
    case command   // 그 밖의 셸 명령
    case read      // Read, Grep, Glob, WebFetch ...
    case delegate  // 서브에이전트 호출 (Task / Agent)
    case other
}

public enum ToolClassifier {

    static let planTools: Set<String> = ["todowrite", "update_plan", "taskcreate", "taskupdate"]
    static let writeTools: Set<String> = ["edit", "write", "multiedit", "notebookedit", "apply_patch", "applypatch", "str_replace_editor"]
    static let shellTools: Set<String> = ["bash", "shell", "local_shell", "exec_command", "unified_exec", "powershell", "container.exec"]
    static let readTools: Set<String> = ["read", "grep", "glob", "ls", "webfetch", "websearch", "notebookread", "view_image", "web_search"]
    static let delegateTools: Set<String> = ["task", "agent"]

    public static func classify(tool: String, detail: String?) -> ToolCategory {
        let t = tool.lowercased()
        if planTools.contains(t) { return .plan }
        if writeTools.contains(t) || t.contains("patch") { return .write }
        if shellTools.contains(t) || t.hasSuffix("shell") || t.hasSuffix("exec") {
            return isTestCommand(detail) ? .test : .command
        }
        if readTools.contains(t) { return .read }
        if delegateTools.contains(t) { return .delegate }
        return .other
    }

    private static let testRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(^|[\s;&|/(])(test|tests|pytest|jest|vitest|rspec|phpunit|mocha|ctest|xctest|playwright)([\s;&|):]|$)"#,
        options: [.caseInsensitive]
    )

    public static func isTestCommand(_ command: String?) -> Bool {
        guard let command, !command.isEmpty else { return false }
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        // 셸 내장 `test -f foo` 는 테스트 실행이 아니다
        if trimmed.hasPrefix("test ") || trimmed.hasPrefix("[ ") { return false }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return testRegex?.firstMatch(in: trimmed, options: [], range: range) != nil
    }
}
