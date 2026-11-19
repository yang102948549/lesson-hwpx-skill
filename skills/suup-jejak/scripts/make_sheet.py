#!/usr/bin/env python
"""활동지 만들기: design.json → 활동지.hwpx

    python scripts/make_sheet.py <design.json> [-o 활동지.hwpx]

글꼴과 기본 모양은 지도안 서식과 같은 것을 씁니다. design.json의 worksheet 형식은 GUIDE.md를 봅니다.
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hwpxkit import CHAR, PARA, Package, cell, esc, para, plain_text, table  # noqa: E402
from check_design import check  # noqa: E402

W = 49594            # 표 너비 (지도안 표와 같음)
ROW = 1300           # 글 한 줄짜리 칸 높이
WRITE = 2100         # 학생이 손으로 쓰는 줄 하나 높이 (약 7.4mm)
LABEL_W = 7000       # 회색 이름 칸 너비


class Styles:
    """활동지에만 필요한 모양을 서식 header.xml에 덧붙입니다."""

    def __init__(self, pkg):
        self.title = CHAR['title']                         # HY헤드라인M 18pt
        self.h = pkg.add_char('6', bold=True)              # 돋움 11pt 굵게 (구역 제목)
        self.label = pkg.add_char('1', bold=True)          # 돋움 10pt 굵게 (회색 칸)
        self.body = CHAR['body']                           # 바탕 10pt
        self.small = pkg.add_char('2', color='#555555')    # 돋움 9pt 회색 (안내)
        self.gray = pkg.add_border(fill='#E5E5E5')
        self.box = '3'
        self.none = pkg.add_border(sides='')
        self.under = pkg.add_border(sides='B', width='0.4 mm')
        # 쓰기 줄: 바깥은 실선, 안쪽 가로줄은 점선
        self.line_first = pkg.add_border(sides='LRT', kinds={'B': 'DOT'})
        self.line_mid = pkg.add_border(sides='LR', kinds={'T': 'DOT', 'B': 'DOT'})
        self.line_last = pkg.add_border(sides='LRB', kinds={'T': 'DOT'})
        self.p_body = PARA['body']
        self.p_center = PARA['center']
        self.p_item = pkg.add_para('1', prev=500)          # 문항 앞 띄움
        # 문항·구역 제목·안내는 다음 것(답 칸, 표)과 같은 쪽에 둡니다
        self.p_q = pkg.add_para('1', prev=500, keep_next=True)
        self.p_guide = pkg.add_para('1', prev=300, keep_next=True)
        self.p_section = pkg.add_para('0', prev=1400, keep_next=True)
        self.p_gap = pkg.add_para('0', prev=300)


def widths(ratios, total=W):
    s = sum(ratios)
    ws = [int(total * r // s) for r in ratios]   # 비율이 실수여도 너비는 정수로
    ws[-1] += total - sum(ws)
    return ws


def write_box(st, lines):
    """학생이 쓰는 칸: 줄 수만큼 점선 가로줄."""
    rows, hs = [], []
    for i in range(lines):
        if lines == 1:
            b = st.box
        elif i == 0:
            b = st.line_first
        elif i == lines - 1:
            b = st.line_last
        else:
            b = st.line_mid
        rows.append([cell(0, i, W, WRITE, para('', st.p_body, st.body), b)])
        hs.append(WRITE)
    return table(rows, [W], hs, page_break='NONE', repeat_header=False, para_pr=st.p_gap)


def grid(st, item):
    ws = widths(item.get('widths') or [1] * len(item['headers']))
    h = item.get('row_lines', 1) * WRITE if item.get('row_lines', 1) > 1 else WRITE
    rows = [[cell(c, 0, w, ROW, para(t, st.p_center, st.label), st.gray)
             for c, (t, w) in enumerate(zip(item['headers'], ws))]]
    hs = [ROW]
    body = item['rows']
    if isinstance(body, int):
        body = [[''] * len(ws) for _ in range(body)]
    for r, vals in enumerate(body, 1):
        # 첫 칸과 짧은 값(수치, 기호)은 가운데, 긴 글은 왼쪽 정렬
        rows.append([cell(c, r, w, h, para(v, st.p_center if c == 0 or len(v) <= 8 else st.p_body, st.body), st.box)
                     for c, (v, w) in enumerate(zip(vals, ws))])
        hs.append(h)
    return table(rows, ws, hs, page_break='CELL', repeat_header=True, para_pr=st.p_gap)


def checklist(st, item):
    heads = item.get('headers', ['점검 내용', '잘함', '보통', '노력 필요'])
    ws = widths([8] + [1.4] * (len(heads) - 1))
    ws = [int(w) for w in ws]
    ws[-1] += W - sum(ws)
    rows = [[cell(c, 0, w, ROW, para(t, st.p_center, st.label), st.gray) for c, (t, w) in enumerate(zip(heads, ws))]]
    hs = [ROW]
    for r, text in enumerate(item['rows'], 1):
        row = [cell(0, r, ws[0], ROW + 200, para(text, st.p_body, st.body), st.box)]
        row += [cell(c, r, w, ROW + 200, para('', st.p_center, st.body), st.box) for c, w in enumerate(ws[1:], 1)]
        rows.append(row)
        hs.append(ROW + 200)
    return table(rows, ws, hs, page_break='CELL', repeat_header=True, para_pr=st.p_gap)


def item_paras(st, item, qnum):
    t = item['type']
    if t == 'text':
        return [para(item['text'], st.p_item, st.body)]
    if t == 'question':
        qnum[0] += 1
        out = [para('', st.p_q, runs=[(st.label, f'{qnum[0]}. '), (st.body, item['text'])])]
        if item.get('hint'):
            out.append(para(item['hint'], st.p_guide, st.small))
        return out + [write_box(st, item.get('lines', 3))]
    if t == 'box':
        out = [para(item['text'], st.p_q, st.body)] if item.get('text') else []
        h = item.get('lines', 5) * WRITE
        return out + [table([[cell(0, 0, W, h, para('', st.p_body, st.body), st.box, valign='TOP')]],
                            [W], [h], page_break='NONE', repeat_header=False, para_pr=st.p_gap)]
    if t == 'table':
        return [grid(st, item)]
    if t == 'check':
        return [checklist(st, item)]
    raise ValueError(f'모르는 문항 종류: {t}')


def head_table(st, d):
    m = d['meta']
    unit = '  '.join(x for x in (m.get('unit', ''), m.get('subunit', '')) if x)
    ws = [LABEL_W, 24594, 4000, 5000, 4000, 5000]
    r0 = [
        cell(0, 0, ws[0], ROW, para('단원', st.p_center, st.label), st.gray),
        cell(1, 0, ws[1], ROW, para(unit, st.p_body, st.body), st.box),
        cell(2, 0, ws[2], ROW, para('학번', st.p_center, st.label), st.gray),
        cell(3, 0, ws[3], ROW, para('', st.p_center, st.body), st.box),
        cell(4, 0, ws[4], ROW, para('이름', st.p_center, st.label), st.gray),
        cell(5, 0, ws[5], ROW, para('', st.p_center, st.body), st.box),
    ]
    objs = [para(f'{n}. {o}', st.p_body, st.body) for n, o in enumerate(d['objectives'], 1)]
    oh = max(ROW, len(objs) * 1600 + 282)
    r1 = [
        cell(0, 1, ws[0], oh, para('학습 목표', st.p_center, st.label), st.gray),
        cell(1, 1, W - ws[0], oh, objs, st.box, colspan=5),
    ]
    return table([r0, r1], ws, [ROW, oh], page_break='NONE', repeat_header=False, para_pr=st.p_gap)


def section_head(st, sec):
    title = sec.get('title', '')
    return table([[
        cell(0, 0, LABEL_W, ROW + 200, para(sec['label'], st.p_center, st.label), st.gray),
        cell(1, 0, W - LABEL_W, ROW + 200, para(title, st.p_body, st.h), st.under, margin=(850, 510, 141, 141)),
    ]], [LABEL_W, W - LABEL_W], [ROW + 200], page_break='NONE', repeat_header=False, para_pr=st.p_section)


def build(design_path, out=None):
    design_path = Path(design_path)
    d = json.loads(design_path.read_text(encoding='utf-8'))
    for p in check(d):
        print('확인:', p)
    ws = d['worksheet']
    pkg = Package()
    st = Styles(pkg)
    title_runs = f'<hp:run charPrIDRef="{st.title}"><hp:t>{esc(ws["title"])}</hp:t></hp:run>'
    paras = [pkg.first_para(title_runs), head_table(st, d)]
    qnum = [0]
    for sec in ws['sections']:
        paras.append(section_head(st, sec))
        if sec.get('guide'):
            paras.append(para(sec['guide'], st.p_guide, st.small))
        for item in sec.get('items', []):
            paras += item_paras(st, item, qnum)
    pkg.set_body(paras)
    out = Path(out) if out else design_path.parent / '활동지.hwpx'
    pkg.save(out, plain_text(pkg.section))
    print('저장:', out)
    return out


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('design')
    ap.add_argument('-o', '--out')
    a = ap.parse_args()
    build(a.design, a.out)
