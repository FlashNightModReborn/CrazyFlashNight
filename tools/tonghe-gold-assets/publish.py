"""Publish with session-only original glyph subsets, then release the resources.

The three subset fonts were extracted from the pre-change published library.
They supply only existing static label glyphs. No font registry entry is written.
"""
from __future__ import annotations
import ctypes
from ctypes import wintypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
EVIDENCE=ROOT/'tmp/tonghe-gold'
FONT_FILES=['29_STXingkai.ttf','126_STFangsong.ttf','1154_STLiti.ttf']

def main():
    if (ROOT/'scripts/compile_state_uncertain.marker').exists():
        raise SystemExit('Compile state is uncertain; use the documented recovery procedure first')
    EVIDENCE.mkdir(parents=True,exist_ok=True)
    gdi=ctypes.WinDLL('gdi32',use_last_error=True)
    gdi.AddFontResourceExW.argtypes=[wintypes.LPCWSTR,wintypes.DWORD,ctypes.c_void_p]
    gdi.AddFontResourceExW.restype=ctypes.c_int
    gdi.RemoveFontResourceExW.argtypes=[wintypes.LPCWSTR,wintypes.DWORD,ctypes.c_void_p]
    gdi.RemoveFontResourceExW.restype=wintypes.BOOL
    user=ctypes.WinDLL('user32',use_last_error=True)
    user.SendMessageTimeoutW.argtypes=[wintypes.HWND,wintypes.UINT,wintypes.WPARAM,wintypes.LPARAM,wintypes.UINT,wintypes.UINT,ctypes.POINTER(ctypes.c_size_t)]
    user.SendMessageTimeoutW.restype=wintypes.LPARAM
    loaded=[];receipt={'font_resources':[],'registry_changes':False,'compile_exit':None}
    try:
        for name in FONT_FILES:
            p=HERE/'compile-fonts'/name
            n=gdi.AddFontResourceExW(str(p),0,None)
            if n<=0:raise OSError(ctypes.get_last_error(),'Could not load original font subset '+name)
            loaded.append(p)
            receipt['font_resources'].append({'file':name,'faces_loaded':n,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
        response=ctypes.c_size_t()
        user.SendMessageTimeoutW(0xffff,0x001d,0,0,2,2000,ctypes.byref(response))
        print('ORIGINAL_FONT_RESOURCES_READY '+json.dumps(receipt['font_resources']),flush=True)
        child_env=os.environ.copy()
        # Do not pass a PowerShell 7-only module search path into Windows PS 5.
        child_env['PSModulePath']=str(Path(os.environ['SystemRoot'])/'System32/WindowsPowerShell/v1.0/Modules')
        powershell=str(Path(os.environ['SystemRoot'])/'System32/WindowsPowerShell/v1.0/powershell.exe')
        probe=subprocess.run([powershell,'-NoProfile','-Command',"@(Get-Process Flash -ErrorAction SilentlyContinue).Count"],env=child_env,capture_output=True,text=True)
        if probe.returncode or probe.stdout.strip()!='0':
            raise SystemExit('Close CS6 before running the font-session publisher so its font cache starts clean')
        bootstrap=subprocess.run([powershell,'-NoProfile','-Command',"Start-ScheduledTask -TaskName FlashCS6Task; Start-Sleep -Seconds 3"],env=child_env)
        if bootstrap.returncode:raise SystemExit('Could not start the existing CS6 task')
        receipt['owned_host_started']=True
        command=[powershell,'-NoProfile','-File','scripts/compile_test.ps1',
                 '-Target','flashswf/arts/素材库-物品技能图标/素材库-物品技能图标.xfl',
                 '-PublishOnly','-VerifySwf','flashswf/arts/素材库-物品技能图标.swf',
                 '-TimeoutSeconds','600','-QuitFlashAfterPublish']
        with (EVIDENCE/'compile-font-safe.log').open('wb') as log:
            completed=subprocess.run(command,cwd=ROOT,env=child_env,stdout=log,stderr=subprocess.STDOUT)
        receipt['compile_exit']=completed.returncode
        if completed.returncode:
            # Keep resources alive if a late publisher could still be using them.
            if (ROOT/'scripts/compile_state_uncertain.marker').exists():
                print('Compilation remains uncertain; holding original font resources until a later terminal',flush=True)
                marker=ROOT/'scripts/compile_state_uncertain.marker'
                while not (ROOT/'scripts/publish_done.marker').exists() or (ROOT/'scripts/publish_done.marker').stat().st_mtime<marker.stat().st_mtime:
                    time.sleep(.5)
            raise SystemExit(completed.returncode)
    finally:
        receipt['resources_released']=[]
        for p in reversed(loaded):
            receipt['resources_released'].append({'file':p.name,'released':bool(gdi.RemoveFontResourceExW(str(p),0,None))})
        response=ctypes.c_size_t()
        user.SendMessageTimeoutW(0xffff,0x001d,0,0,2,2000,ctypes.byref(response))
        (EVIDENCE/'font-session-receipt.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
    print('FONT_SAFE_PUBLICATION_COMPLETE',flush=True)

if __name__=='__main__':main()
