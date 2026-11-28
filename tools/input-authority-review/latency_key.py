"""The allow-listed Win32 key pulse used by observe-latency.js."""

import ctypes as c
from ctypes import wintypes as w
import json
import sys
import time


class Keyboard(c.Structure):
    _fields_ = [("vk", w.WORD), ("scan", w.WORD), ("flags", w.DWORD), ("time", w.DWORD), ("extra", c.c_size_t)]


class Mouse(c.Structure):
    _fields_ = [("x", w.LONG), ("y", w.LONG), ("data", w.DWORD), ("flags", w.DWORD), ("time", w.DWORD), ("extra", c.c_size_t)]


class InputData(c.Union):
    _fields_ = [("key", Keyboard), ("mouse", Mouse)]


class Input(c.Structure):
    _fields_ = [("type", w.DWORD), ("data", InputData)]


def main(expected_hwnd, expected_pid, hold_ms):
    hwnd = int(expected_hwnd, 0)
    pid = int(expected_pid)
    hold = int(hold_ms)
    if hwnd <= 0 or pid <= 0 or hold != 120:
        raise ValueError("The observer accepts only its predefined isolated 120 ms D pulse.")
    user = c.WinDLL("user32", use_last_error=True)
    user.GetForegroundWindow.restype = w.HWND
    user.GetWindowThreadProcessId.argtypes = [w.HWND, c.POINTER(w.DWORD)]
    user.GetWindowThreadProcessId.restype = w.DWORD
    user.GetAsyncKeyState.argtypes = [c.c_int]
    user.GetAsyncKeyState.restype = c.c_short
    user.SendInput.argtypes = [w.UINT, c.POINTER(Input), c.c_int]
    user.SendInput.restype = w.UINT

    def send(vk, flags):
        event = Input(1, InputData(key=Keyboard(vk, 0, flags, 0, 0)))
        if user.SendInput(1, c.byref(event), c.sizeof(event)) != 1:
            raise RuntimeError("SendInput did not enqueue the requested edge.")

    print('{"event":"ready"}', flush=True)
    for line in sys.stdin:
        vk = {"pulse": 0x44, "recenter": 0x41}.get(line.strip())
        if vk is None:
            raise RuntimeError("Unexpected driver command.")
        foreground = user.GetForegroundWindow()
        observed_pid = w.DWORD()
        user.GetWindowThreadProcessId(foreground, c.byref(observed_pid))
        if foreground != hwnd or observed_pid.value != pid:
            raise RuntimeError("The foreground window is not the selected game root on the input desktop.")
        if any(user.GetAsyncKeyState(key) & 0x8000 for key in (0x41, 0x44)):
            raise RuntimeError("A movement key was already held before the controlled pulse.")
        send(vk, 0)
        try:
            print(json.dumps({"edge": "down", "vk": vk, "foreground": foreground, "pid": observed_pid.value}), flush=True)
            time.sleep(hold / 1000)
        finally:
            send(vk, 2)
        print(json.dumps({"edge": "up", "vk": vk, "foreground": user.GetForegroundWindow()}), flush=True)


if __name__ == "__main__":
    try:
        main(*sys.argv[1:])
    except (ValueError, RuntimeError) as exception:
        raise SystemExit(str(exception)) from exception
