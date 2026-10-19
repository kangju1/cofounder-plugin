#!/bin/sh
# 업무 기록 알림 — UserPromptSubmit·PostToolUse 훅(막지 않는다). 플랫폼 Feature 1197·1201·1223.
#
# 기록의 기본은 턴 선언이다(Feature 1223): 그 요청에서 한 일을 mark_work(phase=turn) 으로
# 남긴다. 한 요청 안에서 업무가 바뀌면 바뀐 그 자리에서 앞 업무를 남기고, 요청을 마칠 때 마지막
# 업무를 남긴다(Feature 1262) — 서버가 한 요청의 턴 선언들을 호출 순서대로 나눠 받기 때문이다.
# 이 훅은 그것을 미리 알리고, 빠뜨린 턴은 턴 끝 관문(turn-gate.sh, Stop 훅)이 한 번 돌려보낸다.
#
# 요청 하나가 들어온 직후, 또는 도구 호출 하나가 끝난 직후 stdin 으로 그 JSON 을 받아, 업무 기록
# (mark_work)을 할 때면 추가 문맥(additionalContext) 한 줄을 낸다. 서버를 부르지 않는다.
#
#   세션의 첫 요청(UserPromptSubmit) → 열린 구간이 없으면 세션당 한 번 턴 선언 알림
#   claim_feature 성공            → 이 과제로 턴 선언하라는 알림
#   update_feature status=done    → 열린 구간이 있으면 끝 기록 알림
#   첫 파일 수정·문서 작성        → 열린 구간이 없으면 세션당 한 번 턴 선언 알림.
#                                   첫 요청 알림을 냈고 그 뒤 mark_work 가 한 번이라도 있었으면 생략
#   mark_work                     → 알림 없이 열림(start)·닫힘(done·blocked)과 「기록 있음」만 적어 둔다
#                                   (turn 은 열고 닫지 않는다 — 그 자리에서 닫힌 구간이다)
#
# 상태 파일(세션별): <세션>.open 열린 구간 · <세션>.nudged 첫 편집 알림 냄 ·
#                    <세션>.prompted 첫 요청 알림 냄 · <세션>.marked 이 세션에 mark_work 있음
#
# 런타임 요구 없음: POSIX sh 와 기본 도구(tr·sed·mkdir·rm)만 쓴다. jq·Python·Node 를 쓰지 않는다.
# 끄기: COFOUNDER_WORK_HOOK=off, 또는 SPNV_EXECUTOR 가 비어 있지 않은 세션(타이머·이벤트 실행기).
# 어떤 경우에도 종료 코드는 0 이다 — 알림이 작업을 막지 않는다.

case "${COFOUNDER_WORK_HOOK:-}" in
  off|OFF|Off|0|false|FALSE|no|NO) exit 0 ;;
esac
[ -n "${SPNV_EXECUTOR:-}" ] && exit 0

input=$(cat | tr '\r\n' '  ')

# 첫 등장 기준이 아니라 그 구간에서 마지막 등장 — 키 이름 앞뒤의 따옴표가 escape 되지 않은 것만 맞는다
# (문자열 값 안의 \"key\" 는 맞지 않는다).
str_field() {
  printf '%s' "$2" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

tool=$(str_field tool_name "$input")
event=
if [ -z "$tool" ]; then
  # 도구 이름이 없는 입력은 UserPromptSubmit 만 받는다. prompt 값 안의 따옴표는 escape 되어 있어
  # 요청 문장이 키 이름처럼 보여도 여기 걸리지 않는다.
  event=$(str_field hook_event_name "$input")
  [ "$event" = UserPromptSubmit ] || exit 0
fi

# tool_input 객체만 떼어 낸다(tool_response 안의 같은 키에 걸리지 않게).
ti=$(printf '%s' "$input" | sed 's/.*"tool_input"[[:space:]]*:\(.*\)/\1/; s/"tool_response"[[:space:]]*:.*//')

sid=$(str_field session_id "$input" | tr -cd 'A-Za-z0-9_-')
[ -n "$sid" ] || sid=unknown
dir="${COFOUNDER_WORK_HOOK_STATE_DIR:-${TMPDIR:-/tmp}/cofounder-work-hook}"
open_f="$dir/$sid.open"
nudged_f="$dir/$sid.nudged"
prompted_f="$dir/$sid.prompted"
marked_f="$dir/$sid.marked"

emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "${event:-PostToolUse}" "$1"
}

