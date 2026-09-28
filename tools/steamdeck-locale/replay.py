#!/usr/bin/env python3
"""CF7 #46：真实 NLS 表前缀 + 历史日志重放；native libc 矩阵。

只用标准库。Proton 环境改写属于已标记的源码模型，不执行 Proton/Wine。
"""
from __future__ import annotations
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
from typing import Any

ROOT = Path(__file__).resolve().parent
PREFIX_SHA256 = "543e11ac0d685983e53e97d3d7411f0d1d9912d0ab179099d85866b6f9ff426e"
PAYLOAD = b"CF7 issue46 Unicode filename probe v1\n"
MATRIX = [
    ("all_unset", {}, 20, 20, 20127),
    ("lang_utf8", {"LANG": "C.UTF-8"}, 0, 0, 65001),
    ("ctype_c_overrides_lang", {"LANG": "C.UTF-8", "LC_CTYPE": "C"}, 20, 20, 20127),
    ("ctype_posix_overrides_lang", {"LANG": "C.UTF-8", "LC_CTYPE": "POSIX"}, 20, 20, 20127),
    ("outer_all_c_removed", {"LANG": "C.UTF-8", "LC_CTYPE": "C.UTF-8", "LC_ALL": "C"}, 20, 0, 65001),
    ("outer_all_utf8_removed", {"LANG": "C.UTF-8", "LC_CTYPE": "C", "LC_ALL": "C.UTF-8"}, 0, 20, 20127),
    ("host_utf8_wins", {"LANG": "C", "LC_CTYPE": "C", "LC_ALL": "C", "HOST_LC_ALL": "C.UTF-8"}, 20, 0, 65001),
    ("host_posix_poison", {"LANG": "C.UTF-8", "LC_ALL": "C.UTF-8", "HOST_LC_ALL": "POSIX"}, 0, 20, 20127),
    ("host_empty_removes_all", {"LANG": "C.UTF-8", "LC_CTYPE": "C", "LC_ALL": "C.UTF-8", "HOST_LC_ALL": ""}, 0, 20, 20127),
    ("invalid_host_is_not_ascii_branch", {"LANG": "C.UTF-8", "HOST_LC_ALL": "CF7_MISSING_LOCALE.UTF-8"}, 0, 21, 65001),
    ("invalid_ctype_is_not_ascii_branch", {"LANG": "C.UTF-8", "LC_CTYPE": "CF7_MISSING_LOCALE.UTF-8"}, 21, 21, 65001),
    ("invalid_lang_is_not_ascii_branch", {"LANG": "CF7_MISSING_LOCALE.UTF-8"}, 21, 21, 65001),
    ("empty_all_falls_back_to_lang", {"LANG": "C.UTF-8", "LC_ALL": ""}, 0, 0, 65001),
    ("language_does_not_select_codeset", {"LANG": "C.UTF-8", "LANGUAGE": "C"}, 0, 0, 65001),
    ("python_utf8_does_not_fix_native_c", {"LANG": "C", "LC_CTYPE": "C", "LC_ALL": "C", "PYTHONUTF8": "1"}, 20, 20, 20127),
    ("host_alias_c_utf8", {"LANG": "C", "LC_CTYPE": "C", "HOST_LC_ALL": "C.utf8"}, 20, 0, 65001),
]

def load_prefix(path: Path | None = None) -> bytes:
    text = (path or ROOT / "fixtures/c_20127.prefix.b64").read_text(encoding="ascii")
    data = base64.b64decode("".join(text.split()), validate=True)
    if hashlib.sha256(data).hexdigest() != PREFIX_SHA256:
        raise ValueError("NLS prefix identity mismatch")
    return data


def parse_sbcs_table(data: bytes) -> tuple[int, ...]:
    if len(data) < 28:
        raise ValueError("truncated NLS header")
    header_words, cp, max_char_size = struct.unpack_from("<3H", data)
    if not 13 <= header_words <= 64 or cp != 20127 or max_char_size != 1:
        raise ValueError("unsupported NLS header/codepage")
    start = 2 * (header_words + 1)
    if len(data) < start + 512:
        raise ValueError("truncated NLS multibyte table")
    return struct.unpack_from("<256H", data, start)


def decode_wine_string(text: str) -> str:
    """解码所用 Wine 日志格式；未知/不完整转义直接失败，不猜测。"""
    out: list[str] = []
    simple = {"n": "\n", "r": "\r", "t": "\t", "b": "\b", "f": "\f", "v": "\v", '"': '"', "\\": "\\"}
    i = 0
    while i < len(text):
        if text[i] != "\\":
            out.append(text[i]); i += 1; continue
        i += 1
        if i >= len(text):
            raise ValueError("trailing Wine escape")
        # Wine 的 Unicode 转义是四位十六进制；先识别完整四位。
        if re.fullmatch(r"[0-9a-fA-F]{4}", text[i:i+4]):
            out.append(chr(int(text[i:i+4], 16))); i += 4
        elif text[i] in simple:
            out.append(simple[text[i]]); i += 1
        else:
            raise ValueError(f"unsupported Wine escape at {i}")
    return "".join(out)


def extract_wine_field(line: str, field: str) -> str:
    match = re.search(r"\b" + re.escape(field) + r' L"((?:\\.|[^"\\])*)"', line)
    if not match:
        raise ValueError(f"missing Wine field: {field}")
    return decode_wine_string(match.group(1))


