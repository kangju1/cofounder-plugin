# cofounder — Claude Code 플러그인

Claude Code(CLI·VS Code·Cursor·데스크톱 앱)에 한 번 설치하면 코파운더에 연결되고, AI 작업 내역과 사용량이
조직의 업무 지도에 쌓입니다.

## 설치

```bash
claude plugin marketplace add kangju1/cofounder-plugin
claude plugin install cofounder@jengablock
# Claude Code 를 다시 열고, /mcp 에서 plugin:cofounder:cofounder 를 골라 로그인한 뒤
/cofounder:cofounder-setup
```

데스크톱 앱·조직 일괄 배포·문제 해결은 설치 안내를 봅니다: https://spnv.jengablock.com/guides/claude-code

## 들어 있는 것

| 구성 | 하는 일 |
|---|---|
| MCP 서버 `cofounder` | `https://cofounder-api.jengablock.com/mcp/` 원격 연결(OAuth 로그인) |
| 스킬 `cofounder-setup` | 수집 토큰을 받아 사용자 설정(`~/.claude/settings.json`)의 `env` 에 수집 설정 일곱 줄을 넣습니다. 기존 설정은 그대로 두고 바꾸기 전 파일을 남깁니다 |
| 스킬 `cofounder-work` | 산출물 작업을 시작·끝낼 때 업무 지도의 칸에 기록하고, 끝낼 때 판단 요지와 산출물 위치를 남깁니다 |
| 훅 `hooks/hooks.json` → `hooks/work-reminder.sh` | 업무 기록 알림. 도구 호출 직후 Claude 에게 기록할 때라고 한 줄 알립니다. 작업을 막지 않고 서버를 부르지 않습니다 |

## 업무 기록 알림 훅

스킬 설명만으로는 업무 기록이 빠지는 일이 많아(2026-10-14 실측: 플러그인이 켜진 과제 세션 셋에서 기록 0건), 아래
때에 Claude 의 문맥에 알림 한 줄을 붙입니다(`PostToolUse` 훅의 `additionalContext`). 사용자 화면에 대화 메시지로
나오지 않고, 질문에 답만 하는 대화에서는 나오지 않습니다.

| 언제 | 조건 | 알림 |
|---|---|---|
| 과제 선점(`claim_feature`) 직후 | 늘 | 이 과제의 업무 시작을 기록합니다(`my_map_cells` → `mark_work start`, `item=feature:<번호>`) |
| 과제 완료(`update_feature` 의 `status=done`) 직후 | 이 세션에 열린 업무 구간이 있을 때 | 판단 요지·산출물과 함께 업무 끝을 기록합니다(`mark_work done`) |
| 파일 수정(Edit·Write·MultiEdit·NotebookEdit)·문서 작성(`create_document`·`update_document`) 직후 | 열린 구간이 없을 때, 세션당 한 번 | 산출물 작업이면 업무 시작을 기록합니다 |

- 코파운더 도구는 플러그인 연결(`mcp__plugin_cofounder_cofounder__*`)과 프로젝트 `.mcp.json` 의 `spnv-platform` 연결
  (`mcp__spnv-platform__*`) 이름을 둘 다 잡습니다.
- 열린 구간은 훅이 스스로 기억합니다. `mark_work` 호출을 같은 훅이 보고 세션별 상태 파일(임시 폴더
  `${TMPDIR:-/tmp}/cofounder-work-hook/<세션 id>.*`)에 start 면 열림, done·blocked 면 닫힘을 적습니다.
- **끄기**: 환경 변수 `COFOUNDER_WORK_HOOK=off`(예: 사용자 설정 `env` 에 넣기). `SPNV_EXECUTOR` 가 설정된
  세션(타이머·이벤트 실행기)에서도 아무것도 내지 않습니다.

### 실행 환경

훅은 POSIX `sh` 스크립트이고 `tr`·`sed`·`mkdir`·`rm` 만 씁니다. jq·Python·Node 는 필요 없습니다.

| 환경 | 동작 |
|---|---|
| macOS · Linux · WSL | 동작합니다(훅 명령은 `sh -c` 로 실행됩니다) |
| Windows + Git for Windows | 동작합니다(훅 명령은 Git Bash 로 실행되고, Git Bash 에 `sh`·`sed`·`tr` 이 들어 있습니다) |
| Windows, Git for Windows 없음 | **알림이 나오지 않습니다.** 이때 Claude Code 는 훅 명령을 PowerShell 로 실행하는데 `sh` 가 없어 훅이 실패합니다. 실패는 막지 않는 오류라 작업은 그대로 진행되지만, 대화에 `hook error` 표시가 남을 수 있습니다. Git for Windows 를 설치하면 알림이 동작합니다 |

근거: Claude Code 훅 문서(https://code.claude.com/docs/en/hooks) — 「The `command` string is passed to a shell:
`sh -c` on macOS and Linux, Git Bash on Windows, or PowerShell when Git Bash isn't installed.」

## 런타임

설치한 컴퓨터에 Python·Node 같은 런타임이 없어도 됩니다. 알림 훅은 위 표의 셸만 씁니다.

## 어느 세션이 집계되나

수집 설정은 사용자 설정에 들어가므로 그 컴퓨터의 모든 Claude Code 창이 사용량을 보냅니다. 조직 설정
「작업 기록 플러그인이 켜진 프로젝트의 세션만 집계」(기본 켜짐, 웹 설정 · AI 사용량 탭)가 켜져 있으면 서버는
**이 플러그인이 켜진 세션**의 사용량만 받습니다. 업무 지도에 남길 프로젝트에서만 쓰려면 그 프로젝트 범위로
설치합니다(`claude plugin install cofounder@jengablock --scope project`).

어느 쪽이든 `cofounder-work` 의 시작~끝 기록 사이에 든 사용량만 그 칸·일감에 집계됩니다. 기록 밖의 사용량은
집계하지 않습니다.

## 개발

정본은 `kangju1/supernova-platform` 의 `claude-plugin/` 이다. 공개 배포처 `kangju1/cofounder-plugin` 은 그 폴더의
사본이고, `claude-plugin/publish.sh` 로만 갱신한다(이력은 옮기지 않는다 — 플랫폼 커밋 메시지에 고객 이름이 섞인다).
플러그인을 바꾸면 `plugins/cofounder/.claude-plugin/plugin.json` 의 버전을 올리고 main 에 반영한 뒤 publish 한다.

```bash
claude plugin validate ./claude-plugin
claude plugin validate ./claude-plugin/plugins/cofounder --strict
sh claude-plugin/tests/work-reminder.test.sh   # 알림 훅 단위 시험
```

마켓플레이스 이름 `jengablock`, 플러그인 이름 `cofounder`. 스킬은 `/cofounder:<스킬>` 로 부릅니다.
