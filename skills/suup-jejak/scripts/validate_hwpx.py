#!/usr/bin/env python
"""hwpx 파일 구조 점검 (한컴오피스 없이, 모든 운영체제에서)

    python validate_hwpx.py <파일.hwpx> [<파일.hwpx> ...]

한글이 파일을 못 여는 흔한 원인을 찾습니다.
- ZIP 첫 항목이 압축하지 않은 mimetype인지
- 모든 XML이 올바른지
- 본문이 쓰는 글자·문단·테두리 모양 번호가 header.xml에 있는지, itemCnt가 맞는지
- 표의 행 수, 셀 위치와 병합이 격자를 빈틈없이 덮는지
통과해도 보기 좋은지는 알 수 없으므로, 가능하면 한글에서 열어 확인합니다.
"""
import re
import sys
import zipfile
from xml.etree import ElementTree as ET
for _s in (sys.stdout, sys.stderr):  # 콘솔 인코딩에 없는 글자 때문에 멈추지 않도록
    if hasattr(_s, 'reconfigure'):
        _s.reconfigure(errors='replace')


def ln(tag):
    return tag.rsplit('}', 1)[-1]


def check(path):
    errs = []
    try:
        zf = zipfile.ZipFile(path)
    except Exception as e:  # noqa: BLE001
        return [f'ZIP을 열 수 없음: {e}']
    infos = zf.infolist()
    if not infos or infos[0].filename != 'mimetype':
        errs.append('첫 항목이 mimetype이 아님')
    elif infos[0].compress_type != zipfile.ZIP_STORED:
        errs.append('mimetype이 압축되어 있음 (무압축이어야 함)')
    elif zf.read('mimetype') != b'application/hwp+zip':
        errs.append('mimetype 내용이 application/hwp+zip이 아님')

    names = zf.namelist()
    missing_files = [n for n in ('Contents/header.xml', 'Contents/content.hpf', 'META-INF/container.xml')
                     if n not in names]
    if missing_files:
        return errs + [f'{n} 없음' for n in missing_files]

    trees = {}
    parse_errs = []
    for n in names:
        if n.endswith(('.xml', '.hpf', '.rdf')):
            try:
                trees[n] = ET.fromstring(zf.read(n))
            except ET.ParseError as e:
                parse_errs.append(f'{n}: XML 오류 {e}')
    if parse_errs:
        return errs + parse_errs

    # manifest에 적힌 파일이 있는지
    for el in trees['Contents/content.hpf'].iter():
        if ln(el.tag) == 'item' and el.get('href') and el.get('href') not in names:
            errs.append(f'content.hpf가 가리키는 {el.get("href")} 없음')

    # 모양 번호
    header = trees['Contents/header.xml']
    groups = {'charProperties': 'charPr', 'paraProperties': 'paraPr', 'borderFills': 'borderFill'}
    ids = {}
    for el in header.iter():
        g = ln(el.tag)
        if g in groups:
            kids = [c for c in el if ln(c.tag) == groups[g]]
            ids[groups[g]] = {c.get('id') for c in kids}
            if el.get('itemCnt') and int(el.get('itemCnt')) != len(kids):
                errs.append(f'header.xml {g} itemCnt={el.get("itemCnt")}인데 실제 {len(kids)}개')
    refs = {'charPrIDRef': 'charPr', 'paraPrIDRef': 'paraPr', 'borderFillIDRef': 'borderFill'}
    sections = sorted(n for n in names if re.match(r'Contents/section\d+\.xml$', n))
    if not sections:
        errs.append('본문 section 없음')
    for sn in sections:
        missing = set()
        for el in trees[sn].iter():
            for attr, kind in refs.items():
                v = el.get(attr)
                if v is not None and v not in ids.get(kind, set()):
                    missing.add(f'{attr}={v}')
        if missing:
            errs.append(f'{sn}: header에 없는 모양 번호 {sorted(missing)}')
        # 표
        for t_i, tbl in enumerate(e for e in trees[sn].iter() if ln(e.tag) == 'tbl'):
            rows = [c for c in tbl if ln(c.tag) == 'tr']
            rc, cc = int(tbl.get('rowCnt')), int(tbl.get('colCnt'))
            if len(rows) != rc:
                errs.append(f'{sn} 표{t_i + 1}: rowCnt={rc}인데 tr {len(rows)}개')
                continue
            grid = [[0] * cc for _ in range(rc)]
            for tr in rows:
                for tc in (c for c in tr if ln(c.tag) == 'tc'):
                    a = next(c for c in tc if ln(c.tag) == 'cellAddr')
                    s = next(c for c in tc if ln(c.tag) == 'cellSpan')
                    c0, r0 = int(a.get('colAddr')), int(a.get('rowAddr'))
                    cs, rs = int(s.get('colSpan')), int(s.get('rowSpan'))
                    for r in range(r0, r0 + rs):
                        for c in range(c0, c0 + cs):
                            if r >= rc or c >= cc:
                                errs.append(f'{sn} 표{t_i + 1}: 셀({c0},{r0})이 표 밖으로 나감')
                            else:
                                grid[r][c] += 1
            bad = [(c, r) for r in range(rc) for c in range(cc) if grid[r][c] != 1]
            if bad:
                errs.append(f'{sn} 표{t_i + 1}: 비거나 겹친 칸 {bad[:5]}')
    return errs


if __name__ == '__main__':
    failed = 0
    for p in sys.argv[1:]:
        e = check(p)
        if e:
            failed += 1
            print(f'실패: {p}')
            for x in e:
                print('  -', x)
        else:
            print(f'통과: {p}')
    sys.exit(1 if failed else 0)
