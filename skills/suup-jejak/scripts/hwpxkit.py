"""HWPX 조립 도구 (표준 라이브러리만 사용)

지도안 서식(templates/지도안 서식.hwpx)의 header.xml(글꼴, 글자 모양, 문단 모양, 테두리)을
그대로 물려받고, 본문(section0.xml)은 문자열로 조립합니다.
ElementTree로 다시 쓰면 네임스페이스 접두사가 바뀌어 한글이 못 여는 경우가 있어서
XML은 문자열로만 다룹니다.
"""
import re
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / 'templates' / '지도안 서식.hwpx'

# 서식 header.xml 안의 문단 모양(paraPr) 번호
PARA = {
    'body': '1',        # 양쪽 정렬, 줄간격 160%, 머리 기호 없음
    'center': '21',     # 가운데 정렬
    'dash': '33',       # '-' 머리 기호, 왼쪽 여백 조금
    'dot': '34',        # '•' 머리 기호 (자료 및 유의점)
}
# 글자 모양(charPr) 번호
CHAR = {
    'cell': '3',        # 함초롬바탕 9pt (지도안 과정표)
    'note': '11',       # 함초롬바탕 9pt (자료 및 유의점)
    'head': '8',        # 함초롬바탕 10pt (지도안 머리표)
    'body': '0',        # 함초롬바탕 10pt
    'sans': '1',        # 함초롬돋움 10pt
    'title': '16',      # HY헤드라인M 18pt 굵게
}


def esc(text):
    return escape(str(text), {'"': '&quot;'})


def para(text='', para_pr=PARA['body'], char_pr=CHAR['cell'], runs=None):
    """문단 하나. runs=[(글자모양, 글)]을 주면 한 문단 안에서 모양을 바꿉니다.
    linesegarray는 넣지 않습니다. 한글이 열 때 줄 배치를 다시 계산합니다."""
    if runs is None:
        runs = [(char_pr, text)]
    body = ''
    for cp, t in runs:
        body += f'<hp:run charPrIDRef="{cp}"><hp:t>{esc(t)}</hp:t></hp:run>' if t != '' \
            else f'<hp:run charPrIDRef="{cp}"/>'
    return (f'<hp:p id="0" paraPrIDRef="{para_pr}" styleIDRef="0" pageBreak="0" '
            f'columnBreak="0" merged="0">{body}</hp:p>')


def cell(col, row, width, height, paras, border, colspan=1, rowspan=1,
         valign='CENTER', margin=(510, 510, 141, 141)):
    if isinstance(paras, str):
        paras = [paras]
    l, r, t, b = margin
    return (f'<hp:tc name="" header="0" hasMargin="1" protect="0" editable="0" dirty="0" '
            f'borderFillIDRef="{border}">'
            f'<hp:subList id="" textDirection="HORIZONTAL" lineWrap="BREAK" vertAlign="{valign}" '
            f'linkListIDRef="0" linkListNextIDRef="0" textWidth="0" textHeight="0" '
            f'hasTextRef="0" hasNumRef="0">{"".join(paras)}</hp:subList>'
            f'<hp:cellAddr colAddr="{col}" rowAddr="{row}"/>'
            f'<hp:cellSpan colSpan="{colspan}" rowSpan="{rowspan}"/>'
            f'<hp:cellSz width="{width}" height="{height}"/>'
            f'<hp:cellMargin left="{l}" right="{r}" top="{t}" bottom="{b}"/></hp:tc>')


_tbl_id = [1500000000]


