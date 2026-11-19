# 성취기준에서 지도안·활동지까지 (hwpx)

2022 개정 교육과정 성취기준 코드(예: `9과15-01`)를 주면 AI가 한 차시 수업을 설계하고, **지도안**과 **학생 활동지**를 한글(hwpx) 파일로 만들어 주는 스킬입니다. 스킬은 AI에게 작업 순서를 알려 주는 파일입니다.

- 지도안은 동봉한 `지도안 서식.hwpx`에 맞춰 칸을 채우고, 활동 수에 따라 줄을 늘립니다.
- 활동지는 지도안과 같은 글꼴로 만들며 질문, 점선 쓰기 칸, 표, 스스로 점검표가 들어갑니다.
- 지도안과 활동지는 `design.json` 한 파일에서 함께 나오므로 활동 이름과 순서가 늘 맞습니다.
- 성취기준 원문, 평가 증거, 흔한 오개념, 선수 학습 자료(초1~고3 4,451개)가 함께 들어 있습니다.

견본: [도덕 9도01-01](skills/suup-jejak/examples/도덕-가치관), [과학 9과15-01 1차시](skills/suup-jejak/examples/과학-9과15-01-1차시) (각 폴더에 hwpx와 PDF가 있습니다)

## 준비물

- 스킬을 지원하는 AI 작업 환경: Claude Code(데스크톱 앱 포함), Codex, Antigravity 중 하나
- 결과를 열어 볼 한글(한컴오피스) 또는 hwpx를 여는 프로그램
- **Windows에서는 따로 설치할 것이 없습니다.** Python이나 Node.js가 없어도 됩니다.

## 어떻게 동작하나

스킬을 설치한 뒤 AI에게 "지도안 만들어 줘"라고 하면, AI가 스킬 안의 도구를 실행해 hwpx 파일을 만듭니다. 사용자가 명령 창을 열 일은 없습니다. 같은 일을 하는 도구가 두 벌 들어 있고, AI가 실행 환경을 보고 하나를 고릅니다.

| 실행 환경 | 예 | AI가 쓰는 도구 | 필요한 것 |
|---|---|---|---|
| **Windows PC** | Claude 데스크톱 앱(Code), Claude Code, Codex, Antigravity | `scripts/suup.ps1` (Windows에 기본으로 들어 있는 PowerShell 5.1) | 없음 |
| macOS·Linux PC | 같은 앱을 macOS·Linux에서 쓸 때 | `scripts/*.py`, `scripts/standards.mjs` | Python 3.8 이상, Node.js 18 이상 |
| 클라우드 샌드박스 | claude.ai 웹·앱 채팅에 올린 스킬 | `scripts/*.py`, `scripts/standards.mjs` | 없음 (샌드박스에 미리 깔려 있음) |

- 두 도구가 만드는 hwpx 내용은 같습니다. 자동 테스트가 매번 견본과 바이트 단위로 비교합니다.
- **hwpx 만들기에는 한글 프로그램이 필요 없습니다.** 그래서 만들 때 한글의 '접근 허용' 확인 창도 뜨지 않습니다.
- **PDF 확인**은 AI가 결과를 눈으로 검토하는 선택 단계로, Windows PC와 한컴오피스가 있어야 합니다. 할 수 없는 환경(macOS·Linux, 클라우드 샌드박스, 한글 자동화를 막는 샌드박스)에서는 건너뛰고 구조 점검 결과만 알려 줍니다. 이때는 한글에서 직접 열어 보세요.
- 결과 내용은 AI마다 다릅니다(차시 나누기, 활동 구성). 형식과 지도안·활동지 연결은 도구가 점검합니다.

## 한글 보안 모듈

한글 자동화로 파일을 열 때 보안 모듈이 없으면 한글이 '접근 허용' 확인 창을 띄웁니다. 그래서 PDF 확인을 하려면 보안 모듈이 등록되어 있어야 합니다.

