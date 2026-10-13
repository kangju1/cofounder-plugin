---
name: cofounder-setup
description: 이 컴퓨터의 Claude Code 가 AI 사용량(비용·토큰·도구 사용)을 조직의 업무 지도로 보내도록 한 번 설정합니다. 사용자가 「코파운더 설정」「사용량 수집 설정」을 요청하거나 업무 기록 중 수집 설정이 없다고 확인됐을 때 씁니다.
---

# 코파운더 사용량 수집 설정

이 컴퓨터의 Claude Code **사용자 설정 파일**(`settings.json`)의 `env` 에 수집 설정 일곱 줄을 넣는다. 셸 명령이나
스크립트 없이 파일 읽기(Read)·쓰기(Write) 도구로 한다. 데스크톱 앱에서도 같은 방법으로 한다.

수신 주소 — 「이미 설정됨」을 이 값으로 가린다:

```
https://cofounder-api.jengablock.com/api/otel
```

일곱 키 가운데 토큰과 상관없는 다섯 키는 값이 늘 같다(값은 모두 JSON 문자열 — `"1"` 이지 숫자 `1` 이 아니다):

```
CLAUDE_CODE_ENABLE_TELEMETRY = 1
OTEL_LOGS_EXPORTER           = otlp
OTEL_METRICS_EXPORTER        = otlp
OTEL_EXPORTER_OTLP_PROTOCOL  = http/json
OTEL_LOG_TOOL_DETAILS        = 1
```

지키는 것:

- 토큰 원문을 대화에 출력하지 않는다. 사용자에게 보여 주지도, 요약에 옮기지도 않는다.
- 사용자 설정 파일의 다른 내용은 한 글자도 바꾸지 않는다. `env` 안에서도 아래 일곱 키만 넣거나 바꾼다.
- 프로젝트 폴더의 `.claude/settings.json`·`.claude/settings.local.json` 에는 쓰지 않는다. 토큰이 저장소에 들어간다.

## 1. 설정 파일 위치

설정 폴더는 이 플러그인의 데이터 폴더 `${CLAUDE_PLUGIN_DATA}` 에서 끝의 `plugins/data/<이름>` 을 뗀
폴더다. 그 폴더의 `settings.json` 이 대상이다.

```
/Users/kim/.claude/plugins/data/cofounder-jengablock   →  /Users/kim/.claude/settings.json
C:\Users\kim\.claude\plugins\data\cofounder-jengablock →  C:\Users\kim\.claude\settings.json
```

위 데이터 폴더 경로가 `${` 로 시작하는 글자 그대로 보이거나(치환되지 않았으면) 경로에 `plugins` 다음
`data` 가 없으면 운영체제 기본 위치를 쓴다.

| 운영체제 | 사용자 설정 파일 |
|---|---|
| macOS | `/Users/<사용자 이름>/.claude/settings.json` |
| Linux | `/home/<사용자 이름>/.claude/settings.json` |
| Windows | `C:\Users\<사용자 이름>\.claude\settings.json` |

사용자 이름은 작업 폴더 경로 등 지금 보이는 경로에서 확인한다. 확인할 수 없으면 사용자에게 묻는다.

## 2. 지금 상태 확인

설정 파일을 읽는다(Read).

- **파일이 없다** → 3단계로 가서 토큰을 받고, 4단계에서 새 파일을 만든다(백업 없음).
- **JSON 으로 읽히지 않는다** → 고치지 말고 멈춘다. 「설정 파일 형식이 올바르지 않아 수집 설정을 넣지 않았습니다.
  `<경로>` 를 확인해 주세요.」라고 안내한다.
- **`env.OTEL_EXPORTER_OTLP_ENDPOINT` 가 수신 주소와 같고 `env.OTEL_EXPORTER_OTLP_HEADERS` 가
  `Authorization=Bearer ` 로 시작한다** → 토큰은 이미 들어 있다. **토큰을 새로 받지 않는다.**
  - 위 다섯 키가 모두 같은 값으로 있으면 아무것도 고치지 않고 아래처럼 안내하고 끝낸다.
  - 다섯 키 중 빠졌거나 값이 다른 것이 있으면, 4단계의 백업·합치기·확인·권한을 그 키들만 넣는 것으로 따른
    뒤 5단계로 안내한다.

  ```
  이 컴퓨터는 이미 사용량 수집이 설정되어 있습니다.
  - 설정 파일: <경로>
  - 방금 설정했다면 Claude Code 를 완전히 종료한 뒤 다시 열어야 보내지기 시작합니다.
  - 토큰은 코파운더 설정 → AI 사용량에서 확인하고 폐기할 수 있습니다.
  ```

  사용자가 토큰을 바꾸고 싶다고 하면(유출 등) `revoke_usage_token` 으로 폐기한 뒤 이 스킬을 처음부터 다시
  따른다.
