#!/bin/sh
# 업무 기록 알림 훅(plugins/cofounder/hooks/work-reminder.sh) 단위 시험 — 플랫폼 Feature 1197·1201·1223.
# 쓰는 법: sh claude-plugin/tests/work-reminder.test.sh   (dash 로도: dash claude-plugin/tests/work-reminder.test.sh)
# 표본 stdin JSON 을 넣고 추가 문맥 출력이 기대대로인지 본다. 상태 파일은 임시 폴더에만 쓴다.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HOOK="$HERE/../plugins/cofounder/hooks/work-reminder.sh"
SH="${TEST_SH:-sh}"
STATE=$(mktemp -d)
trap 'rm -rf "$STATE"' EXIT
export COFOUNDER_WORK_HOOK_STATE_DIR="$STATE"
unset COFOUNDER_WORK_HOOK SPNV_EXECUTOR

pass=0; fail=0
run() { printf '%s' "$1" | "$SH" "$HOOK"; }
expect() { # 이름, 출력, 찾을 문자열(빈 값이면 출력이 비어야 한다)
  if [ -z "$3" ]; then
    if [ -z "$2" ]; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1 — 출력이 없어야 함: $2"; fi
  else
    case "$2" in
      *"$3"*) pass=$((pass+1)); echo "ok   $1" ;;
      *) fail=$((fail+1)); echo "FAIL $1 — '$3' 없음: $2" ;;
    esac
  fi
}
valid_json() { # 출력이 hookSpecificOutput 한 줄 JSON 인지(따옴표 짝)
  case "$1" in
    '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"'*'"}}') return 0 ;;
    *) return 1 ;;
  esac
}
j() { # session tool input-json [response-json]
  r=${4:-}; [ -n "$r" ] || r='{}'
  printf '{"session_id":"%s","transcript_path":"/x/%s.jsonl","cwd":"/tmp","permission_mode":"default","hook_event_name":"PostToolUse","tool_name":"%s","tool_input":%s,"tool_response":%s,"tool_use_id":"toolu_1"}' \
    "$1" "$1" "$2" "$3" "$r"
}
pr() { # session prompt-text — UserPromptSubmit 입력
  printf '{"session_id":"%s","transcript_path":"/x/%s.jsonl","cwd":"/tmp","permission_mode":"default","hook_event_name":"UserPromptSubmit","prompt":"%s"}' \
    "$1" "$1" "$2"
}
valid_prompt_json() {
  case "$1" in
    '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"'*'"}}') return 0 ;;
    *) return 1 ;;
  esac
}
P=mcp__plugin_cofounder_cofounder__
S=mcp__spnv-platform__

# 1. claim_feature — 두 연결 이름 모두, 과제 번호가 item 에 들어간다
out=$(run "$(j s1 ${P}claim_feature '{"feature_id":1197,"holder":"session:s1"}' '{"id":1197,"status":"active","claimed":true}')")
expect "claim(플러그인 이름) 알림" "$out" "item=feature:1197"
expect "claim 알림은 턴 선언" "$out" "mark_work(phase=turn"
expect "claim 알림에 from_request" "$out" "from_request"
valid_json "$out" && expect "claim 출력 형식" ok ok || expect "claim 출력 형식" "$out" "__형식불일치__"
out=$(run "$(j s1 ${S}claim_feature '{"feature_id": 42, "holder": "session:s1"}')")
expect "claim(spnv-platform 이름) 알림" "$out" "item=feature:42"

# 2. update_feature — 열린 구간 없으면 done 이어도 조용
out=$(run "$(j s2 ${P}update_feature '{"feature_id":1,"status":"done"}' '{"id":1,"status":"done"}')")
expect "update_feature done, 구간 없음 → 없음" "$out" ""
# mark_work start → 열림
out=$(run "$(j s2 ${P}mark_work '{"cell":"impl","item":"feature:1","phase":"start"}' '{"ok":true}')")
expect "mark_work start 는 출력 없음" "$out" ""
out=$(run "$(j s2 ${S}update_feature '{"feature_id":1,"status_note":"\"status\":\"x\"","status":"done"}' '{"id":1,"status":"done"}')")
expect "update_feature done, 구간 열림 → 끝 기록 알림" "$out" "mark_work(phase=done)"
out=$(run "$(j s2 ${P}update_feature '{"feature_id":1,"status":"active"}' '{"id":1,"status":"done"}')")
expect "update_feature 비done(응답에 done 있어도) → 없음" "$out" ""
out=$(run "$(j s2 ${P}update_feature '{"feature_id":1,"status_note":"status done 으로 \"status\": \"done\""}')")
expect "update_feature 값 안의 \\\"status\\\":\\\"done\\\" 에 안 걸림" "$out" ""
# 열린 구간이 있으면 첫 Edit 알림 없음
out=$(run "$(j s2 Edit '{"file_path":"/tmp/a","old_string":"a","new_string":"b"}')")
expect "구간 열림 + Edit → 없음" "$out" ""
# mark_work done → 닫힘
run "$(j s2 ${S}mark_work '{"cell":"impl","item":"feature:1","phase":"done","summary":"x"}')" >/dev/null
out=$(run "$(j s2 ${P}update_feature '{"feature_id":1,"status":"done"}')")
expect "mark_work done 뒤 update_feature done → 없음" "$out" ""
# blocked 도 닫힘
run "$(j s2b ${P}mark_work '{"cell":"impl","item":"x","phase":"start"}')" >/dev/null
run "$(j s2b ${P}mark_work '{"cell":"impl","item":"x","phase":"blocked","summary":"y"}')" >/dev/null
out=$(run "$(j s2b ${P}update_feature '{"feature_id":1,"status":"done"}')")
expect "mark_work blocked 뒤 update_feature done → 없음" "$out" ""

