import AppKit
import UserNotifications
import AIPulseCore

/// macOS 알림. UserNotifications 는 .app 번들에서만 동작하므로 `swift run` 개발 실행에서는 조용히 건너뛴다.
@MainActor
final class Notifier {
    static let shared = Notifier()

    var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    func setup(delegate: UNUserNotificationCenterDelegate) {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(title: String, body: String, sessionKey: String) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["sessionKey": sessionKey]
        let request = UNNotificationRequest(
            identifier: "\(sessionKey)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}

/// 세션을 실행한 터미널(또는 에디터) 앱을 앞으로 가져온다.
/// 훅 프로세스가 상속받은 __CFBundleIdentifier / TERM_PROGRAM 으로 앱을 찾는다.
/// 특정 탭/창까지 선택하는 기능은 터미널별 스크립팅이 필요해 다음 단계 과제로 남긴다.
@MainActor
enum TerminalJumper {
    static let termProgramBundles: [String: String] = [
        "Apple_Terminal": "com.apple.Terminal",
        "iTerm.app": "com.googlecode.iterm2",
        "vscode": "com.microsoft.VSCode",
        "ghostty": "com.mitchellh.ghostty",
        "WezTerm": "com.github.wez.wezterm",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "zed": "dev.zed.Zed",
    ]

    @discardableResult
    static func focus(_ session: AgentSession) -> Bool {
        var candidates: [String] = []
        if let host = session.hostApp { candidates.append(host) }
        if let term = session.termProgram, let id = termProgramBundles[term] { candidates.append(id) }
        for id in candidates {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                app.activate(options: [.activateAllWindows])
                return true
            }
        }
        return false
    }

    static func reveal(path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

@MainActor
enum AppearanceController {
    static func apply(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    static func applySaved() {
        let raw = UserDefaults.standard.string(forKey: Prefs.appearance) ?? AppearanceMode.system.rawValue
        apply(AppearanceMode(rawValue: raw) ?? .system)
    }
}

enum DurationFormatter {
    static func short(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        if total < 60 { return "\(total)초" }
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func approx(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded(.up))
        if minutes <= 1 { return "1분 이내" }
        if minutes < 60 { return "약 \(minutes)분" }
        return "약 \(minutes / 60)시간 \(minutes % 60)분"
    }

    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "방금" }
        if seconds < 3600 { return "\(Int(seconds / 60))분 전" }
        return "\(Int(seconds / 3600))시간 전"
    }
}
