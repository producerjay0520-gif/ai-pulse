import SwiftUI
import AppKit
import ServiceManagement
import AIPulseCore

/// 설정: 연결·일반 · 테마 · 인터페이스 3개 탭
struct SettingsView: View {
    var body: some View {
        TabView {
            ViewSettingsTab()
                .tabItem { Label("연결 · 일반", systemImage: "link") }
            ThemeSettingsTab()
                .tabItem { Label("테마", systemImage: "paintpalette") }
            InterfaceSettingsTab()
                .tabItem { Label("인터페이스", systemImage: "checklist") }
        }
        .frame(width: 720, height: 600)
    }
}

// MARK: - Tab 1 보기 · 연결

struct ViewSettingsTab: View {
    @Environment(PulseStore.self) private var store
    @AppStorage(Prefs.dockSize) private var size: DockSize = .regular
    @State private var output = ""
    @State private var working = false
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("에이전트 연결") {
                connectionRow(
                    name: "Claude Code",
                    detail: "터미널 · 데스크톱 앱의 Code 탭 (~/.claude/settings.json)",
                    connected: store.hookStatus.claude
                ) { await toggleHook(target: "claude", connected: store.hookStatus.claude) }
                connectionRow(
                    name: "Codex",
                    detail: "Codex CLI (~/.codex/hooks.json) · 처음 실행 때 /hooks 에서 신뢰 필요",
                    connected: store.hookStatus.codex
                ) { await toggleHook(target: "codex", connected: store.hookStatus.codex) }
                connectionRow(
                    name: "Claude 앱",
                    detail: "Claude 데스크톱 앱의 대화·에이전트 작업 (AI Pulse 확장)",
                    connected: store.hookStatus.claudeApp,
                    connectTitle: "확장 설치",
                    connectedTitle: "다시 설치"
                ) {
                    output = ClaudeAppConnector.install()
                }
                if !output.isEmpty {
                    Text(output)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                Text("연결하면 각 도구의 설정에 AI Pulse 훅/확장이 추가됩니다. 기존 설정 파일은 .aipulse-backup 으로 백업됩니다. AI Pulse 는 작업 요약만 이 Mac 에 기록하고, 에이전트 동작에는 관여하지 않으며 네트워크로 아무것도 보내지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("일반") {
                Toggle("로그인 시 자동으로 실행", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        output = LoginItem.set(newValue)
                        launchAtLogin = LoginItem.isEnabled
                    }
                ))
                Picker("패널 크기", selection: $size) {
                    ForEach(DockSize.allCases) { Text("\($0.title) · \(Int($0.width))pt").tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("메뉴바 아이콘이 안 보이나요?") {
                Text("맥북 노치 근처는 메뉴바 아이콘이 가려질 수 있습니다. ⌘ 키를 누른 채 아이콘을 오른쪽으로 끌어 옮기거나, 다른 메뉴바 앱을 줄이세요. 언제든 Spotlight 에서 AI Pulse 를 다시 실행하면 패널이 창으로 열립니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("패널을 창으로 열기") { StatusBarController.shared.showPanelWindow() }
            }
        }
        .formStyle(.grouped)
    }

    private func toggleHook(target: String, connected: Bool) async {
        let result = await HookInstaller.run([connected ? "uninstall" : "install", target])
        output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func connectionRow(
        name: String,
        detail: String,
        connected: Bool,
        connectTitle: String = "연결",
        connectedTitle: String = "연결 해제",
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        HStack {
            Image(systemName: connected ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(connected ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(connected ? connectedTitle : connectTitle) {
                working = true
                Task {
                    await action()
                    working = false
                    store.refreshHookStatus()
                }
            }
            .disabled(working)
        }
    }
}

// MARK: - Tab 2 테마

private struct ThemeSettingsTab: View {
    @AppStorage(Prefs.theme) private var theme: ThemeKind = .default
    @AppStorage(Prefs.appearance) private var appearance: AppearanceMode = .system

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Form {
                Section("테마") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(ThemeKind.allCases) { kind in
                            ThemeCard(kind: kind, selected: kind == theme) { theme = kind }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("화면 모드") {
                    Picker("화면 모드", selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: appearance) { _, newValue in
                        AppearanceController.apply(newValue)
                    }
                    Text("테마와 화면 모드는 따로 바꿀 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(width: 380)

            LivePreview()
        }
    }
}

private struct ThemeCard: View {
    let kind: ThemeKind
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ThemedContainer(override: kind) {
                    ThemeSwatch()
                }
                Text(kind.title).font(.system(size: 12, weight: .semibold))
                Text(kind.subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 테마 카드 안의 작은 견본: 패널 소재 + 상태 캐릭터 + 진행 바
private struct ThemeSwatch: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach([ActivityState.thinking, .writing, .awaitingApproval, .done], id: \.self) { state in
                    StatusGlyph(state: state, size: 18)
                }
            }
            PulseProgressBar(value: 0.64, state: .writing)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThemePanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Tab 3 인터페이스

private struct InterfaceSettingsTab: View {
    @AppStorage(Prefs.display) private var options = DisplayOptions()

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Form {
                Section("프리셋") {
                    HStack(spacing: 8) {
                        ForEach(DisplayPreset.allCases) { preset in
                            presetButton(preset)
                        }
                    }
                }
                Section("표시 정보") {
                    ForEach(DisplayOptions.fields.indices, id: \.self) { index in
                        let field = DisplayOptions.fields[index]
                        Toggle(field.title, isOn: Binding(
                            get: { options[keyPath: field.path] },
                            set: { options[keyPath: field.path] = $0 }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 380)

            LivePreview()
        }
    }

    private func presetButton(_ preset: DisplayPreset) -> some View {
        let active = options == preset.options
        return Button {
            options = preset.options
        } label: {
            VStack(spacing: 2) {
                Text(preset.title).font(.system(size: 12, weight: .semibold))
                Text(preset.subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(active ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(active ? Color.accentColor : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 실시간 미리보기

/// 데모 스크립트 스냅샷을 현재 설정(테마·체크박스·크기)으로 그린다. 설정을 바꾸면 즉시 반영된다.
private struct LivePreview: View {
    @AppStorage(Prefs.display) private var options = DisplayOptions()
    @AppStorage(Prefs.dockSize) private var size: DockSize = .regular
    @State private var sessions: [AgentSession] = Array(DemoScenario.snapshot(at: 24).values)

    private var lead: AgentSession? {
        sessions.first { $0.sessionId == "demo-claude-pulse" } ?? sessions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("실시간 미리보기")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ThemedContainer {
                VStack(spacing: 10) {
                    if let lead {
                        SessionDetailCard(session: lead, options: options, interactive: false)
                    }
                }
                .padding(12)
                .frame(width: size.width + 20)
                .background(ThemePanelBackground())
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 로그인 시 실행

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// 결과 안내 문구 (성공하면 빈 문자열)
    static func set(_ enabled: Bool) -> String {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            return "자동 실행 설정을 바꾸지 못했습니다: \(error.localizedDescription)"
        }
        if enabled && SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return "시스템 설정 → 로그인 항목에서 AI Pulse 를 허용해 주세요."
        }
        return ""
    }
}
