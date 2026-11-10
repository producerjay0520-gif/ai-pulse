#!/usr/bin/env bash
# 빌드된 앱 번들의 CLI 들을 실제로 실행해 보는 통합 테스트 (CI 용, 사용자 설정은 건드리지 않음)
#   ./Scripts/smoke-test.sh build/AIPulse.app
set -euo pipefail
APP="${1:-build/AIPulse.app}"
HOOK="$APP/Contents/MacOS/aipulse-hook"
MCP="$APP/Contents/MacOS/aipulse-mcp"
TMP="$(mktemp -d)"
export AIPULSE_HOME="$TMP/data"
export AIPULSE_TEST_HOME="$TMP/home"
mkdir -p "$AIPULSE_TEST_HOME/.claude"
echo '{"model":"keep-me"}' > "$AIPULSE_TEST_HOME/.claude/settings.json"
fail() { echo "✗ $*"; exit 1; }

echo "▸ 번들 구성"
for f in "$APP/Contents/MacOS/AIPulse" "$HOOK" "$MCP" "$APP/Contents/Resources/AIPulse.mcpb" "$APP/Contents/Resources/AppIcon.icns"; do
  [[ -e "$f" ]] || fail "없음: $f"
done
unzip -l "$APP/Contents/Resources/AIPulse.mcpb" | grep -q "server/aipulse-mcp" || fail "mcpb 에 서버 없음"
unzip -p "$APP/Contents/Resources/AIPulse.mcpb" manifest.json | python3 -m json.tool >/dev/null || fail "mcpb manifest JSON 오류"

echo "▸ 훅 기록"
echo '{"session_id":"s1","cwd":"/tmp/p","hook_event_name":"UserPromptSubmit","prompt":"테스트"}' | "$HOOK" claude
echo '{"session_id":"s1","cwd":"/tmp/p","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"swift test"}}' | "$HOOK" claude
echo 'not json' | "$HOOK" codex   # 잘못된 입력도 exit 0
OUT="$(echo '{"session_id":"s1","hook_event_name":"Stop"}' | "$HOOK" claude)"
[[ -z "$OUT" ]] || fail "훅이 stdout 에 출력함: $OUT"
LINES=$(wc -l < "$AIPULSE_HOME/events.jsonl" | tr -d ' ')
[[ "$LINES" == "3" ]] || fail "이벤트 3줄 기대, 실제 $LINES"

echo "▸ 설치/제거"
"$HOOK" install claude | tee "$TMP/install.txt"
grep -q "aipulse-hook" "$AIPULSE_TEST_HOME/.claude/settings.json" || fail "훅이 등록되지 않음"
grep -q "keep-me" "$AIPULSE_TEST_HOME/.claude/settings.json" || fail "기존 설정이 사라짐"
[[ -f "$AIPULSE_TEST_HOME/.claude/settings.json.aipulse-backup" ]] || fail "백업 없음"
"$HOOK" install claude >/dev/null    # 두 번 설치해도 중복 없음
COUNT=$(grep -o "aipulse-hook" "$AIPULSE_TEST_HOME/.claude/settings.json" | wc -l | tr -d ' ')
[[ "$COUNT" == "15" ]] || fail "훅 중복 또는 누락: $COUNT"
"$HOOK" status | grep -q "Claude Code" || fail "status 출력 없음"
"$HOOK" uninstall claude >/dev/null
! grep -q "aipulse-hook" "$AIPULSE_TEST_HOME/.claude/settings.json" || fail "제거되지 않음"
grep -q "keep-me" "$AIPULSE_TEST_HOME/.claude/settings.json" || fail "제거하면서 기존 설정이 사라짐"

echo "▸ MCP 서버"
RESP="$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"report_status","arguments":{"task_id":"t1","title":"앱 컴포넌트 구현","status":"working","steps":[{"title":"요청 분석","status":"completed"},{"title":"코드 구현","status":"in_progress"}]}}}' \
  | "$MCP")"
echo "$RESP"
[[ "$(echo "$RESP" | wc -l | tr -d ' ')" == "3" ]] || fail "MCP 응답 3줄 기대"
echo "$RESP" | grep -q '"instructions"' || fail "initialize 에 instructions 없음"
echo "$RESP" | grep -q '"report_status"' || fail "tools/list 에 report_status 없음"
echo "$RESP" | grep -q 'Reported to AI Pulse' || fail "tools/call 실패"
grep -q '"PulseReport"' "$AIPULSE_HOME/events.jsonl" || fail "MCP 보고가 기록되지 않음"

echo "▸ 앱 실행 (3초)"
"$APP/Contents/MacOS/AIPulse" & PID=$!
sleep 3
kill -0 "$PID" 2>/dev/null || fail "앱이 실행 직후 종료됨"
kill "$PID"

rm -rf "$TMP"
echo "✓ smoke test 통과"