def replay(observation: dict[str, Any] | None = None) -> dict[str, Any]:
    if observation is None:
        observation = json.loads((ROOT / "fixtures/filename-observation.json").read_text(encoding="utf-8"))
    obs = observation["filenameObservation"]
    name = obs["requestedFilename"]
    source_bytes = name.encode("utf-8")
    logged_bytes = bytes.fromhex(obs["hostFilesystemObservation"]["nameUtf8Hex"])
    table = parse_sbcs_table(load_prefix())
    table_result = "".join(chr(table[b]) for b in source_bytes)
    line = obs["wineDirectoryEnumerationLine"]
    parsed_long = extract_wine_field(line, "long")
    parsed_mask = extract_wine_field(line, "mask")
    checks = {
        "utf8_bytes_match_historical_record": source_bytes == logged_bytes,
        "mask_is_original_unicode_name": parsed_mask == name,
        "real_nls_table_matches_parsed_log": table_result == parsed_long,
        "independent_saved_observation_matches_log": obs["utf8BytesWithHighBitsRemoved"] == parsed_long,
        "all_256_table_entries_equal_byte_and_0x7f": all(value == (b & 0x7f) for b, value in enumerate(table)),
        "utf8_control_preserves_original_name": source_bytes.decode("utf-8") == name,
        "utf8_control_differs_from_broken_log": source_bytes.decode("utf-8") != parsed_long,
        "ascii_control_unchanged": "".join(chr(table[b]) for b in b"ascii.swf") == "ascii.swf",
    }
    return {
        "schema": "cf7-issue46-nls-replay/v1", "scope": "offline-table-and-historical-excerpt",
        "wine_executed": False, "deck_executed": False,
        "nls_material": "first 540 bytes only; not a complete installed Proton artifact",
        "nls_prefix_sha256": PREFIX_SHA256,
        "input_utf8_hex": source_bytes.hex(" "),
        "output_utf16le_hex": table_result.encode("utf-16le").hex(" "),
        "output_escaped": ascii(table_result), "checks": checks,
        "passed": all(checks.values()),
    }


def proton_locale_environment(env: dict[str, str]) -> dict[str, str]:
    """仅建模两个冻结 Proton 版本的 init_wine locale 分支；不修改调用者。"""
    result = dict(env)
    if result.get("HOST_LC_ALL", ""):
        result["LC_ALL"] = result["HOST_LC_ALL"]
    else:
        result.pop("LC_ALL", None)
    return result


def source_model_codepage(native: dict[str, Any], nls_available: bool = True) -> int | None:
    # 源码明确：setlocale 失败走 UTF-8；NLS 读取失败不改初始 UTF-8 表。
    if not native["setlocale_ok"]:
        return 65001
    normalized = re.sub(r"[^A-Za-z0-9]", "", native["libc_codeset"]).upper()
    if normalized == "UTF8":
        return 65001
    if normalized == "ANSIX341968":
        return 20127 if nls_available else 65001
    return None  # 本工具不猜测未覆盖的其他 codepage。


def native_probe(probe: Path, env: dict[str, str], stage: str) -> dict[str, Any]:
    run = subprocess.run([str(probe.resolve()), "--stage", stage], env=env, capture_output=True, timeout=10)
    if run.returncode not in (0, 20, 21):
        raise RuntimeError(f"native probe failed: {run.returncode}: {run.stderr!r}")
    result = json.loads(run.stdout.decode("ascii"))
    if result.get("exit_code") != run.returncode:
        raise ValueError("probe JSON/exit mismatch")
    result["stderr"] = run.stderr.decode("utf-8", "backslashreplace")
    return result


def matrix(probe: Path) -> dict[str, Any]:
    rows = []
    for name, locale_vars, before_code, after_code, expected_cp in MATRIX:
        # 不继承 Python 已经可能改写过的 LANG/LC_*，使测试输入明确。
        env = {"PATH": os.defpath, **locale_vars}
        before = native_probe(probe, env, "native-before")
        after = native_probe(probe, proton_locale_environment(env), "native-after-proton-policy-model")
        predicted = source_model_codepage(after)
        passed = (before["exit_code"] == before_code and after["exit_code"] == after_code and predicted == expected_cp)
        rows.append({"case": name, "input": locale_vars, "before": before, "after_policy_model": after,
                     "wine_codepage_source_prediction": predicted, "expected": [before_code, after_code, expected_cp], "passed": passed})
    return {"schema": "cf7-issue46-locale-matrix/v1", "scope": "native-libc-plus-source-policy-model",
            "wine_executed": False, "deck_executed": False, "cases": rows, "case_count": len(rows),
            "passed_count": sum(row["passed"] for row in rows), "passed": all(row["passed"] for row in rows)}


def prepare_fixture(path: Path) -> dict[str, Any]:
    path.mkdir(parents=True, exist_ok=False)  # 必须新目录，绝不覆盖真实资产。
    for name in ("ascii.bin", "加载背景.bin"):
        (path / name).write_bytes(PAYLOAD)
    result = {"schema": "cf7-issue46-file-fixture/v1", "payload_sha256": hashlib.sha256(PAYLOAD).hexdigest(),
              "bytes": len(PAYLOAD), "files": ["ascii.bin", "加载背景.bin"]}
    (path / "fixture.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--matrix-probe", type=Path)
    ap.add_argument("--prepare-fixture", type=Path)
    ap.add_argument("--output", type=Path, help="新建结果文件；已有文件拒绝覆盖")
    args = ap.parse_args()
    try:
        if args.prepare_fixture:
            result = prepare_fixture(args.prepare_fixture)
        else:
            result = {"nls_replay": replay()}
            if args.matrix_probe:
                result["locale_matrix"] = matrix(args.matrix_probe)
        text = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
        if args.output:
            with args.output.open("x", encoding="utf-8") as out:
                out.write(text)
        else:
            print(text, end="")
        return 0 if all(value.get("passed", True) for value in result.values() if isinstance(value, dict)) else 1
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
        print(f"CF7_REPLAY_ERROR: {exc}", file=sys.stderr)
        return 2

if __name__ == "__main__":
    raise SystemExit(main())
