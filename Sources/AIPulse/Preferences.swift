import Foundation
import AIPulseCore

/// UserDefaults 키. 모든 UI 설정은 @AppStorage 로 저장돼 재실행 후에도 유지된다 (UX 원칙 8).
enum Prefs {
    static let theme = "theme"
    static let appearance = "appearance"
    static let onboarded = "onboarded"
    static let dockSize = "dockSize"
    static let display = "displayOptions"
    static let demoMode = "demoMode"
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "시스템 설정"
        case .light: return "라이트"
        case .dark: return "다크"
        }
    }
}

enum DockSize: String, CaseIterable, Identifiable {
    case compact, regular, expanded
    var id: String { rawValue }
    var title: String {
        switch self {
        case .compact: return "컴팩트"
        case .regular: return "기본"
        case .expanded: return "확장"
        }
    }
    /// 인수인계서 권장 팝업 너비 300~340pt
    var width: CGFloat {
        switch self {
        case .compact: return 300
        case .regular: return 320
        case .expanded: return 340
        }
    }
}

/// 인터페이스 탭의 표시 항목 체크박스. 하나의 문자열로 AppStorage 에 저장한다.
struct DisplayOptions: Equatable, RawRepresentable {
    var projectName = true
    var agent = true
    var progress = true
    var step = true
    var elapsed = false
    var eta = false
    var files = false
    var tests = false
    var approval = true
    var notifyCompletion = true
    var character = true

    static let fields: [(key: String, path: WritableKeyPath<DisplayOptions, Bool>, title: String)] = [
        ("projectName", \.projectName, "프로젝트 이름"),
        ("agent", \.agent, "AI 모델 / 에이전트"),
        ("progress", \.progress, "진행률"),
        ("step", \.step, "현재 작업 단계"),
        ("elapsed", \.elapsed, "경과 시간"),
        ("eta", \.eta, "예상 완료 시간"),
        ("files", \.files, "파일 수정 수"),
        ("tests", \.tests, "테스트 현황"),
        ("approval", \.approval, "승인 요청"),
        ("notifyCompletion", \.notifyCompletion, "완료 알림"),
        ("character", \.character, "캐릭터 애니메이션"),
    ]

    init() {}

    init?(rawValue: String) {
        self.init()
        for part in rawValue.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2,
                  let field = Self.fields.first(where: { $0.key == String(pair[0]) }) else { continue }
            self[keyPath: field.path] = pair[1] == "1"
        }
    }

    var rawValue: String {
        Self.fields.map { "\($0.key)=\(self[keyPath: $0.path] ? 1 : 0)" }.joined(separator: ";")
    }

    // 프리셋
    static let standard = DisplayOptions()

    static var focus: DisplayOptions {
        var o = DisplayOptions()
        o.agent = false
        o.step = false
        return o
    }

    static var developer: DisplayOptions {
        var o = DisplayOptions()
        for field in fields { o[keyPath: field.path] = true }
        return o
    }

    /// 앱 레이어(알림 등)에서 현재 값을 읽을 때
    static var current: DisplayOptions {
        guard let raw = UserDefaults.standard.string(forKey: Prefs.display) else { return DisplayOptions() }
        return DisplayOptions(rawValue: raw) ?? DisplayOptions()
    }
}

enum DisplayPreset: String, CaseIterable, Identifiable {
    case focus, standard, developer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .focus: return "집중 모드"
        case .standard: return "기본 모드"
        case .developer: return "개발자 모드"
        }
    }
    var subtitle: String {
        switch self {
        case .focus: return "이름·진행률·승인만"
        case .standard: return "권장 기본값"
        case .developer: return "모든 정보 표시"
        }
    }
    var options: DisplayOptions {
        switch self {
        case .focus: return .focus
        case .standard: return .standard
        case .developer: return .developer
        }
    }
}
