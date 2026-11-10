# AI Pulse — 요구사항 분석 · 이벤트 수집 검증 · 아키텍처

작성일 2026-11-10 · 대상 버전 1.0

## 1. 구현 가능 / 제약 구분

| 요구사항 | 판단 | 근거·방식 |
|---|---|---|
| Claude Code 세션 감지, 시작/완료 | ✅ 가능 | 공식 훅 `SessionStart`, `UserPromptSubmit`, `Stop`, `SessionEnd` |
| Codex 세션 감지, 시작/완료 | ✅ 가능 | Codex 훅(기본 활성) `SessionStart`, `UserPromptSubmit`, `Stop`, `SessionEnd` |
| 승인 요청 감지 | ✅ 가능 | 두 제공자 모두 `PermissionRequest`. Claude 는 `Notification(permission_prompt)` 도 |
| 오류·중단 | ✅ 가능 | Claude `StopFailure`, `PostToolUseFailure` / Codex `Interrupt` |
| 현재 작업 단계 | ✅ 가능(추정) | `PreToolUse` 의 툴 이름·명령으로 분류 (편집=코드 작성, 테스트 명령=테스트 …) |
| 진행률 | ⚠️ 부분 | Claude 의 `TodoWrite` 체크리스트(완료/전체), `TaskCreated/TaskCompleted`. **근거가 없으면 숫자 대신 활동 표시** (Codex 대부분) |
| 단계별 소요 시간 | ✅ 가능 | 체크리스트 항목이 진행 중/완료로 바뀐 시각 기록 |
| 예상 완료 시간 | ⚠️ 추정 | 체크리스트 진행 속도 선형 추정. 3단계 이상·20% 이상·30초 이상일 때만 "추정"으로 표시 |
| 파일 수정 수 / 테스트 현황 | ✅ 가능 | Edit/Write/apply_patch 경로 집계, 테스트 명령 실행·실패 집계 |
| 프로젝트 클릭 → 터미널 이동 | ⚠️ 앱 단위 | 훅 환경변수 `__CFBundleIdentifier`·`TERM_PROGRAM` 으로 터미널 앱 활성화. **특정 탭/창 선택은 터미널별 AppleScript 필요 → 후속** |
| 목업의 일시정지/중지 버튼 | ❌ 보류 | 외부에서 에이전트를 안전하게 일시정지·중지하는 공식 API가 없음. 훅으로 툴 실행을 막는 방식은 에이전트 동작을 바꾸므로 MVP 제외 → **알림 끄기 / 터미널 이동**으로 대체 |
| macOS 알림 | ✅ 가능 | UserNotifications (.app 번들에서만 동작) |
| Claude 앱 (데스크톱) 대화·에이전트 작업 | ✅ 가능 (v1.0) | 공식 확장 형식 `.mcpb` 로 MCP 서버 `aipulse-mcp` 설치. 서버 `instructions` 가 시스템 프롬프트에 들어가 Claude 가 `report_status` 로 제목·단계·상태를 보고. 보고 여부는 모델이 결정하므로 100% 보장은 아님 |
| claude.ai 웹 · ChatGPT 웹 | ❌ 범위 밖 | 훅·확장 지점 없음 |
| Mac App Store 배포 | ❌ 제외 | App Store 앱 안의 명령줄 도구는 다른 앱이 실행할 수 없어 훅·확장이 동작하지 않음. GitHub Releases 로 배포 |
| 메뉴바 아이콘 | ✅ | `NSStatusItem` + `NSPopover` (아이콘 + 퍼센트). 노치에 가려지면 Spotlight 재실행 시 패널을 창으로 표시 |
| 사이드 도크 | ⏸ 보류 | 1.0 에서 제외 (미구현 UI 는 설정에서 제거) |

## 2. 이벤트 수집 검증 결과

### Claude Code
- 설정: `~/.claude/settings.json` 의 `hooks` (이벤트 → matcher 그룹 → 핸들러)
- 입력: stdin JSON. 공통 `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `permission_mode` / 툴 이벤트 `tool_name`, `tool_input`, `tool_use_id`
- `Notification` 의 `notification_type`: `permission_prompt`, `idle_prompt`, `agent_needs_input`, `agent_completed` 등
- 주의: `SessionStart`·`UserPromptSubmit` 의 stdout 은 모델 컨텍스트로 들어감 → 훅은 **아무것도 출력하지 않음**

### Codex
- 설정: `~/.codex/hooks.json` 또는 `config.toml` 의 `[hooks]`. 훅은 기본 활성이지만 **새 훅은 `/hooks` 에서 신뢰(trust)해야 실행**
- 이벤트: `SessionStart`, `SessionEnd`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `UserPromptSubmit`, `Stop`, `Interrupt`, `SubagentStart/Stop`, `PreCompact/PostCompact`, `Pre/PostModelRequest`
- 입력: Claude 와 같은 공통 필드 + `turn_id`, `model`
- `SessionEnd`·`Interrupt` 기본 타임아웃 1초 → 훅은 빠르게 끝나야 함 (Swift CLI, 수 ms)

## 3. 아키텍처

```
Claude Code / Codex                 Claude 앱
   │ 훅 (stdin JSON)                  │ MCP (report_status)
   ▼                                  ▼
