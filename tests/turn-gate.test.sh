#!/bin/sh
# 턴 끝 관문 훅(plugins/cofounder/hooks/turn-gate.sh) 단위 시험 — 플랫폼 Feature 1223·1262.
# 쓰는 법: sh claude-plugin/tests/turn-gate.test.sh   (dash 로도: dash claude-plugin/tests/turn-gate.test.sh)
# 표본 대화 기록(JSONL)과 Stop 입력 JSON 을 넣고 막는지(block) 통과하는지 본다. 파일은 임시 폴더에만 쓴다.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HOOK="$HERE/../plugins/cofounder/hooks/turn-gate.sh"
SH="${TEST_SH:-sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset COFOUNDER_WORK_HOOK SPNV_EXECUTOR

pass=0; fail=0
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

# 실측 모양의 줄(Claude Code 대화 기록 — 한 줄 한 메시지, 키 순서도 실측과 같다).
U() { # 사람 요청
  printf '{"parentUuid":null,"isSidechain":false,"promptId":"p","type":"user","message":{"role":"user","content":[{"type":"text","text":"%s"}]},"uuid":"u"}\n' "$1"
}
Us() { # 문자열 본문 요청
  printf '{"parentUuid":null,"isSidechain":false,"type":"user","message":{"role":"user","content":"%s"},"uuid":"u"}\n' "$1"
}
R() { # 도구 결과(두 키 순서 모두 실측에 있다)
  printf '{"parentUuid":"a","isSidechain":false,"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]},"uuid":"r"}\n'
  printf '{"parentUuid":"a","isSidechain":false,"type":"user","message":{"role":"user","content":[{"tool_use_id":"t2","type":"tool_result","content":"{\\"type\\":\\"user\\"}"}]},"uuid":"r2"}\n'
}
T() { # 도구 호출
  printf '{"parentUuid":"u","isSidechain":false,"message":{"model":"claude","id":"m","type":"message","role":"assistant","content":[{"type":"tool_use","id":"t1","name":"%s","input":{"x":"\\"name\\":\\"mark_work\\""}}]},"type":"assistant","uuid":"a"}\n' "$1"
}
A() { # 글로만 답한 줄
  printf '{"parentUuid":"u","isSidechain":false,"message":{"model":"claude","id":"m","type":"message","role":"assistant","content":[{"type":"text","text":"%s"}]},"type":"assistant","uuid":"a"}\n' "$1"
}
S() { # 하위 에이전트 줄
  printf '{"parentUuid":"u","isSidechain":true,"message":{"model":"claude","id":"m","type":"message","role":"assistant","content":[{"type":"tool_use","id":"t9","name":"Bash","input":{}}]},"type":"assistant","uuid":"s"}\n'
}
stop() { # 기록파일 [stop_hook_active]
  printf '{"session_id":"s1","transcript_path":"%s","cwd":"/tmp","permission_mode":"default","hook_event_name":"Stop","stop_hook_active":%s}' \
    "$1" "${2:-false}" | "$SH" "$HOOK"
}
P=mcp__plugin_cofounder_cofounder__
S2=mcp__spnv-platform__

f="$TMP/a.jsonl"; { U '배송 정책서 써 줘'; T Write; R; A '썼습니다'; } > "$f"
out=$(stop "$f")
expect "도구를 쓰고 기록 없음 → 막음" "$out" '"decision":"block"'
expect "막을 때 mark_work turn 안내" "$out" 'mark_work(phase=\"turn\"'
expect "막을 때 no_fitting_cell 안내" "$out" "no_fitting_cell=true"
expect "막을 때 업무가 바뀐 자리에서 선언 안내(Feature 1262)" "$out" "업무가 바뀐 그 자리에서 앞 업무를 남기고, 요청을 마칠 때 마지막 업무를 남깁니다"
expect "막을 때 서버가 호출 순서대로 나눠 받는다는 근거" "$out" "호출 순서대로 나눠 받아"
case "$out" in *—*) expect "안내에 엠대시 없음" "$out" "__엠대시__" ;; *) expect "안내에 엠대시 없음" ok ok ;; esac
case "$out" in '{"decision":"block","reason":"'*'"}') expect "출력 형식" ok ok ;; *) expect "출력 형식" "$out" "__형식불일치__" ;; esac

