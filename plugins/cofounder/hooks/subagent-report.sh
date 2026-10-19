#!/bin/sh
# 하위 작업 알림 — SubagentStart·SubagentStop 훅(막지 않는다). 플랫폼 Feature 1265.
#
# 하위 작업(Agent 도구로 띄운 서브에이전트)은 부모와 같은 세션으로 사용량을 보내고, 사용량 사건의
# 요청 id(prompt.id)는 띄운 요청이 아니라 그때 진행 중인 요청 값이다. 그래서 서버는 하위 작업의 모델
# 호출 비용이 어느 하위 작업의 것인지 정확히 모른다. 하위 작업 기록 파일의 assistant 줄마다 붙은
# requestId(req_…)는 사용량 사건 api_request 의 request_id 와 같은 값이다 — 이 훅이 그 번호를
# 서버에 알려 서버가 비용을 그 하위 작업에 잇는다.
#
#   SubagentStart → session_id · agent_id · agent_type · prompt_id · 시각
#   SubagentStop  → 같은 값 + agent_transcript_path 에서 읽은 requestId 목록(중복 제거)
#                   + 그 기록 파일의 첫 promptId(띄운 요청) + 시각
#
# 보내는 곳과 자격은 사용량 수집과 같다 — 사용자 설정 env 의
#   OTEL_EXPORTER_OTLP_ENDPOINT (…/api/otel)  →  POST <그 값>/v1/subagents
#   OTEL_EXPORTER_OTLP_HEADERS  (Authorization=Bearer <수집 토큰>)
# Claude Code 는 settings 의 env 중 OTEL_* 를 훅 프로세스에 넘기지 않는다(2.1.296 실측 — 같은 env 의 다른
# 이름은 넘어온다). 그래서 환경변수에 없으면 Claude Code 와 같은 우선순위로 설정 파일에서 직접 읽는다:
#   관리 설정(managed-settings.json) > <프로젝트>/.claude/settings.local.json > <프로젝트>/.claude/settings.json
#   > ${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json   (프로젝트 = CLAUDE_PROJECT_DIR, 없으면 입력의 cwd)
# 둘 중 하나라도 못 찾거나, 주소가 /api/otel 로 끝나지 않으면(다른 수집처) 아무것도 하지 않는다.
# 토큰은 명령 인자에 싣지 않는다(curl 설정을 stdin 으로 준다 — 프로세스 목록에 안 보인다).
#
# 런타임 요구: POSIX sh 와 기본 도구(tr·sed·grep·awk·date·mktemp) + curl. jq·Python·Node 를 쓰지 않는다.
# curl 이 없으면 아무것도 하지 않는다.
# 끄기: COFOUNDER_WORK_HOOK=off.
# 어떤 경우에도 출력이 없고 종료 코드는 0 이다 — 서버가 없거나 느려도 대화를 막지 않는다(curl 3초).

case "${COFOUNDER_WORK_HOOK:-}" in
  off|OFF|Off|0|false|FALSE|no|NO) exit 0 ;;
esac

input=$(cat | tr '\r\n' '  ')

str_field() {
  printf '%s' "$2" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

# 설정 파일들에서 env 키 하나를 우선순위대로 찾는다(처음 찾은 값). 값에 따옴표가 든 경우는 다루지 않는다.
settings_env() {
  proj="${CLAUDE_PROJECT_DIR:-$(str_field cwd "$input")}"
  for f in "/Library/Application Support/ClaudeCode/managed-settings.json" \
           "/etc/claude-code/managed-settings.json" \
           ${proj:+"$proj/.claude/settings.local.json"} \
           ${proj:+"$proj/.claude/settings.json"} \
           "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"; do
    [ -r "$f" ] || continue
    v=$(tr '\r\n' '  ' < "$f" 2>/dev/null | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1)
    if [ -n "$v" ]; then printf '%s' "$v"; return 0; fi
  done
  return 0
}

endpoint="${OTEL_EXPORTER_OTLP_ENDPOINT:-}"
headers="${OTEL_EXPORTER_OTLP_HEADERS:-}"
[ -n "$endpoint" ] || endpoint=$(settings_env OTEL_EXPORTER_OTLP_ENDPOINT)
[ -n "$headers" ] || headers=$(settings_env OTEL_EXPORTER_OTLP_HEADERS)
[ -n "$endpoint" ] && [ -n "$headers" ] || exit 0
endpoint="${endpoint%/}"
case "$endpoint" in
  */api/otel) ;;
  *) exit 0 ;;
