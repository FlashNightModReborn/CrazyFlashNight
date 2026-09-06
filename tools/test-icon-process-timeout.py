"""真实子进程验证 FFDec 命令超时；隔离的短期进程，不调用实际 FFDec。"""
import ctypes
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("icon_bake_process_test", ROOT / "tools/bake-icons-offline.py")
icons = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = icons
spec.loader.exec_module(icons)


def is_running(pid):
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenProcess.restype = ctypes.c_void_p
    kernel.GetExitCodeProcess.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong)]
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    handle = kernel.OpenProcess(0x1000, False, pid)
    if not handle:
        return False
    try:
        code = ctypes.c_ulong()
        return bool(kernel.GetExitCodeProcess(handle, ctypes.byref(code))) and code.value == 259
    finally:
        kernel.CloseHandle(handle)


class ProcessTimeout(unittest.TestCase):
    def test_result_keeps_exit_code_and_utf8_output(self):
        result = icons.run_command([sys.executable, "-X", "utf8", "-c", "print('强化石'); raise SystemExit(7)"], ROOT, 10)
        self.assertEqual(result.returncode, 7)
        self.assertIn("强化石", result.stdout)

    def test_timeout_is_bounded_and_keeps_partial_output(self):
        started = time.monotonic()
        result = icons.run_command([sys.executable, "-c", "import time; print('started',flush=True); time.sleep(60)"], ROOT, 1)
        self.assertLess(time.monotonic() - started, 8)
        self.assertEqual(result.returncode, 124)
        self.assertIn("started", result.stdout)
        self.assertIn("timeout", result.stdout)

    @unittest.skipUnless(os.name == "nt", "Windows 批处理子进程树")
    def test_batch_timeout_ends_the_child_holding_output(self):
        base = (ROOT / "tmp").resolve()
        base.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="icon-process-test-", dir=base) as directory:
            folder = Path(directory).resolve()
            self.assertTrue(folder.is_relative_to(base))
            child, pid_file, batch = folder / "child.py", folder / "child.pid", folder / "wrapper.cmd"
            child.write_text("import os,sys,time\nfrom pathlib import Path\nPath(sys.argv[1]).write_text(str(os.getpid()))\nprint('child started',flush=True)\ntime.sleep(60)\n", encoding="utf-8")
            batch.write_text(f'@echo off\n"{sys.executable}" -X utf8 -B "{child}" "{pid_file}"\n', encoding="utf-8")
            started = time.monotonic()
            result = icons.run_command([str(batch)], ROOT, 1)
            pid = int(pid_file.read_text())
            try:
                self.assertLess(time.monotonic() - started, 8)
                self.assertEqual(result.returncode, 124)
                self.assertIn("child started", result.stdout)
                self.assertFalse(is_running(pid), "超时后批处理的子进程仍在运行")
            finally:
                if is_running(pid):
                    subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)


if __name__ == "__main__":
    unittest.main()