# 3. 첫 쓰기 — 세션당 한 번
out=$(run "$(j s3 Write '{"file_path":"/tmp/a.md","content":"x"}' '{"filePath":"/tmp/a.md","type":"create"}')")
expect "첫 Write → 시작 기록 알림" "$out" "mark_work(phase=turn)"
valid_json "$out" && expect "첫 Write 출력 형식" ok ok || expect "첫 Write 출력 형식" "$out" "__형식불일치__"
out=$(run "$(j s3 Edit '{"file_path":"/tmp/a.md"}')")
expect "두 번째 Edit → 없음" "$out" ""
out=$(run "$(j s3 ${P}create_document '{"path":"x"}')")
expect "같은 세션 create_document → 없음" "$out" ""
out=$(run "$(j s4 ${S}update_document '{"id_or_path":"x","body":"y"}')")
expect "다른 세션 첫 update_document → 알림" "$out" "mark_work(phase=turn)"
out=$(run "$(j s5 MultiEdit '{"file_path":"/tmp/b"}')")
expect "MultiEdit 첫 회 → 알림" "$out" "열린 업무 구간이 없습니다"
out=$(run "$(j s6 NotebookEdit '{"notebook_path":"/tmp/n.ipynb"}')")
expect "NotebookEdit 첫 회 → 알림" "$out" "열린 업무 구간이 없습니다"
out=$(run "$(j s7 Read '{"file_path":"/tmp/a"}')")
expect "Read(쓰기 아님) → 없음" "$out" ""