esac
command -v curl >/dev/null 2>&1 || exit 0

# OTEL_EXPORTER_OTLP_HEADERS 는 `키=값` 을 쉼표로 잇는다(값의 공백은 %20 일 수 있다). Authorization 만 쓴다.
auth=$(printf '%s' "$headers" | tr ',' '\n' | sed -n 's/^[[:space:]]*[Aa]uthorization[[:space:]]*=[[:space:]]*//p' | head -n 1 | sed 's/%20/ /g; s/[[:space:]]*$//')
[ -n "$auth" ] || exit 0
case "$auth" in
  *'"'*|*'\'*) exit 0 ;;   # curl 설정 줄을 깨는 값은 보내지 않는다
esac

# id·종류 값은 아는 글자만 남긴다 — 본문 JSON 을 손으로 엮으므로 따옴표·역슬래시가 들어가면 안 된다.
clean() { printf '%s' "$1" | tr -cd 'A-Za-z0-9_.:@/-' | cut -c1-128; }

event=$(str_field hook_event_name "$input")
case "$event" in
  SubagentStart) kind=start ;;
  SubagentStop) kind=stop ;;
  *) exit 0 ;;
esac
sid=$(clean "$(str_field session_id "$input")")
aid=$(clean "$(str_field agent_id "$input")")
atype=$(clean "$(str_field agent_type "$input")")
pid=$(clean "$(str_field prompt_id "$input")")
[ -n "$sid" ] && [ -n "$aid" ] || exit 0
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

tmp=$(mktemp -d 2>/dev/null) || exit 0
trap 'rm -rf "$tmp"' EXIT

extra=
if [ "$kind" = stop ]; then
  tpath=$(str_field agent_transcript_path "$input" | sed 's#\\/#/#g; s#\\\\#\\#g')
  ids=
  tprompt=
  if [ -n "$tpath" ] && [ -r "$tpath" ]; then
    # 같은 메시지가 여러 줄(생각·글·도구 호출)로 나뉘어 같은 requestId 가 되풀이된다 — 처음 나온 차례로 하나씩.
    ids=$(grep -o '"requestId":"req_[A-Za-z0-9_-]*"' "$tpath" 2>/dev/null \
      | sed 's/.*"\(req_[A-Za-z0-9_-]*\)"$/"\1"/' | awk '!seen[$0]++' | head -n 10000 | tr '\n' ',' | sed 's/,$//')
    tprompt=$(clean "$(grep -o -m 1 '"promptId":"[^"]*"' "$tpath" 2>/dev/null | head -n 1 | sed 's/.*:"\([^"]*\)"$/\1/')")
  fi
  extra=",\"transcript_prompt_id\":\"$tprompt\",\"request_ids\":[$ids]"
fi

printf '{"event":"%s","session_id":"%s","agent_id":"%s","agent_type":"%s","prompt_id":"%s","at":"%s"%s}' \
  "$kind" "$sid" "$aid" "$atype" "$pid" "$now" "$extra" > "$tmp/body.json" 2>/dev/null || exit 0

printf 'header = "Authorization: %s"\n' "$auth" | curl -K - -sS -o /dev/null --connect-timeout 2 --max-time 3 \
  -X POST -H 'Content-Type: application/json' --data-binary @"$tmp/body.json" \
  "$endpoint/v1/subagents" >/dev/null 2>&1
exit 0
