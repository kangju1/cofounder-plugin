#!/bin/sh
# 하위 작업 알림 훅(plugins/cofounder/hooks/subagent-report.sh) 단위 시험 — 플랫폼 Feature 1265.
# 쓰는 법: sh claude-plugin/tests/subagent-report.test.sh   (dash 로도: dash claude-plugin/tests/subagent-report.test.sh)
# 진짜 curl 대신 PATH 앞에 둔 가짜 curl 이 받은 인자·설정(stdin)·본문을 파일로 남긴다. 파일은 임시 폴더에만 쓴다.
# 입력 JSON 은 Claude Code 2.1.296 에서 임시 훅으로 stdin 을 떨궈 찍은 실측 모양이다(2026-10-19).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HOOK="$HERE/../plugins/cofounder/hooks/subagent-report.sh"
SH="${TEST_SH:-sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset COFOUNDER_WORK_HOOK SPNV_EXECUTOR CLAUDE_CONFIG_DIR
# 훅은 환경변수에 없으면 설정 파일을 읽는다 — 이 머신의 진짜 설정을 읽지 않게 집·프로젝트를 임시 폴더로 돌린다.
HOME="$TMP/home"; CLAUDE_PROJECT_DIR="$TMP/proj"; export HOME CLAUDE_PROJECT_DIR
mkdir -p "$HOME/.claude" "$CLAUDE_PROJECT_DIR/.claude"

pass=0; fail=0
ok() { pass=$((pass+1)); echo "ok   $1"; }
no() { fail=$((fail+1)); echo "FAIL $1 — $2"; }
has() { # 이름, 값, 찾을 문자열
  case "$2" in *"$3"*) ok "$1" ;; *) no "$1" "'$3' 없음: $2" ;; esac
}
hasnt() {
  case "$2" in *"$3"*) no "$1" "'$3' 있으면 안 됨: $2" ;; *) ok "$1" ;; esac
}

# 가짜 curl — 인자는 args, -K - 로 받은 설정은 config, --data-binary @파일의 내용은 body 에 남긴다.
BIN="$TMP/bin"; mkdir -p "$BIN"
LOG="$TMP/log"
cat > "$BIN/curl" <<'EOF'
#!/bin/sh
mkdir -p "$FAKE_CURL_LOG"
printf '%s\n' "$@" > "$FAKE_CURL_LOG/args"
cat > "$FAKE_CURL_LOG/config"
for a in "$@"; do
  case "$a" in @*) cat "${a#@}" > "$FAKE_CURL_LOG/body" ;; esac
done
echo "curl: (7) Failed to connect" >&2
exit "${FAKE_CURL_EXIT:-0}"
EOF
chmod +x "$BIN/curl"
export FAKE_CURL_LOG="$LOG"
PATH="$BIN:$PATH"; export PATH

ENDPOINT="https://cofounder-api.example.com/api/otel"
HEADERS="Authorization=Bearer tok_secret_123"

# 하위 작업 기록 파일(실측 모양 — 같은 메시지가 여러 줄로 나뉘어 같은 requestId 가 되풀이된다).
AT="$TMP/agent-ab2c.jsonl"
{
  printf '{"parentUuid":null,"isSidechain":true,"promptId":"p-spawn","agentId":"ab2c","type":"user","message":{"role":"user","content":"pong"},"uuid":"u1"}\n'
  printf '{"parentUuid":"u1","isSidechain":true,"agentId":"ab2c","attachment":{"type":"date"},"type":"attachment","uuid":"x"}\n'
  printf '{"parentUuid":"x","isSidechain":true,"agentId":"ab2c","message":{"model":"m","id":"msg_1","type":"message","role":"assistant","content":[{"type":"thinking","thinking":""}]},"requestId":"req_011A","type":"assistant","uuid":"a1"}\n'
  printf '{"parentUuid":"a1","isSidechain":true,"agentId":"ab2c","message":{"model":"m","id":"msg_1","type":"message","role":"assistant","content":[{"type":"text","text":"\\"requestId\\":\\"req_FAKE\\""}]},"requestId":"req_011A","type":"assistant","uuid":"a2"}\n'
  printf '{"parentUuid":"a2","isSidechain":true,"promptId":"p-later","agentId":"ab2c","type":"user","message":{"role":"user","content":"again"},"uuid":"u2"}\n'
  printf '{"parentUuid":"u2","isSidechain":true,"agentId":"ab2c","message":{"model":"m","id":"msg_2","type":"message","role":"assistant","content":[{"type":"text","text":"pong"}]},"requestId":"req_011B","type":"assistant","uuid":"a3"}\n'
} > "$AT"