def table(rows, col_widths, row_heights, page_break='CELL', repeat_header=True, border='3', inline=True,
          para_pr='0'):
    """rows: [[cell xml, ...], ...]  (병합으로 가려진 칸은 넣지 않음)
    표 하나를 담은 문단을 돌려줍니다.
    inline=True는 '글자처럼 취급'으로 쪽을 넘어가며 나뉘지 않습니다.
    여러 쪽에 걸칠 수 있는 긴 표는 inline=False로 둡니다."""
    _tbl_id[0] += 1
    width = sum(col_widths)
    height = sum(row_heights)
    trs = ''.join('<hp:tr>' + ''.join(r) + '</hp:tr>' for r in rows)
    tbl = (f'<hp:tbl id="{_tbl_id[0]}" zOrder="0" numberingType="TABLE" textWrap="TOP_AND_BOTTOM" '
           f'textFlow="BOTH_SIDES" lock="0" dropcapstyle="None" pageBreak="{page_break}" '
           f'repeatHeader="{1 if repeat_header else 0}" rowCnt="{len(row_heights)}" '
           f'colCnt="{len(col_widths)}" cellSpacing="0" borderFillIDRef="{border}" noAdjust="1">'
           f'<hp:sz width="{width}" widthRelTo="ABSOLUTE" height="{height}" heightRelTo="ABSOLUTE" protect="0"/>'
           f'<hp:pos treatAsChar="{1 if inline else 0}" affectLSpacing="0" flowWithText="1" allowOverlap="0" '
           f'holdAnchorAndSO="0" vertRelTo="PARA" horzRelTo="PARA" vertAlign="TOP" horzAlign="LEFT" '
           f'vertOffset="0" horzOffset="0"/>'
           f'<hp:outMargin left="140" right="140" top="140" bottom="140"/>'
           f'<hp:inMargin left="140" right="140" top="140" bottom="140"/>{trs}</hp:tbl>')
    return (f'<hp:p id="0" paraPrIDRef="{para_pr}" styleIDRef="0" pageBreak="0" columnBreak="0" merged="0">'
            f'<hp:run charPrIDRef="9">{tbl}<hp:t/></hp:run></hp:p>')


