#!/usr/bin/env python
"""한글 자동화 보안 모듈 등록 (PDF 확인용, 선택 사항)

    python setup_hwp_security.py          지금 상태만 보여 줌
    python setup_hwp_security.py --apply  등록함 (사용자가 동의한 경우에만)

render_pdf.py가 한글로 파일을 열 때, 보안 모듈이 없으면 한글이
"파일에 접근하려는 시도가 있습니다. 허용하시겠습니까?" 창을 띄웁니다.
보안 모듈(FilePathCheckerModule.dll)을 등록하면 이 창 없이 열립니다.

등록하면 이 PC에서 한글 자동화를 쓰는 다른 프로그램도 확인 창 없이 파일을 열 수 있게 됩니다.
그래서 AI가 스스로 실행하지 말고, 사용자에게 설명하고 동의를 받은 뒤 --apply로 실행합니다.
지도안·활동지 hwpx를 만드는 데는 필요 없습니다.

등록 위치: HKEY_CURRENT_USER\\Software\\HNC\\HwpAutomation\\Modules  (관리자 권한 필요 없음)
DLL은 pyhwpx 패키지에 들어 있는 것을 씁니다 (pip install pyhwpx).
"""
import importlib.util
import sys
from pathlib import Path
for _s in (sys.stdout, sys.stderr):  # 콘솔 인코딩에 없는 글자 때문에 멈추지 않도록
    if hasattr(_s, 'reconfigure'):
        _s.reconfigure(errors='replace')

KEY = r'Software\HNC\HwpAutomation\Modules'
NAME = 'FilePathCheckerModule'


def registered():
    """등록된 DLL 경로 (없거나 파일이 없으면 None)."""
    if sys.platform != 'win32':
        return None
    import winreg
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, KEY) as k:
            path, _ = winreg.QueryValueEx(k, NAME)
    except OSError:
        return None
    return path if Path(path).is_file() else None


def find_dll():
    spec = importlib.util.find_spec('pyhwpx')
    if not spec or not spec.origin:
        return None
    dll = Path(spec.origin).parent / 'FilePathCheckerModule.dll'
    return dll if dll.is_file() else None


def main():
    if sys.platform != 'win32':
        print('Windows가 아니므로 필요 없습니다 (한글 자동화는 Windows 전용).')
        return 0
    cur = registered()
    if cur:
        print(f'이미 등록됨: {cur}')
        return 0
    dll = find_dll()
    if not dll:
        print('등록되어 있지 않습니다. DLL을 찾지 못했습니다.')
        print('  pip install pyhwpx  로 설치한 뒤 다시 실행하세요.')
        return 1
    if '--apply' not in sys.argv:
        print('등록되어 있지 않습니다.')
        print(f'  등록할 DLL: {dll}')
        print('  사용자 동의를 받은 뒤 --apply 를 붙여 실행하세요.')
        return 1
    import winreg
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, KEY) as k:
        winreg.SetValueEx(k, NAME, 0, winreg.REG_SZ, str(dll))
    print(f'등록했습니다: {dll}')
    print('지우려면: 레지스트리 편집기에서 HKEY_CURRENT_USER\\' + KEY + ' 의 ' + NAME + ' 값을 삭제')
    return 0


if __name__ == '__main__':
    sys.exit(main())