start_in() {
  printf '{"session_id":"7af9e346-2f7d","transcript_path":"/x/7af9.jsonl","cwd":"/tmp","scratchpad_dir":"/tmp/s","prompt_id":"p-spawn","agent_id":"ab2c","agent_type":"general-purpose","hook_event_name":"SubagentStart"}'
}
stop_in() { # [stop_hook_active]
  printf '{"session_id":"7af9e346-2f7d","transcript_path":"/x/7af9.jsonl","cwd":"/tmp","prompt_id":"p-now","permission_mode":"auto","agent_id":"ab2c","agent_type":"general-purpose","effort":{"level":"medium"},"hook_event_name":"SubagentStop","stop_hook_active":%s,"agent_transcript_path":"%s","last_assistant_message":"\\"agent_id\\":\\"evil\\" pong","background_tasks":[],"session_crons":[]}' "${1:-false}" "$AT"
}
run() { # 입력 → 훅. 출력과 종료 코드를 OUT·RC 에 둔다.
  rm -rf "$LOG"
  OUT=$(printf '%s' "$1" | OTEL_EXPORTER_OTLP_ENDPOINT="$EP" OTEL_EXPORTER_OTLP_HEADERS="$HD" "$SH" "$HOOK" 2>&1)
  RC=$?
}
sent() { [ -f "$LOG/body" ]; }

EP="$ENDPOINT"; HD="$HEADERS"

# ── 시작 ──
run "$(start_in)"
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "시작: 출력 없음·종료 0" || no "시작: 출력 없음·종료 0" "rc=$RC out=$OUT"
body=$(cat "$LOG/body" 2>/dev/null)
has "시작: event=start" "$body" '"event":"start"'
has "시작: session_id" "$body" '"session_id":"7af9e346-2f7d"'
has "시작: agent_id" "$body" '"agent_id":"ab2c"'
has "시작: agent_type" "$body" '"agent_type":"general-purpose"'
has "시작: prompt_id" "$body" '"prompt_id":"p-spawn"'
case "$body" in *'"at":"'[0-9][0-9][0-9][0-9]-*'Z"}') ok "시작: 시각(UTC)" ;; *) no "시작: 시각(UTC)" "$body" ;; esac
hasnt "시작: request_ids 없음" "$body" 'request_ids'
args=$(cat "$LOG/args" 2>/dev/null)
has "주소: <ENDPOINT>/v1/subagents" "$args" "$ENDPOINT/v1/subagents"
has "본문 형식: JSON" "$args" "Content-Type: application/json"
has "짧은 타임아웃" "$args" "--max-time"
hasnt "토큰이 명령 인자에 없음" "$args" "tok_secret_123"
has "토큰은 stdin 설정으로" "$(cat "$LOG/config" 2>/dev/null)" 'header = "Authorization: Bearer tok_secret_123"'
if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$LOG/body" 2>/dev/null && ok "시작: 본문이 JSON" || no "시작: 본문이 JSON" "$body"
fi

