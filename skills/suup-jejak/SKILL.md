---
name: suup-jejak
description: 2022 개정 교육과정 성취기준 코드(예 9과15-01)나 단원을 받아 한 차시 수업을 설계하고, 학교 지도안 서식에 맞춘 지도안과 학생 활동지를 한글(hwpx) 파일로 만든다. "지도안 만들어 줘", "활동지 만들어 줘", "수업 설계", "차시 만들어 줘", 성취기준 코드가 나오면 쓴다.
---

# 수업 제작: 지도안과 활동지 (hwpx)

> **이 스킬을 설치하는 중이라면** (Windows): 폴더를 다 복사한 뒤 설치의 마지막 단계로
> `powershell -NoProfile -ExecutionPolicy Bypass -File "<설치한 스킬 폴더>/scripts/suup.ps1" security --apply`를 실행하고, 출력 결과를 사용자에게 알린다.
> 한글 보안 모듈을 등록해 한글 자동화가 파일을 열 때 '접근 허용' 확인 창이 뜨지 않게 한다.
> 이 PC의 다른 한글 자동화 프로그램에도 적용되며 `--remove`로 지울 수 있다는 점도 함께 알린다.
> Windows가 아니면 건너뛴다.

성취기준에서 출발해 한 차시의 **지도안(hwpx)**과 **활동지(hwpx)**를 만든다.
두 문서는 `design.json` 한 파일에서 함께 나온다. 그래서 지도안의 '활동 1'과 활동지의 '활동 1'이 늘 같다.

```
성취기준 분석 → design.json 작성 → 점검 → 지도안.hwpx · 활동지.hwpx → 확인
```

## 1. 명령

`<SKILL>`은 이 SKILL.md가 있는 폴더다. 결과물은 사용자의 작업 폴더에 차시마다 폴더를 하나 만들어 둔다(스킬 폴더 안에 두지 않는다).
같은 일을 하는 도구가 두 벌 있다. 결과 파일은 같다. **실행 환경을 보고 하나를 고른다.**