- **수신 주소는 같은데 `OTEL_EXPORTER_OTLP_HEADERS` 가 없거나 `Authorization=Bearer ` 로 시작하지 않는다** →
  설정이 덜 들어간 상태다. 3단계로 간다.
- **`env.OTEL_EXPORTER_OTLP_ENDPOINT` 에 다른 주소가 있다** → 다른 곳으로 이미 사용량을 보내고 있다. Claude
  Code 는 한 곳으로만 보낸다. 지금 주소를 보여 주고 코파운더로 바꿀지 사용자에게 묻는다. 바꾸지 않겠다고
  하면 아무것도 고치지 않고 끝낸다.

## 3. 토큰 받기

코파운더 MCP 의 `issue_usage_token` 을 인자 없이 부른다(토큰 이름 `claude-code`).

- **「같은 이름의 수집 토큰이 이미 있습니다」로 거절되면** 다른 컴퓨터에 이미 설정했거나 예전 설정이 지워진
  경우다. 이름을 `claude-code-2`, `claude-code-3` … 으로 바꿔 다시 부른다(다섯 번까지). 끝 안내에 「쓰지 않는
  토큰은 코파운더 설정 → AI 사용량에서 폐기할 수 있습니다」를 한 줄 붙인다.
- **도구가 보이지 않거나 인증이 필요하다는 응답이면** 코파운더에 아직 로그인하지 않은 것이다. 파일을 고치지
  말고 멈춘 뒤 안내한다: 「코파운더 로그인이 필요합니다. `/mcp` 에서 `plugin:cofounder:cofounder` 를 골라
  로그인한 뒤 다시 실행해 주세요.」
- 응답의 `settings_env`(키 일곱 개)를 그대로 쓴다. 값을 고치거나 지어내지 않는다.

## 4. 설정 합치기

1. **백업** — 파일이 있었으면 바꾸기 전에 읽은 내용을 **그대로** 같은 폴더의 `settings.json.bak-cofounder` 로
   쓴다(Write). 그 이름의 파일이 이미 있으면 덮어쓰지 말고 `settings.json.bak-cofounder-2`, `-3` … 중 없는 이름을 쓴다.
2. **합친 내용 만들기** — 읽은 JSON 객체에서:
   - 맨 위 키는 전부 그대로 둔다(순서도 유지).
   - `env` 가 없으면 만든다. 있으면 기존 키를 전부 남기고, `settings_env` 의 일곱 키만 넣거나 덮어쓴다.
     있던 키는 그 자리에서 값만 바꾸고, 없던 키는 `env` 끝에 붙인다.
   - 기존 파일의 들여쓰기·줄 모양은 그대로 두고 `env` 안만 고친다. 새 파일이면 들여쓰기 2칸으로 쓴다.
   - 끝 쉼표·따옴표·괄호가 맞는 올바른 JSON 이어야 한다.
3. **쓰기** — 설정 파일에 쓴다(Write).
4. **확인** — 다시 읽고(Read) 아래를 확인한다. 하나라도 어긋나면 백업 내용으로 되돌려 쓰고 멈춘다.
   - JSON 으로 읽힌다
   - `env` 에 일곱 키가 `settings_env` 와 같은 값으로 있다(토큰을 새로 받지 않은 경우는 다섯 키가 위의 값과
     같고, `OTEL_EXPORTER_OTLP_ENDPOINT`·`OTEL_EXPORTER_OTLP_HEADERS` 가 바꾸기 전과 같다)
   - 바꾸기 전의 맨 위 키와 `env` 키가 모두 남아 있다
5. **파일 권한** — macOS·Linux 에서 셸 도구(Bash)를 쓸 수 있으면 설정 파일과 백업 파일을 본인만 읽게 한다:
   `chmod 600 "<설정 파일>" "<백업 파일>"`. 셸 도구를 쓸 수 없으면 건너뛰고, 끝 안내에 「설정 파일 권한은
   그대로 두었습니다」를 한 줄 붙인다. Windows 는 사용자 폴더 권한을 그대로 쓴다.

## 5. 끝 안내

토큰 없이, 아래 모양으로 짧게 알린다.

```
사용량 수집을 설정했습니다.
- 설정 파일: <경로>
- 바꾸기 전 파일: <백업 경로>   (새로 만들었으면 이 줄은 뺍니다)
- Claude Code 를 완전히 종료한 뒤 다시 열면 그때부터 사용량이 업무 지도로 보내집니다.
  데스크톱 앱은 앱을 종료했다가 다시 엽니다.
- 토큰은 코파운더 설정 → AI 사용량에서 확인하고 폐기할 수 있습니다.
```