class Package:
    """서식 hwpx를 읽어 header/section을 바꾼 뒤 새 파일로 씁니다."""

    def __init__(self, template=TEMPLATE):
        with zipfile.ZipFile(template) as zf:
            self.files = {n: zf.read(n) for n in zf.namelist()}
        self.header = self.files['Contents/header.xml'].decode('utf-8')
        self.section = self.files['Contents/section0.xml'].decode('utf-8')

    # ---------- 본문 ----------
    def section_head(self):
        """<hs:sec ...> 여는 태그와 첫 문단의 쪽 설정(secPr, colPr) 런."""
        s = self.section
        sec_open = s[:s.index('>', s.index('<hs:sec')) + 1]
        a = s.index('<hp:run', s.index('<hp:p '))
        b = s.index('</hp:run>', s.index('</hp:secPr>')) + len('</hp:run>')
        return sec_open, s[a:b]

    def first_para(self, extra_runs, para_pr='22'):
        """쪽 설정을 품은 첫 문단 (제목 등)."""
        _, setup = self.section_head()
        return (f'<hp:p id="0" paraPrIDRef="{para_pr}" styleIDRef="0" pageBreak="0" '
                f'columnBreak="0" merged="0">{setup}{extra_runs}</hp:p>')

    def set_body(self, paras):
        sec_open, _ = self.section_head()
        self.section = sec_open + ''.join(paras) + '</hs:sec>'

    # ---------- 스타일 추가 ----------
    def _add(self, group, tag, base_id, edit):
        m = re.search(rf'<hh:{tag} id="{base_id}"[ >].*?</hh:{tag}>', self.header, re.S)
        if not m:
            raise ValueError(f'{tag} {base_id} 없음')
        cnt_m = re.search(rf'<hh:{group} itemCnt="(\d+)"', self.header)
        ids = [int(x) for x in re.findall(rf'<hh:{tag} id="(\d+)"', self.header)]
        new_id = max(ids) + 1
        xml = re.sub(r'id="\d+"', f'id="{new_id}"', m.group(0), count=1)
        xml = edit(xml)
        end = self.header.index(f'</hh:{group}>')
        self.header = self.header[:end] + xml + self.header[end:]
        self.header = self.header.replace(cnt_m.group(0), f'<hh:{group} itemCnt="{int(cnt_m.group(1)) + 1}"', 1)
        return str(new_id)

    def add_char(self, base, height=None, bold=None, color=None):
        def edit(x):
            if height:
                x = re.sub(r'height="\d+"', f'height="{height}"', x, count=1)
            if color:
                x = re.sub(r'textColor="[^"]+"', f'textColor="{color}"', x, count=1)
            if bold and '<hh:bold/>' not in x:
                x = x.replace('<hh:underline', '<hh:bold/><hh:underline', 1)
            return x
        return self._add('charProperties', 'charPr', base, edit)

    def add_border(self, width='0.12 mm', fill=None, sides='LRTB', kinds=None):
        """테두리. sides에 든 면만 실선(L,R,T,B). kinds={'B': 'DOT'}처럼 면마다 선 종류를 바꿀 수 있습니다.
        fill='#E5E5E5' 처럼 주면 배경색."""
        kinds = kinds or {}

        def edit(x):
            for side, key in (('left', 'L'), ('right', 'R'), ('top', 'T'), ('bottom', 'B')):
                if key in kinds:
                    kind, w = kinds[key], width
                elif key in sides:
                    kind, w = 'SOLID', width
                else:
                    kind, w = 'NONE', '0.1 mm'
                x = re.sub(rf'<hh:{side}Border type="\w+" width="[^"]+"',
                           f'<hh:{side}Border type="{kind}" width="{w}"', x)
            x = re.sub(r'<hc:fillBrush>.*?</hc:fillBrush>', '', x, flags=re.S)
            if fill:
                x = x.replace('</hh:borderFill>',
                              f'<hc:fillBrush><hc:winBrush faceColor="{fill}" hatchColor="#FF000000" '
                              f'alpha="0"/></hc:fillBrush></hh:borderFill>')
            return x
        return self._add('borderFills', 'borderFill', '3', edit)

    def add_para(self, base, align=None, left=None, prev=None, next_=None, line=None, keep_next=False):
        def edit(x):
            if keep_next:
                x = x.replace('keepWithNext="0"', 'keepWithNext="1"')
            # switch/case 안과 default 안에 같은 값이 두 번 있으므로 모두 바꿉니다
            if align:
                x = re.sub(r'<hh:align horizontal="\w+"', f'<hh:align horizontal="{align}"', x)
            for key, val in (('left', left), ('prev', prev), ('next', next_)):
                if val is not None:
                    x = re.sub(rf'<hc:{key} value="-?\d+"', f'<hc:{key} value="{val}"', x)
            if line:
                x = re.sub(r'<hh:lineSpacing type="PERCENT" value="\d+"',
                           f'<hh:lineSpacing type="PERCENT" value="{line}"', x)
            return x
        return self._add('paraProperties', 'paraPr', base, edit)

    # ---------- 저장 ----------
    def save(self, out, preview_text=''):
        out = Path(out)
        out.parent.mkdir(parents=True, exist_ok=True)
        files = dict(self.files)
        files['Contents/header.xml'] = self.header.encode('utf-8')
        files['Contents/section0.xml'] = self.section.encode('utf-8')
        files.pop('Preview/PrvImage.png', None)   # 서식의 미리보기 그림은 내용과 달라서 뺍니다
        # 서식을 만든 사람의 이름 같은 문서 정보는 결과물에 옮기지 않습니다
        hpf = files['Contents/content.hpf'].decode('utf-8')
        hpf = re.sub(r'(<opf:meta name="(?:creator|lastsaveby)" content="text">)[^<]*(</opf:meta>)', r'\1\2', hpf)
        files['Contents/content.hpf'] = hpf.encode('utf-8')
        files['Preview/PrvText.txt'] = preview_text[:1000].encode('utf-8')
        with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zf:
            zf.writestr(zipfile.ZipInfo('mimetype'), files.pop('mimetype'), zipfile.ZIP_STORED)
            for name, data in files.items():
                zf.writestr(name, data)
        return out


def plain_text(section_xml):
    return '\n'.join(re.findall(r'<hp:t>([^<]*)</hp:t>', section_xml))
