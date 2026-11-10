import SwiftUI
import AIPulseCore

// MARK: - 세션 상세 카드 (목업의 메인 카드)

struct SessionDetailCard: View {
    let session: AgentSession
    let options: DisplayOptions
    var interactive: Bool = true

    @Environment(\.pulseTheme) private var theme

    private var showsApproval: Bool { session.state == .awaitingApproval && options.approval }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow

            if options.progress {
                PulseProgressBar(value: session.progress, state: session.state)
            }

            if !session.todos.isEmpty {
                if session.state.isActive {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        StepList(session: session, now: context.date, showsTimes: options.elapsed || options.step)
                    }
                } else {
                    StepList(session: session, now: Date(), showsTimes: options.elapsed || options.step)
                }
            } else if options.step {
                ActivityLine(session: session)
            }

            if showsApproval {
                ApprovalCallout(session: session, interactive: interactive)
            }

            if hasStats {
                Rectangle().fill(theme.cardStroke.opacity(0.6)).frame(height: 1)
                statsRow
            }
        }
        .padding(14)
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .strokeBorder(showsApproval ? theme.color(for: .awaitingApproval).opacity(0.8) : .clear, lineWidth: 1.2)
        )
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.system(size: 15, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)
                if options.step && !session.todos.isEmpty {
                    Text(stepText)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 6)
            if options.progress, let progress = session.progress {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 30, weight: .light, design: theme.fontDesign))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient(colors: theme.progressFill(for: session.state),
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .contentTransition(.numericText())
            } else if options.character {
                StatusGlyph(state: session.state, size: 30)
            }
        }
    }

    private var stepText: String {
        let step = session.step
        if let range = step.range(of: " · "), step[..<range.lowerBound] == session.state.label {
            return String(step[range.upperBound...])
        }
        return step
    }

    private var hasStats: Bool { options.files || options.tests || (options.eta && eta != nil) }

    private var eta: TimeInterval? { session.estimatedRemaining(at: Date()) }

    private var statsRow: some View {
        HStack(spacing: 14) {
            if options.files {
                StatItem(symbol: "doc.text", value: "\(session.filesEdited.count)개", help: "수정한 파일")
            }
            if options.tests {
                StatItem(
                    symbol: "flask",
                    value: session.testsFailed > 0 ? "\(session.testsRun)회 · 실패 \(session.testsFailed)" : "\(session.testsRun)회",
                    help: "테스트 실행"
                )
            }
            if options.files || options.tests {
                StatItem(symbol: "terminal", value: "\(session.toolCalls)", help: "툴 호출")
            }
            Spacer(minLength: 0)
            if options.eta, let eta {
                Chip(text: "예상 \(DurationFormatter.approx(eta))")
                    .help("체크리스트 진행 속도로 계산한 추정치")
            }
        }
    }
}

// MARK: - 단계 목록

struct StepList: View {
    let session: AgentSession
    let now: Date
    let showsTimes: Bool

    @Environment(\.pulseTheme) private var theme

    private static let maxVisible = 6

    var body: some View {
        let todos = session.todos
        let current = todos.firstIndex(where: \.isInProgress) ?? todos.firstIndex(where: { !$0.isCompleted }) ?? max(0, todos.count - 1)
        let start = todos.count <= Self.maxVisible ? 0 : max(0, min(current - 2, todos.count - Self.maxVisible))
        let end = min(todos.count, start + Self.maxVisible)

        VStack(alignment: .leading, spacing: 0) {
            ForEach(start..<end, id: \.self) { index in
                StepRow(
                    item: todos[index],
                    isFirst: index == 0,
                    isLast: index == todos.count - 1,
                    trailing: trailing(for: todos[index])
                )
            }
            if todos.count > Self.maxVisible {
                Text("전체 \(todos.count)단계 중 \(start + 1)–\(end)")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.leading, 30)
                    .padding(.top, 2)
            }
        }
    }

    private func trailing(for item: TodoItem) -> String {
        let duration = showsTimes ? session.duration(of: item, at: now) : nil
        if item.isCompleted {
            return duration.map(DurationFormatter.short) ?? "완료"
        }
        if item.isInProgress {
            if let duration { return "진행 중 · \(DurationFormatter.short(duration))" }
            return "진행 중"
        }
        return "대기"
    }
}

struct StepRow: View {
    let item: TodoItem
    let isFirst: Bool
    let isLast: Bool
    let trailing: String

    @Environment(\.pulseTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 0) {
                connector.opacity(isFirst ? 0 : 1)
                StepMarker(item: item)
                connector.opacity(isLast ? 0 : 1)
            }
            .frame(width: 18)

            HStack {
                Text(item.isInProgress ? (item.activeForm ?? item.content) : item.content)
                    .font(.system(size: 12.5, weight: item.isInProgress ? .semibold : .regular, design: theme.fontDesign))
                    .foregroundStyle(item.isCompleted || item.isInProgress ? theme.primaryText : theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(trailing)
                    .font(.system(size: 10.5, design: theme.fontDesign))
                    .monospacedDigit()
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(item.isInProgress ? theme.highlightFill : .clear)
            )
        }
        .frame(height: 30)
    }

    private var connector: some View {
        Rectangle()
            .fill(theme.trackColor)
            .frame(width: 1.5)
            .frame(maxHeight: .infinity)
    }
}

