import SwiftUI
import AppKit
import AIPulseCore

/// 메뉴바 아이콘을 눌렀을 때 펼쳐지는 컴팩트 패널 (목업 레이아웃)
///
///  ┌ 헤더: 캐릭터 타일 · AI Pulse · 에이전트/프로젝트 · [터미널로 이동] [알림 끄기]
///  ├ (세션이 2개 이상이면) 세션 목록 — 승인 대기가 항상 맨 위
///  ├ 상세 카드: 요청 제목 · 큰 진행률 · 진행 바 · 단계 목록 · 승인 요청 · 통계
///  └ 하단: 상태 칩 · 경과/예상 시간 · 더보기 메뉴
struct PopoverView: View {
    var body: some View {
        ThemedContainer {
            PopoverContent()
        }
    }
}

private struct PopoverContent: View {
    @Environment(PulseStore.self) private var store
    @Environment(\.pulseTheme) private var theme
    @AppStorage(Prefs.dockSize) private var dockSize: DockSize = .regular
    @AppStorage(Prefs.display) private var options = DisplayOptions()
    @State private var selectedKey: String?

    var body: some View {
        let ordered = store.orderedSessions
        let selected = ordered.first(where: { $0.key == selectedKey }) ?? ordered.first

        VStack(alignment: .leading, spacing: 10) {
            header(selected: selected, count: ordered.count)

            if ordered.count > 1 {
                SessionSwitcher(
                    sessions: ordered,
                    selectedKey: selected?.key,
                    options: options,
                    projectName: { store.projectName(for: $0) },
                    onSelect: { selectedKey = $0.key }
                )
            }

            if let selected {
                SessionDetailCard(session: selected, options: options)
                    .id(selected.key)
            } else {
                emptyState
            }

            footer(selected: selected)
        }
        .padding(12)
        .frame(width: dockSize.width + 20)
        .background(ThemePanelBackground())
        .animation(.easeInOut(duration: 0.2), value: ordered.map(\.key))
    }

    // MARK: Header

    private func header(selected: AgentSession?, count: Int) -> some View {
        HStack(spacing: 10) {
            StatusGlyph(state: store.aggregateState ?? .idle, size: 24, animated: options.character)
                .frame(width: 40, height: 40)
                .glassCard(radius: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text("AI Pulse")
                    .font(.system(size: 15, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.primaryText)
                HStack(spacing: 5) {
                    Circle()
                        .fill(theme.color(for: selected?.state ?? .idle))
                        .frame(width: 6, height: 6)
                    Text(subtitle(selected: selected, count: count))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if let selected {
                CircleIconButton(symbol: "arrow.up.right.square", help: "세션이 실행 중인 터미널로 이동") {
                    if !TerminalJumper.focus(selected) { TerminalJumper.reveal(path: selected.cwd) }
                }
                CircleIconButton(
                    symbol: store.isMuted(selected) ? "bell.slash" : "bell",
                    help: store.isMuted(selected) ? "이 세션 알림 켜기" : "이 세션 알림 끄기"
                ) {
                    store.toggleMute(selected)
                }
            }
        }
    }

    private func subtitle(selected: AgentSession?, count: Int) -> String {
        guard let selected else { return store.demoMode ? "데모 모드" : "대기 중" }
        var parts = [selected.agent.displayName]
        if options.projectName { parts.append(store.projectName(for: selected)) }
        if count > 1 { parts.append("세션 \(count)개") }
        if store.demoMode { parts.append("데모") }
        return parts.joined(separator: " · ")
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme.secondaryText)
            Text("모니터링 중인 세션이 없습니다")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.primaryText)
            Text(store.hookStatus.any
                 ? "Claude Code나 Codex를 새로 실행하면 여기에 나타납니다."
                 : "Claude Code 또는 Codex에 AI Pulse를 연결하면 작업 상태가 여기에 표시됩니다.")
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
            if !store.hookStatus.any {
                HStack(spacing: 8) {
                    Button("연결 설정") { showSettings() }
                    Button("데모 보기") { store.setDemoMode(true) }
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: Footer

    private func footer(selected: AgentSession?) -> some View {
        HStack(spacing: 6) {
            if let selected {
                Chip(text: chipLabel(selected.state), symbol: chipSymbol(selected.state), tint: theme.color(for: selected.state))
                if options.eta, let eta = selected.estimatedRemaining(at: Date()) {
                    Chip(text: "예상 완료 \(DurationFormatter.approx(eta))")
                } else if options.elapsed {
                    ElapsedChip(session: selected)
                }
            }
            Spacer(minLength: 4)
            moreMenu(selected: selected)
        }
    }

    private func chipLabel(_ state: ActivityState) -> String {
        switch state {
        case .thinking, .writing, .testing: return "실행 중"
        default: return state.label
        }
    }

    private func chipSymbol(_ state: ActivityState) -> String {
        switch state {
        case .thinking, .writing, .testing: return "bolt.fill"
        case .awaitingApproval: return "hand.raised.fill"
        case .done: return "checkmark"
        case .error: return "exclamationmark.triangle.fill"
        case .idle: return "moon.fill"
        }
    }

    private func moreMenu(selected: AgentSession?) -> some View {
        Menu {
            if let selected {
                Button("Finder에서 보기") { TerminalJumper.reveal(path: selected.cwd) }
                Button("경로 복사") { TerminalJumper.copy(selected.cwd) }
                Button("목록에서 제거") {
                    store.dismiss(selected)
                    selectedKey = nil
                }
                Divider()
            }
            Toggle("데모 모드", isOn: Binding(get: { store.demoMode }, set: { store.setDemoMode($0) }))
            Button("설정…") { showSettings() }
            Divider()
            Button("AI Pulse 종료") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.primaryText.opacity(0.9))
                .frame(width: 30, height: 30)
                .background(Circle().fill(theme.cardFill))
                .overlay(Circle().strokeBorder(theme.cardStroke.opacity(0.8), lineWidth: 1))
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func showSettings() {
        StatusBarController.shared.showSettings()
    }
}