- 스킬에 보안 모듈(`bin/FilePathCheckerModule.dll`)이 들어 있어서, **Windows에서는 설치할 때 AI가 자동으로 등록합니다**(아래 설치 방법). Python 등 다른 프로그램은 필요 없습니다.
- DLL은 `%LOCALAPPDATA%\HNC\Automation_Module`에 복사되고 `HKEY_CURRENT_USER\Software\HNC\HwpAutomation\Modules`에 등록됩니다. 관리자 권한은 필요 없고, 스킬 폴더를 옮기거나 지워도 등록은 유지됩니다.
- 이미 다른 프로그램(예: 보안인증등록.exe)으로 등록해 둔 PC는 그 등록을 그대로 씁니다.
- 등록하면 이 PC에서 한글 자동화를 쓰는 다른 프로그램도 확인 창 없이 파일을 열 수 있습니다.
- 지우려면 AI에게 "suup-jejak 보안 모듈 등록을 지워 줘"라고 하거나 `powershell -NoProfile -ExecutionPolicy Bypass -File <스킬 폴더>\scripts\suup.ps1 security --remove`를 실행합니다. 이 스킬이 등록한 것만 지웁니다.

## 시험 결과

| 환경 | 스킬 인식 | hwpx 만들기 | 구조 점검 | 한글로 PDF 확인 |
|---|---|---|---|---|
| Codex CLI 0.167 (Windows, Python 판) | 됨 | 됨 | 통과 | 안 됨: 샌드박스가 한글 자동화를 막음 |
| Antigravity CLI 1.4.9 (Windows, Python 판) | 됨 | 됨 | 통과 | 됨 |
| Claude Code (Windows, Python 판) | 됨 | 됨 | 통과 | 됨 |
| Windows 11 PowerShell 5.1 (Python·Node 없이) | - | 됨 | 통과 | 됨 (한컴오피스) |
| GitHub Actions: Linux·macOS·Windows (Python 판) | - | 됨 | 통과 (견본과 바이트 단위로 같음) | 해당 없음 |
| GitHub Actions: Windows PowerShell 5.1 (Python·Node 없이) | - | 됨 | 통과 (견본과 바이트 단위로 같음) | 해당 없음 |

- 위 세 줄은 2026-11-14에 Windows 11 PC에서 새 성취기준(9도02-02)으로 직접 시험한 결과입니다. 각 AI는 작업 폴더의 `.agents/skills`에 설치된 스킬을 스스로 찾아 읽었습니다. 이때는 PowerShell 판이 없어서 Python 판을 썼습니다.
- PowerShell 판은 2026-11-20에 PowerShell에서 직접 실행해 시험했습니다(견본 생성, 한글·공백이 든 경로, 한컴오피스로 PDF 저장, 보안 모듈 등록·삭제). AI 앱 안에서 PowerShell 판을 실행하는 시험은 아직 하지 않았습니다.

## 설치하기: AI에게 요청하기

AI 작업 창에 아래 문장을 붙여 넣으세요.

```text
https://github.com/yang102948549/lesson-hwpx-skill 에 있는 skills/suup-jejak 스킬을 설치해 줘. 폴더 안의 서식, 데이터, 스크립트, bin도 통째로 설치하고, 설치한 스킬의 SKILL.md 맨 위 안내대로 한글 보안 모듈 등록까지 해 줘.
```

AI가 폴더를 복사한 뒤 `scripts/suup.ps1 security --apply`를 실행해 한글 보안 모듈을 등록합니다(Windows만). Python이나 Node.js를 설치하지 않아도 됩니다.

설치가 끝나면 새 세션을 열고 "suup-jejak 스킬이 설치됐는지 확인해 줘"라고 요청하세요.

## 직접 설치하기: ZIP 다운로드

1. 이 저장소 GitHub 페이지에서 초록색 **Code → Download ZIP**을 누릅니다.
2. 내려받은 ZIP을 마우스 오른쪽 버튼으로 눌러 **압축 풀기**를 합니다.
3. 압축을 푼 폴더에서 `skills` 폴더를 열고 `suup-jejak` 폴더를 복사합니다.
4. 사용하는 환경에 맞는 폴더에 붙여 넣습니다. 폴더가 없으면 만듭니다.
   - Codex: `%USERPROFILE%\.agents\skills`
   - Antigravity: `%USERPROFILE%\.gemini\config\skills`
   - Claude Code: `%USERPROFILE%\.claude\skills`
   - 한 작업 폴더에서만 쓰려면 그 폴더 안의 `.agents\skills` (Codex, Antigravity 공통)
