import SwiftUI
import AIPulseCore

/// 첫 실행 안내: 무엇을 하는 앱인지 → 연결 → 메뉴바 위치
struct OnboardingView: View {
    let onFinish: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ThemedContainer {
                OnboardingHeader()
            }
            ViewSettingsTab()
                .frame(height: 430)
            HStack {
                Text("연결은 나중에 설정 → 연결 · 일반 에서 언제든 바꿀 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("시작하기", action: onFinish)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
            .padding(16)
        }
        .frame(width: 600)
    }
}

private struct OnboardingHeader: View {
    @Environment(\.pulseTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            StatusGlyph(state: .writing, size: 34)
                .frame(width: 56, height: 56)
                .glassCard(radius: 16)
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Pulse")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text("Claude Code · Codex · Claude 앱의 작업 상태를 메뉴바에서 한눈에 봅니다.\n승인이 필요하거나 작업이 끝나면 알려 드려요.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
        }
        .padding(20)
        .background(ThemePanelBackground())
    }
}
