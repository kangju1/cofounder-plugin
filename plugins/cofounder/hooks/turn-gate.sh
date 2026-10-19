#!/bin/sh
# 턴 끝 관문 — Stop 훅. 플랫폼 Feature 1223.
#
# 막는 대상은 사람이 아니라 AI 의 턴이다. 사용자는 아무것도 하지 않아도 되고, 이 훅은 사용자의 입력을
# 막지 않는다. Claude 가 답을 마치려는 순간(Stop) 한 번 돌려보내, 그 턴에서 한 일을 업무 지도에
# 선언(mark_work phase=turn)하게 한다. 선언은 Claude 가 도구 하나를 부르면 끝난다.
#
# 판정: Stop 입력 JSON 의 transcript_path(JSONL)를 읽어, 마지막 「진짜 사용자 요청」(도구 결과가 아닌
# user 메시지) 뒤에 assistant 의 tool_use 가 있었는지, 그중 이름이 mark_work 로 끝나는 것이 있었는지
# 본다.
#   도구를 안 썼다(답만 했다)          → 통과
#   도구를 썼고 mark_work 도 불렀다    → 통과
#   도구를 썼는데 mark_work 가 없다    → {"decision":"block","reason":…} 로 한 번 돌려보낸다
#   stop_hook_active=true(이미 한 번 돌려보낸 턴) → 통과 — 같은 턴을 두 번 막지 않는다
#
# 흔적(도구 이름)으로 업무를 짐작하지 않는다 — 어느 칸의 일인지는 Claude 가 선언한다.
# 판정은 선언이 하나라도 있으면 통과다. 업무가 바뀐 자리에서 선언하라는 것(Feature 1262)은 돌려보내는
# 문구로만 알린다 — 서버는 한 요청의 선언들을 호출 순서대로 나눠 받으므로, 끝에서 몰아 부른 선언은
# 업무별로 나뉘지 않는다.
# 앞 턴의 선언을 다음 턴으로 이어 쓰지 않는다 — 턴마다 본다.
#
# 런타임 요구 없음: POSIX sh 와 기본 도구(sed·awk)만 쓴다. jq·Python·Node 를 쓰지 않는다.
# 끄기: COFOUNDER_WORK_HOOK=off, 또는 SPNV_EXECUTOR 가 비어 있지 않은 세션(타이머·이벤트 실행기).
# 읽을 수 없는 입력·없는 기록 파일은 통과시킨다. 종료 코드는 늘 0 이다.

case "${COFOUNDER_WORK_HOOK:-}" in
  off|OFF|Off|0|false|FALSE|no|NO) exit 0 ;;
esac
[ -n "${SPNV_EXECUTOR:-}" ] && exit 0

input=$(cat | tr '\r\n' '  ')

active=$(printf '%s' "$input" | sed -n 's/.*"stop_hook_active"[[:space:]]*:[[:space:]]*\([a-z]*\).*/\1/p')
[ "$active" = true ] && exit 0

transcript=$(printf '%s' "$input" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
# JSON 의 \/ 와 \\ 를 푼다(Windows 경로).
transcript=$(printf '%s' "$transcript" | sed 's#\\/#/#g; s#\\\\#\\#g')
[ -n "$transcript" ] && [ -r "$transcript" ] || exit 0

# 줄마다 한 메시지. 바깥 메시지의 역할은 "message":{… "role":"…" 로 본다(본문 안 문자열의 따옴표는
# escape 되어 있어 걸리지 않는다). 하위 에이전트 줄(isSidechain:true)은 보지 않는다.
verdict=$(awk '
  /"isSidechain":true/ { next }
  /"message":[{]"role":"user"/ {
    if ($0 ~ /"content":[[][{]("type":"tool_result"|"tool_use_id")/) next
    if ($0 ~ /"isCompactSummary":true/) next
    tools = 0; marked = 0; next
  }
  /"message":[{][^{]*"role":"assistant"/ {
    if ($0 ~ /"type":"tool_use"/) {
      tools = 1
      if ($0 ~ /"name":"[^"]*mark_work"/) marked = 1
    }
  }
  END { printf "%d %d", tools, marked }
' "$transcript" 2>/dev/null)

case "$verdict" in
  "1 0") ;;
  *) exit 0 ;;
esac

printf '%s\n' '{"decision":"block","reason":"이 턴에서 도구를 썼는데 업무 기록이 없습니다. 답을 마치기 전에 이 요청에서 한 일을 mark_work(phase=\"turn\", cell=<칸 키>, item=<일감>, summary=<무엇을 근거로 어떻게 정했는지 한두 줄>, evidence=[<산출물 경로·링크>]) 로 남깁니다. 칸은 my_map_works 로 업무를, my_map_cells(map_slug, work) 로 칸을 고릅니다. 맞는 칸이 없으면 cell 대신 no_fitting_cell=true 를 줍니다. 서버는 한 요청의 선언들을 호출 순서대로 나눠 받아 각 선언에 앞 선언 뒤부터 그 호출까지를 붙이므로, 지금 남기는 선언은 이 요청 전체를 덮습니다. 업무별로 나누려면 다음 요청부터 업무가 바뀐 그 자리에서 앞 업무를 남기고, 요청을 마칠 때 마지막 업무를 남깁니다. 기록한 뒤 답을 마칩니다(cofounder-work 스킬)."}'
exit 0