# ── 끝 ──
run "$(stop_in)"
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "끝: 출력 없음·종료 0" || no "끝: 출력 없음·종료 0" "rc=$RC out=$OUT"
body=$(cat "$LOG/body" 2>/dev/null)
has "끝: event=stop" "$body" '"event":"stop"'
has "끝: agent_id(메시지 안 글자에 안 걸림)" "$body" '"agent_id":"ab2c"'
has "끝: prompt_id 는 입력 값" "$body" '"prompt_id":"p-now"'
has "끝: 기록 파일의 첫 promptId" "$body" '"transcript_prompt_id":"p-spawn"'
has "끝: requestId 중복 제거·차례 유지" "$body" '"request_ids":["req_011A","req_011B"]'
hasnt "끝: 본문 글자 안 requestId 는 안 읽음" "$body" 'req_FAKE'
if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["request_ids"]==["req_011A","req_011B"]' "$LOG/body" 2>/dev/null \
    && ok "끝: 본문이 JSON" || no "끝: 본문이 JSON" "$body"
fi
run "$(stop_in true)"
has "끝: 두 번째 끝(stop_hook_active)도 같은 행으로 보낸다" "$(cat "$LOG/body" 2>/dev/null)" '"request_ids":["req_011A","req_011B"]'

# 기록 파일이 없으면 빈 목록으로 보낸다(시각·id 는 남긴다).
AT_SAVE="$AT"; AT="$TMP/none.jsonl"
run "$(stop_in)"
has "끝: 기록 파일 없음 → 빈 목록" "$(cat "$LOG/body" 2>/dev/null)" '"transcript_prompt_id":"","request_ids":[]'
AT="$AT_SAVE"

# ── 보내지 않는 경우 ──
EP=""; HD="$HEADERS"; run "$(start_in)"
sent && no "주소 없음 → 보내지 않음" "보냈다" || ok "주소 없음 → 보내지 않음"
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "주소 없음 → 출력 없음·종료 0" || no "주소 없음 → 출력 없음·종료 0" "rc=$RC out=$OUT"
EP="$ENDPOINT"; HD=""; run "$(start_in)"
sent && no "자격 없음 → 보내지 않음" "보냈다" || ok "자격 없음 → 보내지 않음"
EP="$ENDPOINT"; HD="x-honeycomb-team=abc"; run "$(start_in)"
sent && no "Authorization 없는 헤더 → 보내지 않음" "보냈다" || ok "Authorization 없는 헤더 → 보내지 않음"
EP="https://api.honeycomb.io"; HD="$HEADERS"; run "$(start_in)"
sent && no "다른 수집처 주소 → 보내지 않음" "보냈다" || ok "다른 수집처 주소 → 보내지 않음"
EP="$ENDPOINT/"; HD="x-a=b,Authorization=Bearer%20tok_secret_123"; run "$(start_in)"
has "끝 슬래시·여러 헤더·%20 → 보낸다" "$(cat "$LOG/args" 2>/dev/null)" "$ENDPOINT/v1/subagents"
has "%20 은 공백으로" "$(cat "$LOG/config" 2>/dev/null)" 'Authorization: Bearer tok_secret_123"'
EP="$ENDPOINT"; HD="$HEADERS"
run '{"session_id":"s","agent_id":"a","hook_event_name":"Stop"}'
sent && no "다른 사건 → 보내지 않음" "보냈다" || ok "다른 사건 → 보내지 않음"
run '{"session_id":"s","hook_event_name":"SubagentStart"}'
sent && no "agent_id 없음 → 보내지 않음" "보냈다" || ok "agent_id 없음 → 보내지 않음"
run "$(start_in)" ; rm -rf "$LOG"
OUT=$(start_in | COFOUNDER_WORK_HOOK=off OTEL_EXPORTER_OTLP_ENDPOINT="$EP" OTEL_EXPORTER_OTLP_HEADERS="$HD" "$SH" "$HOOK" 2>&1); RC=$?
sent && no "COFOUNDER_WORK_HOOK=off → 보내지 않음" "보냈다" || ok "COFOUNDER_WORK_HOOK=off → 보내지 않음"