5. `suup-jejak` 폴더 안에 `SKILL.md`가 바로 보여야 합니다. **`SKILL.md`만 복사하지 말고 폴더를 통째로 복사하세요.** 서식, 데이터, 스크립트, `bin`이 함께 있어야 동작합니다.
6. (Windows) 한글 보안 모듈을 등록합니다. AI에게 "suup-jejak 스킬의 SKILL.md 맨 위 안내대로 보안 모듈을 등록해 줘"라고 요청하면 됩니다. 직접 하려면 붙여 넣은 `suup-jejak` 폴더에서 명령 창을 열고 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\suup.ps1 security --apply`를 실행합니다. "등록했습니다" 또는 "이미 등록됨"이 나오면 됩니다.
7. AI 앱을 다시 시작하거나 새 세션을 엽니다. Antigravity CLI에서는 `/skills reload`로 다시 불러올 수 있습니다.

## 사용하기

```text
9과15-01로 한 차시 지도안과 활동지 만들어 줘.
```

- 성취기준이 한 차시에 크면 AI가 몇 차시로 나눌지 정하고 어느 차시를 만들었는지 알려 줍니다.
- 결과는 작업 폴더에 차시별 폴더(`design.json`, `지도안.hwpx`, `활동지.hwpx`)로 저장됩니다.
- 고치고 싶으면 "활동 2를 모둠 토의로 바꿔 줘"처럼 요청하면 `design.json`을 고쳐 다시 만듭니다.
- **단원명, 수업 대상, 일시, 그림 자료는 직접 확인하세요.** 교과서마다 단원명이 다릅니다.

## 폴더 구성

```text
skills/suup-jejak/
├─ SKILL.md                 AI가 읽는 작업 순서와 규칙
├─ scripts/
│  ├─ suup.ps1              Windows용 도구 하나로 아래 일을 모두 함 (설치 필요 없음)
│  │                          standards · check · plan · sheet · validate · pdf · security
│  │  ─ macOS·Linux·클라우드 샌드박스용 (Python·Node) ─
│  ├─ standards.mjs         성취기준 찾기와 분석 자료
│  ├─ make_plan.py          design.json → 지도안.hwpx
│  ├─ make_sheet.py         design.json → 활동지.hwpx
│  ├─ check_design.py       지도안·활동지 연결과 시간 점검
│  ├─ validate_hwpx.py      hwpx 구조 점검
│  ├─ render_pdf.py         한글로 PDF 저장 (Windows + 한컴오피스 + pywin32)
│  ├─ setup_hwp_security.py 한글 보안 모듈 등록 (Python 판)
│  └─ hwpxkit.py            hwpx 조립 도구
├─ bin/FilePathCheckerModule.dll  한글 자동화 보안 모듈
├─ templates/지도안 서식.hwpx
├─ data/curriculum.json     성취기준 원문 + 학습지도 자료
└─ examples/                견본 두 차시
tools/build-data.mjs        data/curriculum.json 다시 만들기 (개발용)
sources/curriculum-data.js  성취기준 원문 (개발용)
```

학교 지도안 서식을 쓰려면 `templates/`의 서식을 바꾸고 `SKILL.md` 5장을 보세요. 도구가 두 벌이므로 칸 위치와 열 너비는 `suup.ps1`과 `make_plan.py`를 함께 고칩니다.

## 자료 출처와 비보증

성취기준 원문은 교육부·국가교육위원회 고시(저작권법 제7조 비보호 대상)이고, 세부 주제·평가 자료·학습 관계는 [DECK6/korean-secondary-learning-map](https://github.com/DECK6/korean-secondary-learning-map)(MIT)을 가공했습니다. 자세한 내용은 [NOTICE.md](NOTICE.md)를 보세요. 평가 자료는 검토 전 초안이므로 수업과 평가에 쓰기 전에 공식 문서와 대조해야 합니다. 이 스킬이 만든 지도안과 활동지도 교사가 검토한 뒤 사용하세요.
