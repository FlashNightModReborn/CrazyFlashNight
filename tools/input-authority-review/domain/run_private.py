"""Run the Modifier WinForms probe on a newly created desktop without switching to it."""

import ctypes as ctypes
from ctypes import wintypes as win
from pathlib import Path
import subprocess
import sys
from uuid import uuid4


class StartupInfo(ctypes.Structure):
    _fields_ = [
        ("size", win.DWORD), ("reserved", win.LPWSTR), ("desktop", win.LPWSTR), ("title", win.LPWSTR),
        ("x", win.DWORD), ("y", win.DWORD), ("width", win.DWORD), ("height", win.DWORD),
        ("columns", win.DWORD), ("rows", win.DWORD), ("fill", win.DWORD), ("flags", win.DWORD),
        ("show", win.WORD), ("reserved_count", win.WORD), ("reserved_bytes", ctypes.c_void_p),
        ("stdin", win.HANDLE), ("stdout", win.HANDLE), ("stderr", win.HANDLE),
    ]


class ProcessInfo(ctypes.Structure):
    _fields_ = [("process", win.HANDLE), ("thread", win.HANDLE), ("pid", win.DWORD), ("tid", win.DWORD)]


def bind(library, name, result, *args):
    function = getattr(library, name)
    function.argtypes = list(args)
    function.restype = result
    return function


def main(executable, runtime, project, output, core_sha256):
    user = ctypes.WinDLL("user32", use_last_error=True)
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    create_desktop = bind(user, "CreateDesktopW", win.HANDLE, win.LPCWSTR, win.LPCWSTR, ctypes.c_void_p,
                          win.DWORD, win.DWORD, ctypes.c_void_p)
    close_desktop = bind(user, "CloseDesktop", win.BOOL, win.HANDLE)
    create_process = bind(kernel, "CreateProcessW", win.BOOL, win.LPCWSTR, win.LPWSTR, ctypes.c_void_p,
                          ctypes.c_void_p, win.BOOL, win.DWORD, ctypes.c_void_p, win.LPCWSTR,
                          ctypes.POINTER(StartupInfo), ctypes.POINTER(ProcessInfo))
    wait = bind(kernel, "WaitForSingleObject", win.DWORD, win.HANDLE, win.DWORD)
    terminate = bind(kernel, "TerminateProcess", win.BOOL, win.HANDLE, win.UINT)
    exit_code = bind(kernel, "GetExitCodeProcess", win.BOOL, win.HANDLE, ctypes.POINTER(win.DWORD))
    close_handle = bind(kernel, "CloseHandle", win.BOOL, win.HANDLE)

    run_id = uuid4().hex
    desktop_name = "CF7Review-" + run_id
    desktop = create_desktop(desktop_name, None, None, 0, 0x1FF, None)
    if not desktop:
        raise ctypes.WinError(ctypes.get_last_error())
    child = ProcessInfo()
    try:
        executable = Path(executable).resolve(strict=True)
        output = Path(output).resolve()
        if output.exists():
            raise FileExistsError(output)
        startup = StartupInfo()
        startup.size, startup.desktop = ctypes.sizeof(StartupInfo), desktop_name
        argv = [str(executable), str(Path(runtime).resolve(strict=True)), str(Path(project).resolve(strict=True)),
                str(output), run_id, core_sha256]
        command = ctypes.create_unicode_buffer(subprocess.list2cmdline(argv))
        if not create_process(str(executable), command, None, None, False, 0x08000000, None,
                              str(executable.parent), ctypes.byref(startup), ctypes.byref(child)):
            raise ctypes.WinError(ctypes.get_last_error())
        result = wait(child.process, 55_000)
        if result != 0:
            terminate(child.process, 124)
            wait(child.process, 2_000)
            raise RuntimeError(f"Private-desktop probe wait returned {result:#x} for PID {child.pid}.")
        code = win.DWORD()
        if not exit_code(child.process, ctypes.byref(code)):
            raise ctypes.WinError(ctypes.get_last_error())
        return code.value
    finally:
        if child.thread:
            close_handle(child.thread)
        if child.process:
            close_handle(child.process)
        close_desktop(desktop)


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:]))
