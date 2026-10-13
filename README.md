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

훅·실행 파일은 없습니다. 설치한 컴퓨터에 Python·Node 같은 런타임이 없어도 됩니다.

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
```

마켓플레이스 이름 `jengablock`, 플러그인 이름 `cofounder`. 스킬은 `/cofounder:<스킬>` 로 부릅니다.