# 4. 세션의 첫 요청(UserPromptSubmit) — Feature 1201
out=$(run "$(pr p1 '배송 정책서를 써 주세요')")
expect "첫 요청 → 시작 기록 알림" "$out" "mark_work(phase=turn)"
expect "첫 요청 알림에 my_map_works" "$out" "my_map_works"
expect "첫 요청 알림에 질문만이면 넘어간다" "$out" "질문에 답하기만 하는 대화면 넘어갑니다"
valid_prompt_json "$out" && expect "첫 요청 출력 형식(hookEventName=UserPromptSubmit)" ok ok || expect "첫 요청 출력 형식" "$out" "__형식불일치__"
case "$out" in *—*) expect "첫 요청 알림에 엠대시 없음" "$out" "__엠대시__" ;; *) expect "첫 요청 알림에 엠대시 없음" ok ok ;; esac
out=$(run "$(pr p1 '하나 더')")
expect "두 번째 요청 → 없음" "$out" ""
# 첫 요청 알림 뒤 기록이 없으면 첫 편집 때 한 번 더(문장이 다르다), 그 뒤로는 없음
out=$(run "$(j p1 Edit '{"file_path":"/tmp/a"}')")
expect "첫 요청 알림 + 기록 없음 + 첫 Edit → 다시 알림" "$out" "첫 요청 때 안내한 업무 기록이 아직 없습니다"
valid_json "$out" && expect "다시 알림 출력 형식(PostToolUse)" ok ok || expect "다시 알림 출력 형식" "$out" "__형식불일치__"
out=$(run "$(j p1 Write '{"file_path":"/tmp/b"}')")
expect "그다음 Write → 없음" "$out" ""
out=$(run "$(pr p1 '세 번째')")
expect "편집 알림 뒤 요청 → 없음" "$out" ""
# 첫 요청 알림 뒤 기록하고 끝냈으면(구간 닫힘) 첫 편집 알림 생략
run "$(pr p2 '정책서')" >/dev/null
run "$(j p2 ${P}mark_work '{"cell":"plan","item":"정책서","phase":"start"}')" >/dev/null
run "$(j p2 ${S}mark_work '{"cell":"plan","item":"정책서","phase":"done","summary":"x"}')" >/dev/null
out=$(run "$(j p2 Edit '{"file_path":"/tmp/a"}')")
expect "첫 요청 알림 + 기록 있음(닫힘) + 첫 Edit → 없음" "$out" ""
# 턴 선언은 구간을 열지 않는다 — 기록 있음만 남아 첫 편집 알림 생략
run "$(pr p9 '정책서')" >/dev/null
run "$(j p9 ${P}mark_work '{"cell":"plan","item":"정책서","phase":"turn","summary":"x"}')" >/dev/null
out=$(run "$(j p9 Edit '{"file_path":"/tmp/a"}')")
expect "첫 요청 알림 + turn 기록 + 첫 Edit → 없음" "$out" ""
[ -f "$STATE/p9.open" ] && expect "turn 은 열린 구간을 남기지 않음" "$(ls "$STATE")" "__open__" || expect "turn 은 열린 구간을 남기지 않음" ok ok
# 열린 구간이 있으면 첫 요청 알림 없음(재개한 세션 등)
run "$(j p3 ${P}mark_work '{"cell":"impl","item":"x","phase":"start"}')" >/dev/null
out=$(run "$(pr p3 '이어서')")
expect "열린 구간 있음 + 요청 → 없음" "$out" ""
# 첫 편집 알림을 이미 냈으면 요청 알림 없음
run "$(j p4 Write '{"file_path":"/tmp/a"}')" >/dev/null
out=$(run "$(pr p4 '다음')")
expect "첫 편집 알림 뒤 요청 → 없음" "$out" ""
# 요청 문장 안의 키 모양 문자열에 걸리지 않는다
out=$(run "$(pr p5 'see \"tool_name\":\"Edit\" and \"session_id\":\"zzz\"')")
expect "요청 문장 안의 tool_name 에 안 걸리고 첫 요청 알림" "$out" "my_map_works"
[ -f "$STATE/p5.prompted" ] && expect "요청 문장 안의 session_id 에 안 걸림" ok ok || expect "요청 문장 안의 session_id 에 안 걸림" "$(ls "$STATE")" "__p5__"
# 다른 이벤트 이름·도구 이름 없는 입력은 무시
out=$(printf '{"session_id":"p6","hook_event_name":"Stop"}' | "$SH" "$HOOK")
expect "도구 이름 없는 다른 이벤트 → 없음" "$out" ""
out=$(printf '{\n  "session_id": "p7",\n  "hook_event_name": "UserPromptSubmit",\n  "prompt": "a\\nb"\n}\n' | "$SH" "$HOOK")
expect "여러 줄 UserPromptSubmit JSON" "$out" "my_map_works"

# 끄는 길
out=$(printf '%s' "$(pr p8 '정책서')" | COFOUNDER_WORK_HOOK=off "$SH" "$HOOK")
expect "COFOUNDER_WORK_HOOK=off + 요청 → 없음" "$out" ""
out=$(printf '%s' "$(pr p8 '정책서')" | SPNV_EXECUTOR=intake "$SH" "$HOOK")
expect "SPNV_EXECUTOR + 요청 → 없음" "$out" ""
[ -f "$STATE/p8.prompted" ] && expect "끈 동안 요청 상태를 남기지 않음" "$(ls "$STATE")" "__없어야__" || expect "끈 동안 요청 상태를 남기지 않음" ok ok
out=$(printf '%s' "$(j s8 Write '{"file_path":"/tmp/a"}')" | COFOUNDER_WORK_HOOK=off "$SH" "$HOOK")
expect "COFOUNDER_WORK_HOOK=off → 없음" "$out" ""
out=$(printf '%s' "$(j s8 ${P}claim_feature '{"feature_id":5}')" | SPNV_EXECUTOR=impl "$SH" "$HOOK")
expect "SPNV_EXECUTOR 설정 → 없음" "$out" ""
out=$(run "$(j s8 Write '{"file_path":"/tmp/a"}')")
expect "끈 동안은 세션 기록을 남기지 않아 켜면 첫 Write 알림" "$out" "열린 업무 구간이 없습니다"

# 여러 줄로 들여 쓴 JSON 도 읽는다
out=$(printf '{\n  "session_id": "s9",\n  "tool_name": "%sclaim_feature",\n  "tool_input": {\n    "feature_id": 7\n  },\n  "tool_response": {}\n}\n' "$P" | "$SH" "$HOOK")
expect "여러 줄 JSON" "$out" "item=feature:7"

# 종료 코드는 늘 0
printf 'not json' | "$SH" "$HOOK"; rc=$?
[ "$rc" = 0 ] && expect "잘못된 입력도 종료 코드 0" ok ok || expect "잘못된 입력도 종료 코드 0" "rc=$rc" "__0__"

echo "---"; echo "통과 $pass · 실패 $fail"
[ "$fail" = 0 ]
