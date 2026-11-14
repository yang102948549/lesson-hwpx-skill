#!/usr/bin/env python
"""design.json 점검: 지도안과 활동지가 서로 맞는지 봅니다.

    python scripts/check_design.py <design.json>
"""
import json
import sys
from pathlib import Path

PERIOD = {'초': 40, '중': 45, '고': 50}


def check(d):
    out = []
    m = d.get('meta', {})
    for k in ('subject', 'unit', 'period'):
        if not m.get(k):
            out.append(f'meta.{k}이(가) 비어 있습니다.')
    objs = d.get('objectives', [])
    if not 1 <= len(objs) <= 3:
        out.append(f'학습 목표는 1~3개가 알맞습니다. 지금 {len(objs)}개입니다.')
    for o in objs:
        if not o.rstrip().endswith(('있다.', '있다')):
            out.append(f'학습 목표를 "~할 수 있다." 꼴로 쓰면 평가와 잇기 쉽습니다: {o}')

    stages = d.get('stages', [])
    total = sum(s.get('minutes', 0) for s in stages)
    want = m.get('minutes') or PERIOD.get(str(m.get('school', ''))[:1])
    if want and total != want:
        out.append(f'단계 시간 합계가 {total}분입니다. 한 차시는 {want}분입니다.')

    # 지도안 ↔ 활동지 연결
    sheet = d.get('worksheet')
    labels = [s['label'] for s in sheet.get('sections', [])] if sheet else []
    if len(set(labels)) != len(labels):
        out.append('활동지 구역 이름(label)이 겹칩니다.')
    used = []
    for st in stages:
        for step in st.get('steps', []):
            ref = step.get('sheet')
            if not ref:
                continue
            used.append(ref)
            if ref not in labels:
                out.append(f'지도안 "{step.get("label")}"이(가) 활동지의 "{ref}"를 가리키는데 활동지에 없습니다.')
    for lb in labels:
        if lb not in used:
            out.append(f'활동지 "{lb}"를 쓰는 지도안 단계가 없습니다. 해당 단계에 "sheet": "{lb}"를 넣으세요.')
    return out


if __name__ == '__main__':
    d = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    probs = check(d)
    for p in probs:
        print('확인:', p)
    if not probs:
        print('문제 없음')
    sys.exit(1 if probs else 0)
