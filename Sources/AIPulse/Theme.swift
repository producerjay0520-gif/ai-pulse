import SwiftUI
import AIPulseCore

enum ThemeKind: String, CaseIterable, Identifiable {
    case warmGlass, appleMinimal, retroPixel, neon, animal
    var id: String { rawValue }

    var title: String {
        switch self {
        case .warmGlass: return "Warm Glass"
        case .appleMinimal: return "Apple Minimal"
        case .retroPixel: return "Retro Pixel"
        case .neon: return "Neon"
        case .animal: return "Animal"
        }
    }

    var subtitle: String {
        switch self {
        case .warmGlass: return "따뜻한 반투명 유리 · 기본"
        case .appleMinimal: return "macOS 네이티브 · 절제된 색상"
        case .retroPixel: return "8비트 픽셀 · 계단식 모션"
        case .neon: return "사이버펑크 · 빛나는 진행 바"
        case .animal: return "귀여운 동물 · 상태별 표정"
        }
    }

    static let `default`: ThemeKind = .warmGlass
}

/// 테마는 색·소재·모션만 바꾸고, 레이아웃과 정보 구조는 공통이다 (UX 원칙 5).
struct ThemeStyle {
    let kind: ThemeKind
    var palette: [ActivityState: Color]
    var fontDesign: Font.Design = .default
    var cornerRadius: CGFloat = 14
    var glow: Bool = false

    // 패널 소재
    /// 패널 배경을 테마가 직접 그리는지 (false 면 시스템 머티리얼)
    var customPanel: Bool = false
    var panelGradient: [Color] = []
    /// 배경 뒤에서 번지는 빛 (색, 위치, 반지름 비율)
    var glows: [(Color, UnitPoint, CGFloat)] = []
    /// 패널 안 텍스트를 밝은 색으로 고정할지
    var forcesDark: Bool = false

    // 카드·텍스트
    var cardFill: Color = Color.primary.opacity(0.05)
    var cardStroke: Color = Color.primary.opacity(0.08)
    var highlightFill: Color = Color.primary.opacity(0.07)
    var trackColor: Color = Color.primary.opacity(0.08)
    var progressColors: [Color] = []
    var primaryText: Color = .primary
    var secondaryText: Color = .secondary

    func color(for state: ActivityState) -> Color { palette[state] ?? .secondary }

    var accent: Color { color(for: .thinking) }

    func progressFill(for state: ActivityState) -> [Color] {
        if state == .error || state == .awaitingApproval || progressColors.isEmpty {
            return [color(for: state), color(for: state)]
        }
        return progressColors
    }