out=$(stop "$f" true)
expect "stop_hook_active=true → 통과(두 번 막지 않음)" "$out" ""

f="$TMP/b.jsonl"; { U '써 줘'; T Edit; R; T "${P}mark_work"; R; A '기록했습니다'; } > "$f"
expect "도구 + 플러그인 이름 mark_work → 통과" "$(stop "$f")" ""
f="$TMP/b2.jsonl"; { U '써 줘'; T Bash; R; T "${S2}mark_work"; R; } > "$f"
expect "도구 + spnv-platform 이름 mark_work → 통과" "$(stop "$f")" ""

f="$TMP/c.jsonl"; { U '이게 뭐예요'; A '설명입니다'; } > "$f"
expect "도구 없이 답만 → 통과" "$(stop "$f")" ""

# 앞 요청에서 기록했어도 이번 요청에서 기록이 없으면 막는다(이어 쓰지 않는다)
f="$TMP/d.jsonl"; { U '하나'; T Edit; R; T "${P}mark_work"; R; Us '둘'; T Bash; R; A '끝'; } > "$f"
expect "앞 요청 기록은 이번 요청에 안 이어짐 → 막음" "$(stop "$f")" '"decision":"block"'
# 앞 요청에서 도구를 썼어도 이번 요청은 답만이면 통과
f="$TMP/e.jsonl"; { U '하나'; T Edit; R; Us '고마워요'; A '네'; } > "$f"
expect "앞 요청 도구 + 이번 요청 답만 → 통과" "$(stop "$f")" ""

# 도구 결과(user 줄)는 요청 경계가 아니다 — 도구 결과 안의 \"type\":\"user\" 에도 안 걸린다
f="$TMP/g.jsonl"; { U '해 줘'; T "${P}mark_work"; R; T Bash; R; A '끝'; } > "$f"
expect "같은 요청 앞쪽의 mark_work 도 센다 → 통과" "$(stop "$f")" ""

# 도구 입력 문자열 안의 \"name\":\"mark_work\" 는 기록으로 안 센다
f="$TMP/h.jsonl"; { U '해 줘'; T Write; R; } > "$f"
expect "입력 값 안의 mark_work 글자에 안 속음 → 막음" "$(stop "$f")" '"decision":"block"'

# 하위 에이전트 줄은 보지 않는다
f="$TMP/i.jsonl"; { U '물어볼게요'; S; A '답'; } > "$f"
expect "하위 에이전트 도구만 → 통과" "$(stop "$f")" ""

# 없는 기록 파일·잘못된 입력은 통과
expect "없는 기록 파일 → 통과" "$(stop "$TMP/none.jsonl")" ""
out=$(printf 'not json' | "$SH" "$HOOK"); rc=$?
expect "잘못된 입력 → 통과" "$out" ""
[ "$rc" = 0 ] && expect "종료 코드 0" ok ok || expect "종료 코드 0" "rc=$rc" "__0__"

# 끄는 길
f="$TMP/a.jsonl"
out=$(printf '{"session_id":"s1","transcript_path":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$f" | COFOUNDER_WORK_HOOK=off "$SH" "$HOOK")
expect "COFOUNDER_WORK_HOOK=off → 통과" "$out" ""
out=$(printf '{"session_id":"s1","transcript_path":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$f" | SPNV_EXECUTOR=impl "$SH" "$HOOK")
expect "SPNV_EXECUTOR → 통과" "$out" ""

# 여러 줄로 들여 쓴 Stop 입력도 읽는다
out=$(printf '{\n  "session_id": "s1",\n  "transcript_path": "%s",\n  "stop_hook_active": false\n}\n' "$f" | "$SH" "$HOOK")
expect "여러 줄 Stop 입력" "$out" '"decision":"block"'

echo "---"; echo "통과 $pass · 실패 $fail"
[ "$fail" = 0 ]
