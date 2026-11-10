# AI Pulse 개인정보 처리방침 / Privacy Policy

최종 수정: 2026-11-10

## 요약
AI Pulse 는 **어떤 데이터도 수집하거나 외부로 전송하지 않습니다.** 네트워크 기능이 없습니다.

## 이 Mac 에만 저장되는 정보
연결한 AI 도구(Claude Code, Codex, Claude 앱)가 작업할 때, 화면 표시를 위해 다음 요약을
`~/Library/Application Support/AIPulse/events.jsonl` 에 기록합니다.

- 세션 ID, 작업 폴더 경로, 이벤트 종류와 시각
- 툴 이름과 명령·파일 경로 앞부분 (최대 100자), 사용자 요청 앞부분 (최대 120자)
- 작업 체크리스트 제목과 상태
- 에이전트를 실행한 앱의 번들 ID (터미널로 이동하는 데 사용)

파일 내용, 툴 실행 결과, 전체 대화 내용은 기록하지 않습니다. 로그는 8MB 를 넘으면 자동으로 비워지며,
앱을 지울 때 위 폴더를 삭제하면 모두 사라집니다.

## 수정하는 설정 파일
사용자가 연결을 누른 경우에만 `~/.claude/settings.json`, `~/.codex/hooks.json` 에 AI Pulse 훅을 추가하며,
수정 전 파일을 `.aipulse-backup` 으로 백업합니다. 연결 해제 시 AI Pulse 항목만 제거합니다.

## 문의
GitHub 저장소의 Issues 를 이용해 주세요.

---

**English.** AI Pulse collects no data and makes no network connections. Short summaries of agent activity
(session id, working directory, event type and time, tool name and truncated command/path, truncated prompt,
checklist titles) are stored only on your Mac at `~/Library/Application Support/AIPulse/events.jsonl` to drive the UI.
File contents, tool output and full conversations are never recorded.