    static func make(_ kind: ThemeKind, scheme: ColorScheme) -> ThemeStyle {
        let dark = scheme == .dark
        switch kind {
        case .warmGlass:
            var t = ThemeStyle(kind: kind, palette: [
                .idle: Color(hex: 0xD8CABD), .thinking: Color(hex: 0xF6C99A), .writing: Color(hex: 0xF4A77A),
                .testing: Color(hex: 0xEBD7A4), .awaitingApproval: Color(hex: 0xFF9A55),
                .done: Color(hex: 0xF3E3CF), .error: Color(hex: 0xF27A6B),
            ])
            t.customPanel = true
            t.forcesDark = true
            t.cornerRadius = 18
            t.panelGradient = dark
                ? [Color(hex: 0x5A4E47), Color(hex: 0x3A302B), Color(hex: 0x2A221E)]
                : [Color(hex: 0x9C918A), Color(hex: 0x7B6F68), Color(hex: 0x5B4F48)]
            t.glows = [
                (Color(hex: 0xF08A4B).opacity(dark ? 0.55 : 0.65), UnitPoint(x: 0.1, y: 1.0), 0.9),
                (Color(hex: 0xF6C48A).opacity(dark ? 0.30 : 0.40), UnitPoint(x: 0.95, y: 0.15), 0.6),
            ]
            t.cardFill = Color.white.opacity(0.09)
            t.cardStroke = Color.white.opacity(0.22)
            t.highlightFill = Color.white.opacity(0.14)
            t.trackColor = Color.white.opacity(0.14)
            t.progressColors = [Color(hex: 0xF9DDBB), Color(hex: 0xF0965F)]
            t.primaryText = Color.white.opacity(0.96)
            t.secondaryText = Color.white.opacity(0.62)
            return t

        case .appleMinimal:
            var t = ThemeStyle(kind: kind, palette: [
                .idle: .gray, .thinking: .blue, .writing: .indigo, .testing: .teal,
                .awaitingApproval: .orange, .done: .green, .error: .red,
            ])
            t.cornerRadius = 10
            t.cardFill = Color.primary.opacity(dark ? 0.06 : 0.04)
            return t

        case .retroPixel:
            var t = ThemeStyle(kind: kind, palette: [
                .idle: Color(hex: 0x8B9BB4), .thinking: Color(hex: 0x3CBCFC), .writing: Color(hex: 0xB8F818),
                .testing: Color(hex: 0x00E8D8), .awaitingApproval: Color(hex: 0xF8B800),
                .done: Color(hex: 0x58D854), .error: Color(hex: 0xF83800),
            ])
            t.fontDesign = .monospaced
            t.cornerRadius = 2
            t.cardFill = Color.primary.opacity(dark ? 0.08 : 0.05)
            t.trackColor = Color.primary.opacity(0.12)
            return t

        case .neon:
            var t = ThemeStyle(kind: kind, palette: [
                .idle: Color(hex: 0x7A7AB8), .thinking: Color(hex: 0x7CF3E0), .writing: Color(hex: 0xC08CFF),
                .testing: Color(hex: 0x00FFA3), .awaitingApproval: Color(hex: 0xFF9F1C),
                .done: Color(hex: 0x7CF3E0), .error: Color(hex: 0xFF2E63),
            ])
            t.fontDesign = .rounded
            t.glow = true
            t.customPanel = true
            t.forcesDark = true
            t.panelGradient = [Color(hex: 0x24223A), Color(hex: 0x15141F)]
            t.glows = [(Color(hex: 0x8B5CF6).opacity(0.35), UnitPoint(x: 0.9, y: 0.0), 0.7)]
            t.cardFill = Color.white.opacity(0.05)
            t.cardStroke = Color.white.opacity(0.10)
            t.highlightFill = Color(hex: 0x6D5BD0).opacity(0.35)
            t.trackColor = Color.white.opacity(0.10)
            t.progressColors = [Color(hex: 0x7CF3E0), Color(hex: 0xB07CFF)]
            t.primaryText = .white
            t.secondaryText = Color.white.opacity(0.6)
            return t

        case .animal:
            var t = ThemeStyle(kind: kind, palette: [
                .idle: Color(hex: 0xB8A99A), .thinking: Color(hex: 0x7FB3D5), .writing: Color(hex: 0xC39BD3),
                .testing: Color(hex: 0x76D7C4), .awaitingApproval: Color(hex: 0xF5B041),
                .done: Color(hex: 0x82E0AA), .error: Color(hex: 0xEC7063),
            ])
            t.fontDesign = .rounded
            t.cornerRadius = 16
            t.cardFill = Color(hex: 0xF5B041).opacity(dark ? 0.07 : 0.06)
            return t
        }
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = ThemeStyle.make(.default, scheme: .dark)
}

extension EnvironmentValues {
    var pulseTheme: ThemeStyle {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// 현재 저장된 테마를 하위 뷰에 주입한다. forcesDark 테마는 하위 컨트롤도 다크 스킴으로 맞춘다.
struct ThemedContainer<Content: View>: View {
    @AppStorage(Prefs.theme) private var theme: ThemeKind = .default
    @Environment(\.colorScheme) private var scheme
    var override: ThemeKind?
    @ViewBuilder var content: () -> Content

    var body: some View {
        let style = ThemeStyle.make(override ?? theme, scheme: scheme)
        content()
            .environment(\.pulseTheme, style)
            .environment(\.colorScheme, style.forcesDark ? .dark : scheme)
    }
}

/// 테마 패널 배경: Warm Glass 는 반투명 그라데이션 + 번지는 주황 빛
struct ThemePanelBackground: View {
    @Environment(\.pulseTheme) private var theme

    var body: some View {
        if theme.customPanel {
            GeometryReader { geo in
                let side = max(geo.size.width, geo.size.height)
                ZStack {
                    LinearGradient(colors: theme.panelGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .opacity(0.92)
                    ForEach(theme.glows.indices, id: \.self) { i in
                        let glow = theme.glows[i]
                        Circle()
                            .fill(glow.0)
                            .frame(width: side * glow.2, height: side * glow.2)
                            .position(x: geo.size.width * glow.1.x, y: geo.size.height * glow.1.y)
                            .blur(radius: side * 0.18)
                    }
                }
            }
            .background(.ultraThinMaterial)
        } else {
            Rectangle().fill(.clear)
        }
    }
}

/// 유리 카드 (Warm Glass 기준: 반투명 채움 + 밝은 헤어라인)
struct GlassCard: ViewModifier {
    @Environment(\.pulseTheme) private var theme
    var radius: CGFloat?

    func body(content: Content) -> some View {
        let r = radius ?? theme.cornerRadius
        content
            .background(RoundedRectangle(cornerRadius: r, style: .continuous).fill(theme.cardFill))
            .overlay(
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [theme.cardStroke, theme.cardStroke.opacity(0.25)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            )
    }
}

extension View {
    func glassCard(radius: CGFloat? = nil) -> some View { modifier(GlassCard(radius: radius)) }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
