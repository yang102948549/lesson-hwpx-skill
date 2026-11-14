#!/usr/bin/env python
"""지도안 만들기: design.json → 지도안.hwpx (templates/지도안 서식.hwpx 기준)

    python scripts/make_plan.py <design.json> [-o 지도안.hwpx]

design.json의 plan 부분 형식은 GUIDE.md를 봅니다.
"""
import argparse
import json
import math
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hwpxkit import CHAR, PARA, Package, cell, para, plain_text, table  # noqa: E402
from check_design import check  # noqa: E402

# 과정표 열 너비 (서식과 같음): 단계 | 활동명 | 교수·학습 활동 | 자료 및 유의점
COLS = [3558, 5256, 27330, 13463]
LINE = 1440          # 9pt, 줄간격 160%
PAD = 282            # 위아래 셀 여백

# 단계 안에서의 위치(첫 줄/마지막 줄)에 따라 굵은 선이 달라지는 서식의 테두리 번호
# (위 굵게, 아래 굵게) → (가운데 두 칸, 오른쪽 칸)
BORDERS = {
    (True, False): ('21', '22'),
    (False, False): ('15', '23'),
    (False, True): ('24', '25'),
    (True, True): ('26', '27'),
}
STAGE_BORDER = '18'   # 회색 배경, 굵은 선


def lines_of(texts, width, char_w=800):
    per = max(1, (width - 1020) // char_w)
    return sum(max(1, math.ceil(len(t) / per)) for t in texts) or 1


def header_table(pkg, d):
    """서식의 머리표(4행 8열)를 그대로 가져와 칸만 채웁니다."""
    s = pkg.files['Contents/section0.xml'].decode('utf-8')
    i = s.index('<hp:tbl ')
    a = s.rfind('<hp:p ', 0, i)
    b = s.index('</hp:p>', s.index('</hp:tbl>', i)) + len('</hp:p>')
    p = s[a:b]
    # 표를 담은 바깥 문단의 줄 배치 정보만 지웁니다 (표 뒤에 있는 마지막 것)
    tail = p.rfind('<hp:linesegarray>')
    if tail > p.rfind('</hp:tbl>'):
        p = p[:tail] + p[p.index('</hp:linesegarray>', tail) + len('</hp:linesegarray>'):]

    m = d['meta']
    c8 = CHAR['head']
    center = lambda t: para(t, PARA['center'], c8)  # noqa: E731
    fill = {
        (1, 0): [center(m.get('subject', ''))],
        (3, 0): [center(m.get('teacher', ''))],
        (5, 0): [center(m.get('target', ''))],
        (7, 0): [center(m.get('date', ''))],
        (1, 1): [center(m.get('unit', '')), center(m.get('subunit', ''))],
        (3, 1): [center(m.get('form', ''))],
        (5, 1): [center(m.get('period', ''))],
        (7, 1): [center(m.get('place', ''))],
        (1, 2): [para(f'{n}. {o}', PARA['body'], c8) for n, o in enumerate(d['objectives'], 1)],
        (1, 3): [para(d.get('intent', ''), PARA['body'], c8)],
    }

    def repl(tc):
        x = tc.group(0)
        addr = re.search(r'colAddr="(\d+)" rowAddr="(\d+)"', x)
        key = (int(addr.group(1)), int(addr.group(2)))
        if key not in fill:
            return x
        return re.sub(r'(<hp:subList[^>]*>).*?(</hp:subList>)',
                      lambda mm: mm.group(1) + ''.join(fill[key]) + mm.group(2), x, flags=re.S)

    return re.sub(r'<hp:tc .*?</hp:tc>', repl, p, flags=re.S)


def step_cells(step, d):
    """한 단계 안의 한 줄: 활동명, 교수·학습 활동, 자료 및 유의점 문단들."""
    act = []
    raw = []
    for t in step.get('activity', []):
        if t.startswith('▶'):
            act.append(para(t, PARA['body'], CHAR['cell']))
        else:
            act.append(para(t, PARA['dash'], CHAR['cell']))
        raw.append(t)
    if step.get('objectives'):
        for n, o in enumerate(d['objectives'], 1):
            act.append(para(f'{n}. {o}', PARA['body'], CHAR['cell']))
            raw.append(f'{n}. {o}')
    notes = list(step.get('notes', []))
    if step.get('sheet'):
        notes.insert(0, f"활동지: {step['sheet']}")
    note_ps = [para(t, PARA['dot'], CHAR['note']) for t in notes] or [para('', PARA['center'], CHAR['cell'])]
    label = step.get('label', '')
    label_ps = [para(t, PARA['center'], CHAR['cell']) for t in label.split('\n')]
    h = max(lines_of(raw, COLS[2]), lines_of(notes, COLS[3]), lines_of(label.split('\n'), COLS[1])) * LINE + PAD
    return label_ps, act or [para('', PARA['body'], CHAR['cell'])], note_ps, max(h, 1182)


def process_table(d):
    rows, heights = [], []
    head_h = 1182
    rows.append([
        cell(0, 0, COLS[0] + COLS[1], head_h, para('수업 단계', PARA['center']), STAGE_BORDER, colspan=2),
        cell(2, 0, COLS[2], head_h, para('교수·학습 활동', PARA['center']), STAGE_BORDER),
        cell(3, 0, COLS[3], head_h, para('자료 및 유의점', PARA['center']), STAGE_BORDER),
    ])
    heights.append(head_h)
    r = 1
    for stage in d['stages']:
        steps = stage['steps']
        built = [step_cells(s, d) for s in steps]
        stage_h = sum(b[3] for b in built)
        for i, (label_ps, act, notes, h) in enumerate(built):
            mid, right = BORDERS[(i == 0, i == len(steps) - 1)]
            row = []
            if i == 0:
                stage_ps = [para(stage['name'], PARA['center']), para(f"({stage['minutes']}분)", PARA['center'])]
                row.append(cell(0, r, COLS[0], stage_h, stage_ps, STAGE_BORDER, rowspan=len(steps)))
            row += [
                cell(1, r, COLS[1], h, label_ps, mid),
                cell(2, r, COLS[2], h, act, mid),
                cell(3, r, COLS[3], h, notes, right),
            ]
            rows.append(row)
            heights.append(h)
            r += 1
    return table(rows, COLS, heights, page_break='CELL', repeat_header=True, border='15', inline=False)


def build(design_path, out=None):
    design_path = Path(design_path)
    d = json.loads(design_path.read_text(encoding='utf-8'))
    problems = check(d)
    for p in problems:
        print('확인:', p)
    pkg = Package()
    title = d['meta'].get('doc_title', '수업 지도안')
    paras = [
        pkg.first_para(f'<hp:run charPrIDRef="{CHAR["title"]}"><hp:t>{title}</hp:t></hp:run>'),
        header_table(pkg, d),
        para('', PARA['body'], CHAR['body']),
        process_table(d),
    ]
    pkg.set_body(paras)
    out = Path(out) if out else design_path.parent / '지도안.hwpx'
    pkg.save(out, plain_text(pkg.section))
    print('저장:', out)
    return out


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('design')
    ap.add_argument('-o', '--out')
    a = ap.parse_args()
    build(a.design, a.out)