if [ "$event" = UserPromptSubmit ]; then
  [ -f "$open_f" ] && exit 0
  [ -f "$prompted_f" ] && exit 0
  [ -f "$nudged_f" ] && exit 0
  mkdir -p "$dir" 2>/dev/null || exit 0
  : > "$prompted_f" 2>/dev/null || exit 0
  emit "이 세션에는 아직 업무 기록이 없습니다. 이 요청을 처리하며 도구를 쓰면 한 일을 mark_work(phase=turn) 으로 남깁니다. 한 요청 안에서 업무가 바뀌면(예: 요청 접수를 마치고 구현을 시작할 때) 바뀐 그 자리에서 앞 업무를 남기고, 요청을 마칠 때 마지막 업무를 남깁니다. 서버는 한 요청의 선언들을 호출 순서대로 나눠 받아, 각 선언에 앞 선언 뒤부터 그 호출까지를 붙입니다. my_map_works 로 맞는 업무를 고르고 my_map_cells(map_slug, work) 로 칸을 고릅니다. 맞는 칸이 없으면 cell 대신 no_fitting_cell=true 를 줍니다. 도구 없이 질문에 답하기만 하는 대화면 넘어갑니다. 이 안내는 세션에 한 번만 나옵니다(cofounder-work 스킬)."
  exit 0
fi

case "$tool" in
  *__mark_work)
    phase=$(str_field phase "$ti")
    mkdir -p "$dir" 2>/dev/null || exit 0
    : > "$marked_f" 2>/dev/null
    case "$phase" in
      start) : > "$open_f" 2>/dev/null ;;
      done|blocked) rm -f "$open_f" 2>/dev/null ;;
    esac
    exit 0
    ;;
  *__claim_feature)
    fid=$(printf '%s' "$ti" | sed -n 's/.*"feature_id"[[:space:]]*:[[:space:]]*"\{0,1\}\([0-9][0-9]*\).*/\1/p')
    [ -n "$fid" ] || fid='<과제 번호>'
    emit "과제 ${fid} 를 선점했습니다. 이 요청에서 선점 전까지 다른 업무(요청 접수 등)를 했으면 지금 그 업무를 mark_work(phase=turn) 으로 남기고 다음 업무를 시작합니다. 이 과제에서 한 일은 업무가 바뀌는 자리나 요청을 마칠 때 mark_work(phase=turn, cell=<칸 키>, item=feature:${fid}) 로 남깁니다. my_map_works 로 업무를, my_map_cells(map_slug, work) 로 칸을 확인합니다. 이 과제를 앞 요청부터 하고 있었으면 claim_feature 의 from_request 로 몇 번째 요청부터였는지 알릴 수 있습니다(cofounder-work 스킬)."
    exit 0
    ;;
  *__update_feature)
    status=$(str_field status "$ti")
    [ "$status" = done ] || exit 0
    [ -f "$open_f" ] || exit 0
    emit "과제를 완료로 바꿨습니다. 열린 업무 구간을 끝냅니다 — 시작과 같은 cell·item 으로 mark_work(phase=done) 를 부르고, summary 에 무엇을 근거로 어떻게 정했는지, evidence 에 산출물 경로나 링크를 적습니다(cofounder-work 스킬)."
    exit 0
    ;;
  Edit|Write|MultiEdit|NotebookEdit|*__create_document|*__update_document)
    [ -f "$open_f" ] && exit 0
    [ -f "$nudged_f" ] && exit 0
    if [ -f "$prompted_f" ]; then
      # 첫 요청 때 이미 안내했다. 그 뒤 기록이 한 번이라도 있었으면 Claude 가 안내를 따른 것이라 다시 내지 않고,
      # 기록이 한 번도 없었으면 놓친 것으로 보고 첫 편집 때 한 번 더 낸다.
      [ -f "$marked_f" ] && exit 0
      mkdir -p "$dir" 2>/dev/null || exit 0
      : > "$nudged_f" 2>/dev/null || exit 0
      emit "첫 요청 때 안내한 업무 기록이 아직 없습니다. 한 일을 mark_work(phase=turn) 으로 남깁니다. 이 요청 안에서 업무가 바뀌면 바뀐 그 자리에서 앞 업무를 남기고, 요청을 마칠 때 마지막 업무를 남깁니다. my_map_works 로 업무를, my_map_cells(map_slug, work) 로 칸을 고르고, 맞는 칸이 없으면 no_fitting_cell=true 를 줍니다. 이 안내는 다시 나오지 않습니다(cofounder-work 스킬)."
      exit 0
    fi
    mkdir -p "$dir" 2>/dev/null || exit 0
    : > "$nudged_f" 2>/dev/null || exit 0
    emit "이 세션에는 열린 업무 구간이 없습니다. 한 일을 mark_work(phase=turn) 으로 남깁니다. 이 요청 안에서 업무가 바뀌면 바뀐 그 자리에서 앞 업무를 남기고, 요청을 마칠 때 마지막 업무를 남깁니다. my_map_works 로 업무를, my_map_cells(map_slug, work) 로 칸을 고르고, 맞는 칸이 없으면 no_fitting_cell=true 를 줍니다. 이 안내는 세션에 한 번만 나옵니다(cofounder-work 스킬)."
    exit 0
    ;;
esac
exit 0