struct StepMarker: View {
    let item: TodoItem
    @Environment(\.pulseTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let accent = theme.progressFill(for: .thinking).first ?? theme.accent
        ZStack {
            if item.isCompleted {
                Circle().fill(accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 8.5, weight: .heavy))
                    .foregroundStyle(Color.black.opacity(0.7))
            } else if item.isInProgress {
                Circle().strokeBorder(accent, lineWidth: 2)
                Circle()
                    .fill(accent.opacity(0.25))
                    .padding(4)
            } else {
                Circle().strokeBorder(theme.secondaryText.opacity(0.45), lineWidth: 1.5)
            }
        }
        .frame(width: 18, height: 18)
        .shadow(color: item.isInProgress && !reduceMotion ? accent.opacity(0.6) : .clear, radius: 4)
    }
}

/// 체크리스트가 없을 때 (Codex 등): 숫자 대신 현재 활동을 보여준다
struct ActivityLine: View {
    let session: AgentSession
    @Environment(\.pulseTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            StatusGlyph(state: session.state, size: 18)
            Text(session.step)
                .font(.system(size: 12, design: theme.fontDesign))
                .foregroundStyle(theme.primaryText.opacity(0.85))
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.highlightFill))
    }
}

struct ApprovalCallout: View {
    let session: AgentSession
    let interactive: Bool
    @Environment(\.pulseTheme) private var theme

    var body: some View {
        let color = theme.color(for: .awaitingApproval)
        Button {
            if interactive { TerminalJumper.focus(session) }
        } label: {
            HStack(spacing: 8) {
                StatusGlyph(state: .awaitingApproval, size: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text("터미널에서 승인이 필요합니다")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(color)
                    Text(session.step)
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if interactive {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(color)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.14)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 다중 세션 목록

struct SessionSwitcher: View {
    let sessions: [AgentSession]
    let selectedKey: String?
    let options: DisplayOptions
    let projectName: (AgentSession) -> String
    let onSelect: (AgentSession) -> Void

    @Environment(\.pulseTheme) private var theme
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(sessions) { session in
                    row(session)
                }
            }
            .padding(4)
            .background(GeometryReader { geo in
                Color.clear.preference(key: SwitcherHeightKey.self, value: geo.size.height)
            })
        }
        .scrollIndicators(.never)
        .frame(height: min(max(contentHeight, 34), 4 * 32 + 8))
        .onPreferenceChange(SwitcherHeightKey.self) { contentHeight = $0 }
        .glassCard(radius: theme.cornerRadius - 4)
    }

    private func row(_ session: AgentSession) -> some View {
        let selected = session.key == selectedKey
        let color = theme.color(for: session.state)
        return Button { onSelect(session) } label: {
            HStack(spacing: 7) {
                if options.character {
                    StatusGlyph(state: session.state, size: 15)
                } else {
                    Circle().fill(color).frame(width: 7, height: 7)
                }
                if options.projectName {
                    Text(projectName(session))
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                }
                if options.agent {
                    AgentBadge(agent: session.agent, model: session.model)
                }
                Spacer(minLength: 4)
                if options.progress, let p = session.progress, session.state.isActive {
                    Text("\(Int((p * 100).rounded()))%")
                        .font(.system(size: 11, design: theme.fontDesign))
                        .monospacedDigit()
                        .foregroundStyle(theme.secondaryText)
                }
                Text(session.state.label)
                    .font(.system(size: 10.5, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(color)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? theme.highlightFill : .clear)
            )
            .opacity(session.isEnded ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SwitcherHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - 작은 부품

struct AgentBadge: View {
    let agent: AgentKind
    var model: String?

    private var tint: Color {
        switch agent {
        case .claude: return Color(hex: 0xE58E6B)
        case .codex: return Color(hex: 0x5CC8A8)
        case .claudeApp: return Color(hex: 0xF2B38A)
        }
    }

    var body: some View {
        Text(agent.shortName)
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
            .help(model.map { "\(agent.displayName) · \($0)" } ?? agent.displayName)
    }
}

struct Chip: View {
    let text: String
    var symbol: String?
    var tint: Color?

    @Environment(\.pulseTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint ?? theme.primaryText)
            }
            Text(text)
                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                .monospacedDigit()
                .foregroundStyle(theme.primaryText.opacity(0.85))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(theme.cardFill))
        .overlay(Capsule().strokeBorder(theme.cardStroke.opacity(0.7), lineWidth: 1))
    }
}

struct StatItem: View {
    let symbol: String
    let value: String
    let help: String
    @Environment(\.pulseTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 12))
            Text(value)
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .monospacedDigit()
        }
        .foregroundStyle(theme.primaryText.opacity(0.85))
        .help(help)
    }
}

/// 유리 원형 아이콘 버튼 (목업 우측 상단)
struct CircleIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @Environment(\.pulseTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.primaryText.opacity(0.9))
                .frame(width: 30, height: 30)
                .background(Circle().fill(hovering ? theme.highlightFill : theme.cardFill))
                .overlay(Circle().strokeBorder(theme.cardStroke.opacity(0.8), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct ElapsedChip: View {
    let session: AgentSession

    var body: some View {
        if session.state.isActive {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                chip(session.elapsed(at: context.date))
            }
        } else {
            chip(session.elapsed(at: Date()))
        }
    }

    @ViewBuilder
    private func chip(_ value: TimeInterval?) -> some View {
        if let value {
            Chip(text: "경과 \(DurationFormatter.short(value))")
        }
    }
}
