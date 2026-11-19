#!/usr/bin/env python
"""한글 자동화 보안 모듈 등록 (스킬 설치 때 한 번 실행)

    python setup_hwp_security.py           지금 상태만 보여 줌
    python setup_hwp_security.py --apply   등록함 (스킬 설치의 마지막 단계)
    python setup_hwp_security.py --remove  등록을 지움

한글 자동화로 파일을 열 때 보안 모듈이 없으면 한글이
"파일에 접근하려는 시도가 있습니다. 허용하시겠습니까?" 창을 띄웁니다.
보안 모듈(FilePathCheckerModule.dll)을 등록하면 이 창 없이 열립니다.

--apply는 스킬에 들어 있는 bin/FilePathCheckerModule.dll을
%LOCALAPPDATA%\\HNC\\Automation_Module 에 복사하고(스킬 폴더를 옮기거나 지워도 계속 동작)
HKEY_CURRENT_USER\\Software\\HNC\\HwpAutomation\\Modules 에 등록합니다. 관리자 권한은 필요 없습니다.

등록하면 이 PC에서 한글 자동화를 쓰는 다른 프로그램도 확인 창 없이 파일을 열 수 있습니다.
이미 다른 이름(예: SecurityModule)으로 등록된 보안 모듈이 있으면 그것을 그대로 씁니다.
"""
import hashlib
import os
import shutil
import sys
from pathlib import Path
for _s in (sys.stdout, sys.stderr):  # 콘솔 인코딩에 없는 글자 때문에 멈추지 않도록
    if hasattr(_s, 'reconfigure'):
        _s.reconfigure(errors='replace')

KEY = r'Software\HNC\HwpAutomation\Modules'
NAME = 'FilePathCheckerModule'
# 다른 프로그램이 등록해 둔 이름도 인정함 (보안인증등록.exe는 SecurityModule로 등록)
KNOWN_NAMES = (NAME, 'SecurityModule', 'FilePathCheckDLL')
BUNDLED = Path(__file__).resolve().parent.parent / 'bin' / 'FilePathCheckerModule.dll'
SHA256 = '9ac5b97c47ac8aed1e8bca27a3eef39411361d8f68c262509f0c40a8f9d21bb6'


def install_dir():
    base = os.environ.get('LOCALAPPDATA') or str(Path.home() / 'AppData' / 'Local')
    return Path(base) / 'HNC' / 'Automation_Module'


def registered():
    """(값 이름, DLL 경로) — 등록이 없거나 DLL 파일이 없으면 None.

    render_pdf.py는 값 이름을 hwp.RegisterModule('FilePathCheckDLL', 값 이름)에 씁니다.
    """
    if sys.platform != 'win32':
        return None
    import winreg
    try:
        k = winreg.OpenKey(winreg.HKEY_CURRENT_USER, KEY)
    except OSError:
        return None
    with k:
        for name in KNOWN_NAMES:
            try:
                path, _ = winreg.QueryValueEx(k, name)
            except OSError:
                continue
            if path and Path(path).is_file():
                return name, path
    return None


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def apply():
    if not BUNDLED.is_file():
        print(f'스킬 안에 DLL이 없습니다: {BUNDLED}')
        print('  스킬 폴더(bin 포함)를 통째로 설치했는지 확인하세요.')
        return 1
    if sha256(BUNDLED) != SHA256:
        print(f'DLL이 원본과 다릅니다(바뀌었거나 손상됨). 등록하지 않습니다: {BUNDLED}')
        return 1
    dst_dir = install_dir()
    dst = dst_dir / BUNDLED.name
    try:
        dst_dir.mkdir(parents=True, exist_ok=True)
        if not dst.is_file() or sha256(dst) != SHA256:
            shutil.copyfile(BUNDLED, dst)
    except OSError as e:
        print(f'DLL을 복사하지 못했습니다: {dst} ({e})')
        return 1
    import winreg
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, KEY) as k:
        winreg.SetValueEx(k, NAME, 0, winreg.REG_SZ, str(dst))
    print(f'등록했습니다: {NAME} = {dst}')
    print('이제 한글 자동화로 파일을 열 때 접근 허용 확인 창이 뜨지 않습니다.')
    print('지우려면: python setup_hwp_security.py --remove')
    return 0


def remove():
    import winreg
    dst = install_dir() / BUNDLED.name
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, KEY, 0,
                            winreg.KEY_QUERY_VALUE | winreg.KEY_SET_VALUE) as k:
            path, _ = winreg.QueryValueEx(k, NAME)
            # 이 스킬이 등록한 값만 지움 (다른 프로그램이 같은 이름으로 등록한 것은 그대로 둠)
            if os.path.normcase(os.path.abspath(path)) == os.path.normcase(str(dst)):
                winreg.DeleteValue(k, NAME)
                print(f'레지스트리에서 {NAME} 값을 지웠습니다.')
            else:
                print(f'{NAME} 값은 다른 프로그램이 등록한 것이라 그대로 둡니다: {path}')
    except OSError:
        print('이 스킬이 등록한 값이 없습니다.')
    try:
        dst.unlink()
        print(f'지웠습니다: {dst}')
    except OSError:
        pass
    left = registered()
    if left:
        print(f'다른 프로그램이 등록한 보안 모듈은 남아 있습니다: {left[0]} = {left[1]}')
    return 0


def main():
    if sys.platform != 'win32':
        print('Windows가 아니므로 필요 없습니다 (한글 자동화는 Windows 전용).')
        return 0
    if '--remove' in sys.argv:
        return remove()
    cur = registered()
    if cur:
        print(f'이미 등록됨: {cur[0]} = {cur[1]}')
        return 0
    if '--apply' in sys.argv:
        return apply()
    print('등록되어 있지 않습니다. 등록하려면 --apply 를 붙여 실행하세요.')
    return 1


if __name__ == '__main__':
    sys.exit(main())