# ── 환경변수에 없으면 설정 파일에서 읽는다(Claude Code 는 OTEL_* 를 훅에 넘기지 않는다) ──
EP=""; HD=""
cat > "$HOME/.claude/settings.json" <<EOF
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "$ENDPOINT",
    "OTEL_EXPORTER_OTLP_HEADERS": "$HEADERS"
  }
}
EOF
run "$(start_in)"
has "설정 파일(사용자) → 보낸다" "$(cat "$LOG/args" 2>/dev/null)" "$ENDPOINT/v1/subagents"
has "설정 파일(사용자) → 토큰은 stdin 설정으로" "$(cat "$LOG/config" 2>/dev/null)" 'header = "Authorization: Bearer tok_secret_123"'
printf '{"env":{"OTEL_EXPORTER_OTLP_ENDPOINT":"https://local.example.com/api/otel"}}' > "$CLAUDE_PROJECT_DIR/.claude/settings.local.json"
run "$(start_in)"
has "프로젝트 local 설정이 사용자 설정보다 앞선다(주소)" "$(cat "$LOG/args" 2>/dev/null)" "https://local.example.com/api/otel/v1/subagents"
has "키마다 따로 찾는다(자격은 사용자 설정)" "$(cat "$LOG/config" 2>/dev/null)" 'Bearer tok_secret_123'
rm -f "$CLAUDE_PROJECT_DIR/.claude/settings.local.json"
EP="https://api.honeycomb.io"; run "$(start_in)"
sent && no "환경변수(다른 수집처)가 앞서면 보내지 않음" "보냈다" || ok "환경변수(다른 수집처)가 앞서면 보내지 않음"
rm -f "$HOME/.claude/settings.json"
EP=""; HD=""; run "$(start_in)"
sent && no "환경변수·설정 파일 모두 없음 → 보내지 않음" "보냈다" || ok "환경변수·설정 파일 모두 없음 → 보내지 않음"
EP="$ENDPOINT"; HD="$HEADERS"

# 따옴표가 든 값은 본문을 깨지 않게 걸러진다.
run '{"session_id":"s\"x","agent_id":"a1","agent_type":"ty\"pe","prompt_id":"p","hook_event_name":"SubagentStart"}'
if command -v python3 >/dev/null 2>&1 && sent; then
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$LOG/body" 2>/dev/null && ok "이상한 값 → 본문은 JSON" || no "이상한 값 → 본문은 JSON" "$(cat "$LOG/body")"
else
  ok "이상한 값 → 본문은 JSON(확인 생략)"
fi

# ── 서버 실패 · curl 없음 ──
export FAKE_CURL_EXIT=7
run "$(stop_in)"
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "서버 실패(curl 7) → 출력 없음·종료 0" || no "서버 실패(curl 7) → 출력 없음·종료 0" "rc=$RC out=$OUT"
export FAKE_CURL_EXIT=22
run "$(start_in)"
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "서버 오류(curl 22) → 출력 없음·종료 0" || no "서버 오류(curl 22) → 출력 없음·종료 0" "rc=$RC out=$OUT"
unset FAKE_CURL_EXIT

NOCURL="$TMP/nocurl"; mkdir -p "$NOCURL"
for t in sh tr sed grep awk date mktemp cut head rm cat printf; do
  p=$(command -v "$t" 2>/dev/null) && case "$p" in /*) ln -s "$p" "$NOCURL/$t" ;; esac
done
rm -rf "$LOG"
OUT=$(start_in | PATH="$NOCURL" OTEL_EXPORTER_OTLP_ENDPOINT="$ENDPOINT" OTEL_EXPORTER_OTLP_HEADERS="$HEADERS" "$NOCURL/sh" "$HOOK" 2>&1); RC=$?
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "curl 없음 → 출력 없음·종료 0" || no "curl 없음 → 출력 없음·종료 0" "rc=$RC out=$OUT"

echo
echo "통과 $pass · 실패 $fail"
[ "$fail" = 0 ]