**Windows (기본)**: Windows에 들어 있는 PowerShell만 쓴다. Python·Node.js가 없어도 된다. bash에서도 PowerShell에서도 그대로 실행한다.

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL>/scripts/suup.ps1" standards context 9과15-01   # 성취기준 원문, 평가 증거, 오개념, 선후 학습
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL>/scripts/suup.ps1" check    "<차시폴더>/design.json"  # 지도안·활동지 연결과 시간 점검
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL>/scripts/suup.ps1" plan     "<차시폴더>/design.json"  # → <차시폴더>/지도안.hwpx
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL>/scripts/suup.ps1" sheet    "<차시폴더>/design.json"  # → <차시폴더>/활동지.hwpx
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL>/scripts/suup.ps1" validate "<차시폴더>/지도안.hwpx" "<차시폴더>/활동지.hwpx"  # 파일 구조 점검
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL>/scripts/suup.ps1" pdf      "<차시폴더>/지도안.hwpx" "<차시폴더>/활동지.hwpx"  # 한글로 열어 PDF 저장 (한컴오피스 필요)
```

**macOS·Linux·클라우드 샌드박스** (PowerShell이 없고 Python·Node가 있는 곳):

```
node   <SKILL>/scripts/standards.mjs context 9과15-01
python <SKILL>/scripts/check_design.py  <차시폴더>/design.json
python <SKILL>/scripts/make_plan.py     <차시폴더>/design.json
python <SKILL>/scripts/make_sheet.py    <차시폴더>/design.json
python <SKILL>/scripts/validate_hwpx.py <차시폴더>/*.hwpx
```

- `standards`는 `browse`, `search`, `get`, `context`를 받는다(`--school 중 --grades 1 --subject 과학 --limit 20`, `--json`). 두 벌 모두 같다.
- `plan`, `sheet`는 `-o <파일>`로 저장 위치를 바꿀 수 있다.
- Windows에서 Python 쪽을 쓸 때 한글 출력이 깨지면 명령 앞에 환경 변수 `PYTHONIOENCODING=utf8`을 둔다.
- PDF 확인(`pdf`)을 할 수 없으면(Windows가 아님, 한컴오피스 없음, 보안 모듈 미등록, 샌드박스가 한글 자동화를 막음 → "PDF 확인 건너뜀", 종료 코드 2) `validate`로 점검하고, 사용자에게 한글에서 열어 확인해 달라고 말한다. 한 번 건너뜀이 나오면 다시 시도하지 않는다.
- **한글 보안 모듈**: 스킬을 설치할 때 `suup.ps1 security --apply`로 등록한다(맨 위 안내). 등록돼 있지 않으면 한글이 파일을 열 때마다 '접근 허용' 확인 창을 띄우므로 `pdf`는 건너뛴다. 수업을 만드는 도중에는 스스로 등록하지 말고, 설치 단계가 빠졌다고 사용자에게 알린 뒤 원하면 실행한다. 상태는 `suup.ps1 security`로 본다.
- 견본: `<SKILL>/examples/도덕-가치관/`, `<SKILL>/examples/과학-9과15-01-1차시/`. design.json을 쓰기 전에 하나를 읽고 형식을 따른다.

## 2. 만드는 순서

### ⓪ 교과서 파일을 받았으면
사용자가 교과서·지도서 파일(PDF, HWP 등)을 함께 주면 먼저 **gyogwaseo-ilgi** 스킬로 필요한 쪽만 `교과서.md`로 바꿔 읽는다. 파일을 바로 열어 읽지 않는다(표가 깨지고 순서가 뒤섞인다). 단원명, 용어, 활동 순서는 교과서를 따르고, 쓴 쪽수는 `plan_note`에 적는다.

### ① 성취기준 분석
`standards.mjs context <코드>`로 아래를 뽑는다.

| 뽑을 것 | 어디에 쓰나 |
|---|---|
| 성취기준 원문의 **행동 동사**(설명한다, 판단한다, 제안한다…) | 학습 목표 |
| **평가 증거** | 활동지 문항, 스스로 점검 항목 |
| **평가 질문** | 활동지의 핵심 문항 (다듬어서) |
| **흔한 오개념** | 지도안 '자료 및 유의점', 개념 정리 문항 |
| **선수 학습** | 동기 유발, 도입의 확인 질문 |

- 중학교 자료는 검토 전 초안이다. 고등학교 세부 주제는 기계 생성이라 쓰지 말고 원문을 직접 분석한다. 초등학교는 원문만 있다.
- 성취기준 하나가 한 차시에 너무 크면(내용 요소가 둘 이상) 몇 차시로 나눌지 정하고, 어느 차시를 만드는지 사용자에게 밝힌다. 나눈 내용은 `plan_note`에 적는다.
- 단원명은 교과서마다 다르다. 사용자가 알려 주지 않으면 영역 이름으로 임시로 채우고, 바꿔야 한다고 알린다.

### ② 학습 목표
- 1~3개, **"~할 수 있다."** 꼴로 쓴다. 관찰할 수 있는 동사를 쓴다(안다, 이해한다 대신 설명한다, 구분한다, 쓴다).
- 목표 하나마다 활동지에 그것을 확인하는 문항이 하나 이상 있어야 한다.

### ③ 수업 흐름
- 도입, 전개, 정리 세 단계. 시간 합계는 초 40분, 중 45분, 고 50분이다(`meta.school`로 판단, `meta.minutes`로 바꿀 수 있음).
- 도입: 분위기 조성 → 동기 유발 → 학습 목표.
- 전개: 개념 이해와 활동을 2~4개 줄로 나눈다. 줄 하나가 지도안의 한 칸이다.
- 정리: 핵심 정리, 스스로 점검, 차시 예고.
- 예상 답은 지도안 '자료 및 유의점'에 `예상 답: …`으로 적는다.

### ④ 활동지
- 전개의 활동마다 활동지 구역을 하나 둔다. 지도안의 줄에 `"sheet": "구역 이름"`을 적어 잇는다.
- 문항은 학생에게 하는 말로 쓴다: "~쓰세요.", "~고르세요."
- 마지막에 학습 목표를 학생 말로 바꾼 '스스로 점검'을 둔다.

### ⑤ 점검과 확인
1. `check_design.py`가 "문제 없음"을 낼 때까지 고친다.
2. 두 파일을 만들고 `validate`가 통과하는지 본다.
3. 가능하면 `pdf`로 PDF를 만들어 읽어 본다. 확인할 것: 지도안이 1~2쪽인지, 문항과 답 칸이 같은 쪽에 있는지, 칸이 비거나 넘치지 않는지.
4. 사용자에게 결과 파일 경로, 차시를 나눈 방식, 직접 확인할 것(단원명, 대상, 일시, 그림 자료)을 알린다.

## 3. design.json 형식

```jsonc
{
  "meta": {
    "school": "중",              // 초 | 중 | 고 (차시 시간 점검용)
    "subject": "도덕",
    "teacher": "", "target": "1-1, 1-2", "date": "",
    "unit": "Ⅰ. 자신과의 관계",   // 대단원
    "subunit": "1-01. 나를 찾아서", // 소단원
    "form": "모둠 활동", "period": "2차시", "place": "1-1 교실"
  },
  "standards": ["9도01-01"],
  "plan_note": "차시를 나눈 방식 (선택)",
  "objectives": ["…설명할 수 있다.", "…판단할 수 있다."],
  "intent": "수업 의도 한두 문장",
  "stages": [ /* 지도안 */ ],
  "worksheet": { /* 활동지 */ }
}
```

### stages (지도안 과정표)

```jsonc
{ "name": "전개", "minutes": 33, "steps": [
  {
    "label": "활동 1",                 // 둘째 칸. 줄바꿈은 \n
    "activity": [
      "▶가치관 무인도 생존 게임",       // ▶로 시작하면 소제목
      "가치 카드 16개 중 3개를 고른다."  // 나머지는 '-' 머리 기호
    ],
    "sheet": "활동 1",                 // 활동지 구역 이름 → '자료 및 유의점'에 '활동지: 활동 1'이 자동으로 들어감
    "notes": ["자료: 가치 카드, PPT", "유의점 한 줄"],
    "objectives": true                 // 이 줄에 학습 목표를 번호 붙여 넣음 (도입의 '학습 목표' 줄에 씀)
  }
]}
```

### worksheet (활동지)

```jsonc
{ "title": "나에게 소중한 가치는?",
  "sections": [
    { "label": "활동 1",               // 회색 칸. 지도안의 sheet와 같은 이름
      "title": "가치관 무인도 생존 게임",
      "guide": "회색 작은 글씨 안내 (없어도 됨)",
      "items": [ /* 아래 문항들 */ ] }
  ] }
