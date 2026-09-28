#!/usr/bin/env python3
"""在 Linux 上离线构建 #46 诊断探针；不安装依赖，只写入全新输出目录。"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
KERNEL = {
    "GetStdHandle": 4, "WriteFile": 20, "GetLastError": 0, "GetCommandLineW": 0,
    "GetACP": 0, "GetOEMCP": 0, "GetCurrentProcessId": 0, "ExitProcess": 4,
    "FindFirstFileW": 8, "FindNextFileW": 8, "FindClose": 4,
    "CreateFileW": 28, "ReadFile": 20, "CloseHandle": 4, "LocalFree": 4,
}
SHELL = {"CommandLineToArgvW": 8}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(out: Path, linux_only: bool) -> dict:
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        raise ValueError("本构建配方仅验证过 Linux x86_64；其他环境需单独移植/验证")
    names = ["cc"] if linux_only else ["cc", "clang", "lld-link"]
    tools = {}
    for name in names:
        found = shutil.which(name)
        if not found:
            raise ValueError(f"missing compiler: {name}; 本工具不会自动安装")
        tools[name] = str(Path(found).absolute())
    out = out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    work = out / "objects"
    work.mkdir()
    record = {"schema": "cf7-issue46-build/v1", "platform": platform.platform(),
              "scope": "compiled-only; build script does not execute produced binaries",
              "tools": tools, "source_sha256": {p.name: sha(p) for p in
              (ROOT / "locale_probe.c", ROOT / "win_file_probe.c", ROOT / "build.py")},
              "commands": [], "artifacts": [], "success": False}
    env = dict(os.environ, LC_ALL="C", LANG="C", SOURCE_DATE_EPOCH="0")

    def run(args: list[str]) -> None:
        result = subprocess.run(args, cwd=work, env=env, capture_output=True, timeout=90)
        record["commands"].append({"argv": args, "returncode": result.returncode,
            "stdout": result.stdout.decode("utf-8", "backslashreplace"),
            "stderr": result.stderr.decode("utf-8", "backslashreplace")})
        if result.returncode:
            raise RuntimeError(f"command failed ({result.returncode}): {args}")

    try:
        for tool in tools.values():
            run([tool, "--version"])
        native = out / "locale-probe-linux-x86_64"
        run([tools["cc"], "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
             "-Wl,--build-id=none", str(ROOT / "locale_probe.c"), "-o", str(native)])
        record["artifacts"].append({"name": native.name, "bytes": native.stat().st_size,
                                    "sha256": sha(native), "executed_by_build": False})
        if not linux_only:
            for library, exports in (("kernel32", KERNEL), ("shell32", SHELL)):
                (work / (library + ".def")).write_text("LIBRARY " + library.upper() +
                    ".dll\nEXPORTS\n" + "\n".join(exports) + "\n", encoding="ascii")
            for bits, target, machine in ((64, "x86_64-pc-windows-msvc", "x64"),
                                           (32, "i686-pc-windows-msvc", "x86")):
                libs = []
                for library in ("kernel32", "shell32"):
                    lib = work / f"{library}-{machine}.lib"
                    run([tools["lld-link"], "/lib", f"/def:{work / (library + '.def')}",
                         f"/machine:{machine}", f"/out:{lib}"])
                    libs.append(str(lib))
                obj = work / f"win{bits}.obj"
                run([tools["clang"], f"--target={target}", "-std=c11", "-O2",
                     "-fno-stack-protector", "-fno-builtin", "-Wall", "-Wextra", "-Werror",
                     "-c", str(ROOT / "win_file_probe.c"), "-o", str(obj)])
                exe = out / f"win-file-probe-{machine}.exe"
                args = [tools["lld-link"], "/entry:mainCRTStartup", "/subsystem:console",
                        "/nodefaultlib", f"/machine:{machine}", "/timestamp:0", f"/out:{exe}",
                        str(obj), *libs]
                # x86 调用约定保留 stdcall；仅将装饰后的 IAT 符号绑定到未装饰的系统导入名。
                if bits == 32:
                    args += [f"/alternatename:__imp__{name}@{size}=__imp__{name}"
                             for name, size in {**KERNEL, **SHELL}.items()]
                run(args)
                record["artifacts"].append({"name": exe.name, "bytes": exe.stat().st_size,
                                           "sha256": sha(exe), "executed_by_build": False})
        record["success"] = True
        return record
    finally:
        (out / "build-result.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) +
                                                "\n", encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", type=Path, required=True, help="必须是尚不存在的输出目录")
    ap.add_argument("--linux-only", action="store_true")
    args = ap.parse_args()
    try:
        result = build(args.out, args.linux_only)
        print(json.dumps(result["artifacts"], ensure_ascii=False, indent=2))
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
        print(f"CF7_BUILD_ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
