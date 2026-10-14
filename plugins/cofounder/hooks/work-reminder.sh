#!/bin/sh
# 업무 기록 알림 — UserPromptSubmit·PostToolUse 훅(막지 않는다). 플랫폼 Feature 1197·1201.
#
# 요청 하나가 들어온 직후, 또는 도구 호출 하나가 끝난 직후 stdin 으로 그 JSON 을 받아, 업무 기록
# (mark_work)을 할 때면 추가 문맥(additionalContext) 한 줄을 낸다. 서버를 부르지 않는다.
#
#   세션의 첫 요청(UserPromptSubmit) → 열린 구간이 없으면 세션당 한 번 시작 기록 알림
#   claim_feature 성공            → 업무 시작을 기록하라는 알림
#   update_feature status=done    → 열린 구간이 있으면 끝 기록 알림
#   첫 파일 수정·문서 작성        → 열린 구간이 없으면 세션당 한 번 시작 기록 알림.
#                                   첫 요청 알림을 냈고 그 뒤 mark_work 가 한 번이라도 있었으면 생략
#   mark_work                     → 알림 없이 열림(start)·닫힘(done·blocked)과 「기록 있음」만 적어 둔다
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
  emit "이 세션에는 아직 업무 기록이 없습니다. 이 요청이 산출물을 만들거나 업무를 처리하는 일이면 업무 시작을 먼저 기록합니다: my_map_cells 로 칸을 고르고 mark_work(phase=start) 를 부릅니다. 지도가 여러 장이면 응답의 other_sheets 로 다른 지도도 봅니다. 질문에 답하기만 하는 대화면 넘어갑니다. 이 안내는 세션에 한 번만 나옵니다(cofounder-work 스킬)."
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
    emit "과제 ${fid} 를 선점했습니다. 작업에 들어가기 전에 업무 시작을 기록합니다 — my_map_cells 로 칸을 확인하고 mark_work(phase=start, cell=<칸 키>, item=feature:${fid}) 를 부릅니다. 다른 일감의 구간이 열려 있으면 그 구간을 먼저 끝냅니다(cofounder-work 스킬)."
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
      emit "첫 요청 때 안내한 업무 시작 기록이 아직 없습니다. 지금 작업이 산출물을 만드는 일이면 my_map_cells 로 칸을 고르고 mark_work(phase=start) 를 부릅니다. 산출물 작업이 아니면 넘어갑니다. 이 안내는 다시 나오지 않습니다(cofounder-work 스킬)."
      exit 0
    fi
    mkdir -p "$dir" 2>/dev/null || exit 0
    : > "$nudged_f" 2>/dev/null || exit 0
    emit "이 세션에는 열린 업무 구간이 없습니다. 지금 작업이 산출물을 만드는 일이면 업무 시작을 먼저 기록합니다 — my_map_cells 로 칸을 고르고 mark_work(phase=start) 를 부릅니다. 산출물 작업이 아니면 넘어갑니다. 이 안내는 세션에 한 번만 나옵니다(cofounder-work 스킬)."
    exit 0
    ;;
esac
exit 0