```

| type | 모양 | 값 |
|---|---|---|
| `text` | 본문 한 문단. 빈칸은 `(          )`로 | `text` |
| `question` | 번호 붙은 질문(번호는 활동지 전체에서 이어짐) + 점선 쓰기 칸 | `text`, `lines`(기본 3), `hint` |
| `table` | 회색 머리줄 표 | `headers`, `rows`(빈 줄 수 또는 칸 내용 배열), `widths`(비율), `row_lines`(줄 높이) |
| `check` | 스스로 점검표 (잘함/보통/노력 필요) | `rows`(점검 문장), `headers`(바꿀 때만) |
| `box` | 빈 네모 (그림, 마인드맵) | `text`(위 안내), `lines`(높이) |

## 4. 글쓰기 규칙

**지도안**
- 교사가 주어인 서술형 "~한다."로 쓴다. "~시킨다"보다 "~하게 한다"를 쓴다.
- 발문은 `발문: …?`으로 쓴다. 예상 답은 `예상 답: …`으로 쓴다.
- '자료 및 유의점'에는 자료(`자료: …`)와 지도상의 유의점을 쓴다. 오개념을 막는 말을 여기에 둔다.
- 활동 칸에는 학생이 실제로 하는 일을 순서대로 쓴다. "~에 대해 알아본다"처럼 흐린 말을 피한다.

**활동지**
- 학생에게 직접 말한다. 한 문항에는 한 가지만 묻는다.
- `question`에는 번호가 저절로 붙는다. `text`에는 손으로 번호를 달지 않는다(번호가 겹친다).
- 답 칸의 줄 수는 기대하는 답의 길이에 맞춘다(한 문장이면 1~2줄, 까닭까지 쓰면 3~4줄).
- 평가 증거를 그대로 옮기지 않고 학생이 할 행동으로 바꾼다.
  예: "자신의 판단을 밝히고 그 근거가 되는 가치를 함께 든다" → "어떻게 할지 정하고, 그렇게 정한 까닭을 두 가지 쓰세요."

## 5. 서식 정보 (고칠 때 참고)

- 지도안은 `templates/지도안 서식.hwpx`의 머리표를 그대로 쓰고, 과정표는 같은 열 너비와 테두리 번호로 새로 짠다. 서식 뒤쪽의 예시는 결과물에서 뺀다.
- 활동지는 지도안 서식의 글꼴(함초롬바탕·돋움, HY헤드라인M)을 물려받고, 회색 칸과 점선 쓰기 줄 같은 모양을 덧붙인다.
- 학교 서식으로 바꾸려면 `templates/`에 hwpx를 두고, 칸 위치(`make_plan.py`의 `header_table`의 `fill`, `suup.ps1`의 `Header-Table`)와 열 너비(`COLS`)를 두 벌 모두 맞춘다.
- hwpx를 직접 고칠 때 XML은 문자열로 다룬다. ElementTree로 다시 쓰면 네임스페이스 접두사가 바뀌어 한글이 못 연다. 다른 hwpx 도구나 라이브러리를 설치하지 말고 이 스크립트를 쓴다.
