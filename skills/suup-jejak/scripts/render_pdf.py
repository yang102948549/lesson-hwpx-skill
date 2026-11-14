#!/usr/bin/env python
"""한글(한컴오피스)로 hwpx를 열어 PDF로 저장합니다. 결과 확인용.

    python scripts/render_pdf.py <파일.hwpx> [<파일.hwpx> ...]

Windows, 한컴오피스, pywin32가 있어야 하고, 보안 모듈(FilePathCheckerModule)이
레지스트리에 등록되어 있어야 확인 창 없이 열립니다.
AI 도구의 샌드박스 안에서는 한글 자동화가 막힐 수 있습니다. 그때는 이 단계를 건너뛰고
validate_hwpx.py로 점검한 뒤, 사용자에게 한글에서 열어 확인해 달라고 합니다.
"""
import sys
from pathlib import Path
for _s in (sys.stdout, sys.stderr):  # 콘솔 인코딩에 없는 글자 때문에 멈추지 않도록
    if hasattr(_s, 'reconfigure'):
        _s.reconfigure(errors='replace')

SKIP = 2   # 이 환경에서는 PDF 확인을 할 수 없음 (오류가 아니라 건너뜀)


def fail(msg):
    print(f'PDF 확인 건너뜀: {msg}')
    print('validate_hwpx.py 결과를 알리고, 한글에서 열어 확인해 달라고 사용자에게 요청하세요.')
    sys.exit(SKIP)


def render(paths):
    if sys.platform != 'win32':
        fail('Windows가 아닙니다.')
    try:
        import win32com.client
    except ImportError:
        fail('pywin32가 없습니다 (pip install pywin32).')
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from setup_hwp_security import registered
    if not registered():
        # 보안 모듈 없이 열면 숨은 창에 '접근 허용' 확인 창이 떠서 멈춥니다
        fail('한글 보안 모듈이 등록되어 있지 않습니다. '
             'PDF 확인이 필요하면 사용자에게 setup_hwp_security.py 설명 후 동의를 받아 --apply로 등록하세요.')
    try:
        hwp = win32com.client.Dispatch('HWPFrame.HwpObject')
    except Exception as e:  # noqa: BLE001
        fail(f'한글 자동화를 시작할 수 없습니다. 한컴오피스가 없거나 샌드박스가 막았을 수 있습니다. ({e})')
    try:
        hwp.RegisterModule('FilePathCheckDLL', 'FilePathCheckerModule')
        hwp.XHwpWindows.Item(0).Visible = False
        for p in paths:
            src = Path(p).resolve()
            pdf = src.with_suffix('.pdf')
            if not hwp.Open(str(src), 'HWPX', 'forceopen:true'):
                print('열기 실패:', src)
                continue
            hwp.SaveAs(str(pdf), 'PDF', '')
            pages = hwp.PageCount
            hwp.Clear(1)
            print(f'PDF: {pdf} ({pages}쪽)')
    except Exception as e:  # noqa: BLE001
        fail(f'한글 자동화 중 오류: {e}')
    finally:
        try:
            hwp.Quit()
        except Exception:  # noqa: BLE001
            pass


if __name__ == '__main__':
    render(sys.argv[1:])
