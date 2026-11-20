"""Exercise the real Windows bootstrap dialogs against a private copy of a v2 candidate."""
import argparse
import csv
import ctypes
from ctypes import wintypes
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

EXE = "CRAZYFLASHER7MercenaryEmpire.exe"
BROKER = "runtime/FlashInputBroker.exe"
ERROR_CODE = "CF7-BOOT-FILE-INTEGRITY"
user = ctypes.WinDLL("user32", use_last_error=True)
user.FindWindowExW.argtypes = [wintypes.HWND, wintypes.HWND, wintypes.LPCWSTR, wintypes.LPCWSTR]
user.FindWindowExW.restype = wintypes.HWND
user.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
user.SendMessageTimeoutW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM,
                                     wintypes.UINT, wintypes.UINT, ctypes.POINTER(ctypes.c_size_t)]
user.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]


def read_dialog(process):
    deadline = time.monotonic() + 30
    while process.poll() is None and time.monotonic() < deadline:
        window = None
        while window := user.FindWindowExW(None, window, "#32770", "CF7:FlashNight"):
            pid = wintypes.DWORD()
            user.GetWindowThreadProcessId(window, ctypes.byref(pid))
            if pid.value != process.pid:
                continue
            chunks = []
            child = None
            while child := user.FindWindowExW(window, child, "Static", None):
                buf = ctypes.create_unicode_buffer(8192)
                size = ctypes.c_size_t()
                if user.SendMessageTimeoutW(child, 0x000D, len(buf), ctypes.addressof(buf),
                                            2, 2000, ctypes.byref(size)) and size.value:
                    chunks.append(buf.value)
            if chunks:
                user.PostMessageW(window, 0x0111, 7, 0)  # IDNO closes this process's MessageBox.
                return "\n".join(chunks)
        time.sleep(0.05)
    raise AssertionError(f"Bootstrap dialog unavailable (exit={process.poll()})")


def check_dialog(root, label, expected, *, missing=(), truncated=False, evidence=None):
    log_path = root / "logs/bootstrap.log"
    log_path.unlink(missing_ok=True)
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    process = subprocess.Popen([str(root / EXE)], cwd=root, startupinfo=startup)
    try:
        message = read_dialog(process)
        assert process.wait(timeout=10) == 1
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
    log = log_path.read_text(encoding="utf-8-sig")
    if evidence:
        (evidence / f"{label}-dialog.txt").write_text(message, encoding="utf-8")
        (evidence / f"{label}-bootstrap.log").write_text(log, encoding="utf-8")
    for text in [ERROR_CODE, "logs/bootstrap.log", *expected]:
        assert text in message, (label, text, message)
    assert log.count("[manifest] verification FAILED") == 1, label
    assert ("另有异常" in message) == truncated, message
    assert ("查看安全软件的保护历史" in message) == bool(missing), message
    for name in missing:
        assert f"[integrity] 缺失文件：{name}" in log, (label, name)
    assert message.count("缺失文件：") == min(len(missing), 4), message
    print(f"{label} OK", flush=True)


def exercise(root, candidate, project, evidence):
    shutil.copy2(candidate / EXE, root / EXE)
    shutil.copytree(candidate / "runtime", root / "runtime")
    for name in ["Adobe Flash Player 20.exe", "CRAZYFLASHER7MercenaryEmpire.swf",
                 "launcher/web/bootstrap.html", "crossdomain.xml"]:
        target = root / name
        target.parent.mkdir(exist_ok=True, parents=True)
        shutil.copy2(project / name, target)

    def verify():
        subprocess.run([str(root / EXE), "--verify-only"], cwd=root, check=True, timeout=60)

    def check(label, *text, **kwargs):
        check_dialog(root, label, text, evidence=evidence, **kwargs)

    verify()
    broker = root / BROKER
    original = broker.read_bytes()
    broker.unlink()
    check("missing", f"缺失文件：{BROKER}", missing=[BROKER])
    broker.write_bytes(original + b"\0")
    check("length", f"文件长度不符：{BROKER}")
    broker.write_bytes(bytes([original[0] ^ 1]) + original[1:])
    check("digest", f"文件内容不符（SHA-256）：{BROKER}")
    broker.write_bytes(original)

    # Only the fixture copy receives a deny entry. The account retains WRITE_DAC.
    identity = subprocess.check_output(["whoami", "/user", "/fo", "csv", "/nh"])
    sid = next(csv.reader(identity.decode("mbcs").splitlines()))[-1]
    try:
        subprocess.run(["icacls", str(broker), "/deny", f"*{sid}:(RD,RA)"],
                       check=True, stdout=subprocess.DEVNULL)
        check("access-denied", f"无法读取或校验：{BROKER}（Windows 5 ")
    finally:
        subprocess.run(["icacls", str(broker), "/remove:d", f"*{sid}"],
                       check=True, stdout=subprocess.DEVNULL)

    many = [BROKER, "runtime/FlashInputBridge.dll", "runtime/WebView2Loader.dll",
            "runtime/miniaudio.dll", "runtime/sol_parser.dll", "runtime/Microsoft.Web.WebView2.Core.dll"]
    for name in many:
        (root / name).unlink()
    check("multiple", missing=many, truncated=True)
    for name in many:
        shutil.copy2(candidate / name, root / name)
    verify()
    print("Restored full-install verification OK", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path, help="verified candidate or formal installation root")
    parser.add_argument("--evidence", type=Path, help="save actual message text and raw logs")
    args = parser.parse_args()
    if args.evidence:
        args.evidence.mkdir(parents=True, exist_ok=True)
    project_root = Path(__file__).resolve().parents[3]
    with tempfile.TemporaryDirectory(prefix="cf7-boot-dialog-") as working:
        exercise(Path(working), args.candidate.resolve(), project_root, args.evidence)