aipulse-hook <claude|codex>        aipulse-mcp (.mcpb 확장)
   │ 필요한 필드만 추려 한 줄 JSON (O_APPEND 단일 write, 동시 기록 안전)
   ▼
~/Library/Application Support/AIPulse/events.jsonl
   │ 0.5초 간격 tail (stat 크기 비교만 → 유휴 시 비용 거의 없음)
   ▼
SessionReducer (순수 함수)  ←──  DemoScenario (Mock 이벤트, 같은 경로)
   │ [String: AgentSession] + 알림 효과
   ▼
PulseStore (@Observable) → MenuBarExtra 팝오버 · 설정 · UserNotifications
```

- **훅은 판단하지 않고 기록만** 한다. 상태 해석은 전부 앱의 리듀서에서 → 규칙을 바꿔도 훅 재설치 불필요
- **Mock 데이터도 실제와 같은 리듀서**를 지나가므로 UI 테스트가 곧 상태 전이 테스트
- 앱 재시작 시 로그 끝 2MB 를 재생해 진행 중 세션 복원 (재생분으로는 알림 안 보냄)
- 로그 8MB 초과 시 비움, 종료 후 30분·무활동 12시간 세션은 목록에서 정리

### 모듈
| 타깃 | 역할 |
|---|---|
| `AIPulseCore` | `PulseEvent`, `HookInputParser`, `ToolClassifier`, `AgentSession`, `SessionReducer`, `EventWriter/EventTailer`, `DemoScenario` — UI 의존성 없음, XCTest 대상 |
| `AIPulseHook` | `aipulse-hook` CLI: 훅 모드, `install/uninstall/status` (설정 병합 + 백업) |
| `AIPulse` | SwiftUI 메뉴바 앱: 팝오버, 설정 3탭, 테마 5종, 알림, 터미널 이동 |

## 4. 데이터 모델

- **프로젝트** = 세션 `cwd` 의 git 루트 (없으면 cwd). 한 프로젝트에 Claude·Codex 세션 여러 개가 묶인다
- **세션** `AgentSession`: `agent`, `state`(7종), `step`, `prompt`, `todos`, 단계별 시간, `filesEdited`, `testsRun/Failed`, `toolCalls`, 턴 시작/소요 시간, 실행 터미널 정보
- **상태 우선순위**: 승인 대기 > 오류 > 진행(분석·작성·테스트) > 완료 > 대기 — 목록 정렬과 메뉴바 아이콘에 사용

### 상태 전이 요약
| 이벤트 | 결과 |
|---|---|
| `UserPromptSubmit` | 분석 중, 턴 시작 |
| `PreToolUse` Edit/Write/apply_patch | 코드 작성 |
| `PreToolUse` 셸 + 테스트 명령 | 테스트 |
| `PreToolUse` 그 밖의 툴 | 분석 중 (단계 텍스트로 구분) |
| `PermissionRequest` / `Notification(permission_prompt)` | 승인 대기 + 알림 (중복 방지) |
| `PostToolUse` (승인 대기 중) | 분석 중 |
| `Stop` | 완료 + 알림 |
| `StopFailure` / `Interrupt` | 오류 (StopFailure 만 알림) |

## 5. UI (목업 반영)

- 기본 테마 **Warm Glass**: 회갈색 반투명 패널 + 번지는 주황 빛, 흰 텍스트, 얇고 큰 숫자, 둥근 유리 버튼
- 팝오버: 헤더(캐릭터 타일 · 이름 · 에이전트/프로젝트 · 터미널 이동 · 알림 끄기) → 세션 목록(2개 이상) → 상세 카드(제목·큰 %·진행 바·단계 목록·승인 요청·통계) → 하단(상태 칩·예상/경과·더보기)
- 그 외 테마: Apple Minimal, Retro Pixel, Neon(목업 1·2 색감), Animal — 구조는 같고 색·소재·모션만 다름
- 움직임 줄이기 설정 시 모든 캐릭터·진행 바 애니메이션 정지, 완료 상태는 항상 정지 이미지

## 6. 다음 단계
1. Mac 에서 빌드·테스트 후 실제 세션으로 상태 전이 검증 (특히 Codex 툴 이름 실측)
2. 메뉴바 컬러 미니 진행 바 (`NSStatusItem`)
3. 사이드 도크 (`NSPanel`, 가장자리 호버)
4. 터미널 탭 단위 이동 (Terminal/iTerm2 AppleScript, tty 기록)
5. 참고 오픈소스(AgentBar 등) 라이선스·기능 비교 — 이번 세션에서는 GitHub 접근이 막혀 확인하지 못함. 코드는 참고 없이 독자 구현
