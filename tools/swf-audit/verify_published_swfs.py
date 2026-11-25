#!/usr/bin/env python3
"""Verify the six ScreenShake publish outputs with FFDec and raw AVM1 tags."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
from time import monotonic
import zlib
from lzma import LZMAError

from camera_write_gate import POLICY
from camera_write_scan import (
    PROPS, ROOTS, TOOL_VERSION, bounded_read, external_output, git_head,
    literal, literal_target, make_block, property_name, scan_blocks, sha256, write_json, xml_scripts,
)
from swfscan import avm1_container


ADOBE_JAVA = Path(r"C:\Program Files\Adobe\Adobe Animate 2024\jre\bin\java.exe")
FORMATS = ("as", "pcode")
PCODE_ARG = re.compile(r'"(?:\\.|[^"\\])*"|[^\s,]+')
FFDEC_ERROR = re.compile(
    r"(?im)^\s*(?:SEVERE:|ERROR:|Exception in thread )|"
    r"(?:decompilation|disassembly|export) (?:error|failed|timeout|timed out)|"
    r"decompilation (?:was )?skipped|time limit (?:reached|exceeded)"
)


def java_executable(explicit):
    if explicit:
        return shutil.which(explicit) or str(Path(explicit).resolve(strict=True))
    if os.environ.get("JAVA_HOME"):
        java = Path(os.environ["JAVA_HOME"]) / "bin" / ("java.exe" if os.name == "nt" else "java")
        if java.is_file():
            return str(java)
    java = shutil.which("java")
    if java:
        return java
    if ADOBE_JAVA.is_file():
        return str(ADOBE_JAVA)
    raise FileNotFoundError("Java is unavailable. Specify --java.")


def capture(path):
    before = path.stat()
    data = bounded_read(path)
    after = path.stat()
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise ValueError(f"input changed while being read: {path}")
    return data, dict(sha256=hashlib.sha256(data).hexdigest(), bytes=len(data),
                      mtimeNs=before.st_mtime_ns)


def unchanged(path, identity):
    return path.stat().st_mtime_ns == identity["mtimeNs"] and sha256(path) == identity["sha256"]


def freshness_errors(binary, sources, pre_cleanup_sha):
    errors = []
    if binary["sha256"] == pre_cleanup_sha:
        errors.append(dict(reason="pre_cleanup_swf_bytes"))
    for path, source in sources.items():
        if source["mtimeNs"] > binary["mtimeNs"]:
            errors.append(dict(reason="source_newer_than_swf", sourcePath=path))
    return errors


def names_hash(names):
    data = json.dumps(sorted(names), ensure_ascii=False, separators=(",", ":")).encode()
    return hashlib.sha256(data).hexdigest()


def check_linkages(container, target):
    exports = [row["name"] for row in container["exports"]]
    imports = [[row["url"], row["name"]] for row in container["imports"]]
    failures = [
        dict(reason="missing_or_duplicate_export_anchor", anchor=name)
        for name in target["anchors"] if exports.count(name) != 1
    ]
    if names_hash(exports) != target["exportNamesSha256"]:
        failures.append(dict(reason="export_name_inventory_changed"))
    if names_hash(imports) != target["importNamesSha256"]:
        failures.append(dict(reason="import_url_and_name_inventory_changed"))
    return failures


def export_scripts(java, jar, source, destination, script_format):
    destination.mkdir()
    command = [
        java, f"-Duser.home={destination}", f"-Djava.io.tmpdir={destination}",
        "-Djava.awt.headless=true", "-Xmx768m", "-jar", str(jar), "-onerror", "abort",
        "-timeout", "15", "-exportTimeout", "100", "-format", f"script:{script_format}",
        "-export", "script", str(destination / "export"), str(source),
    ]
    log = destination / "export.log"
    start = monotonic()
    result = dict(format=script_format, command=command, log=str(log))
    try:
        with log.open("wb") as output:
            proc = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT,
                                  timeout=120, check=False, cwd=destination,
                                  env=dict(os.environ, APPDATA=str(destination)))
        result["exitCode"] = proc.returncode
        if proc.returncode or FFDEC_ERROR.search(log.read_text(encoding="utf-8", errors="replace")):
            result["error"] = "FFDec reported an export failure"
    except subprocess.TimeoutExpired:
        result["error"] = "FFDec exceeded 120 seconds"
    except OSError as error:
        result["error"] = str(error)
    result["seconds"] = round(monotonic() - start, 3)
    return result


def pcode_value(value, constants, registers):
    if value.startswith('"'):
        return literal(value)
    if value.startswith("constant") and value[8:].isdigit():
        index = int(value[8:])
        return constants[index] if index < len(constants) else None
    if value.startswith("register") and value[8:].isdigit():
        return registers.get(value)
    try:
        return int(value)
    except ValueError:
        return None


def pcode_writes(script):
    """Bounded straight-line AVM1 stack check alongside per-script AS analysis."""
    stack, constants, registers, variables, hits = [], [], {}, {}, []
    binary_ops = {"Add", "Add2", "StringAdd", "Subtract", "Multiply", "Divide", "Modulo",
                  "BitAnd", "BitOr", "BitXor", "BitLShift", "BitRShift", "BitURShift"}

    def pop():
        return stack.pop() if stack else None

    def record(number, target, prop, opcode):
        if not isinstance(target, str):
            return
        if target == "_level0" or target.startswith("_level0."):
            target = "_root" + target[7:]
        if target.startswith("_root/"):
            target = target.replace("/", ".")
        if target.startswith("/"):
            target = literal_target(target)
        if target in ROOTS and prop in PROPS:
            hits.append(dict(line=number, target=target, property=prop, operator=opcode))

    for number, line in enumerate(script.splitlines(), 1):
        opcode, _, operands = line.strip().partition(" ")
        if not opcode or opcode.startswith(";"):
            continue
        if opcode == "ConstantPool":
            constants = [literal(token) for token in PCODE_ARG.findall(operands)]
        elif opcode == "Push":
            stack.extend(pcode_value(arg, constants, registers) for arg in PCODE_ARG.findall(operands))
        elif opcode == "PushDuplicate":
            stack.append(stack[-1] if stack else None)
        elif opcode == "StackSwap":
            first, second = pop(), pop()
            stack.extend((first, second))
        elif opcode == "StoreRegister":
            if stack:
                registers[operands.split()[0]] = stack[-1]
        elif opcode in ("SetVariable", "DefineLocal"):
            value, name = pop(), pop()
            if isinstance(name, str):
                variables[name] = value
                if opcode == "SetVariable":
                    target, _, prop = name.replace(":", ".").rpartition(".")
                    record(number, target, prop, opcode)
        elif opcode == "GetVariable":
            name = pop()
            stack.append(variables.get(name, name) if isinstance(name, str) else None)
        elif opcode == "GetMember":
            member, obj = pop(), pop()
            stack.append(f"{obj}.{member}" if isinstance(obj, str) and isinstance(member, str) else None)
        elif opcode in ("SetMember", "SetProperty"):
            pop()
            prop, target = pop(), pop()
            record(number, target, property_name(prop) if opcode == "SetProperty" else prop, opcode)
        elif opcode in binary_ops:
            right, left = pop(), pop()
            constant_string = opcode in ("Add2", "StringAdd") and isinstance(left, str) and isinstance(right, str)
            stack.append(left + right if constant_string else None)
        elif opcode in ("Increment", "Decrement", "ToNumber", "ToString", "Not", "TypeOf"):
            pop()
            stack.append(None)
        elif opcode == "Pop":
            pop()
        elif opcode in ("End", "Stop", "Play", "NextFrame", "PreviousFrame"):
            continue
        else:
            # Branches, function calls and unmodeled opcodes bound the symbolic stack check.
            stack.clear()
            registers.clear()
            variables.clear()
    return hits


def windows_long_path(path):
    """Keep long clip-action export paths addressable even without LongPathsEnabled."""
    if os.name != "nt":
        return path
    name = str(path.resolve())
    if name.startswith("\\\\?\\"):
        return Path(name)
    if name.startswith("\\\\"):
        return Path("\\\\?\\UNC\\" + name[2:])
    return Path("\\\\?\\" + name)


def inspect_exports(swf, directory, export_results, expected_count):
    failures, review, writes = [], [], {fmt: [] for fmt in FORMATS}
    paths_by_format = {}
    for result in export_results:
        fmt = result["format"]
        if "error" in result:
            failures.append(dict(reason="ffdec_export_failed", format=fmt, error=result["error"]))
        root = windows_long_path(directory / fmt / "export")
        files = sorted(file for file in root.rglob("*") if file.is_file()) if root.is_dir() else []
        paths = paths_by_format[fmt] = set()
        result["scriptFiles"] = len(files)
        result["scriptSha256"] = {}
        if len(files) != expected_count or not files:
            failures.append(dict(reason="ffdec_script_count_mismatch", format=fmt,
                                 expected=expected_count, observed=len(files)))
        for file in files:
            relative = file.relative_to(root)
            path = swf + "::" + relative.as_posix()
            try:
                if file.suffix.lower() != "." + fmt:
                    raise ValueError(f"unexpected FFDec output file: {relative.as_posix()}")
                data = bounded_read(file)
                result["scriptSha256"][relative.as_posix()] = hashlib.sha256(data).hexdigest()
                paths.add(relative.with_suffix("").as_posix())
                script = data.decode("utf-8-sig")
                if FFDEC_ERROR.search(script):
                    raise ValueError("error marker in FFDec script")
                if fmt == "as":
                    found, dynamic, _ = scan_blocks(path, [make_block(script, kind="compiled_as")])
                    for row in found:
                        row.update(sourcePresent="unknown", compiledPresent=True, reachability="compiled_present")
                    writes[fmt].extend(found)
                    review.extend(dynamic)
                else:
                    writes[fmt].extend(dict(row, exportPath=relative.as_posix()) for row in pcode_writes(script))
            except (OSError, ValueError) as error:
                failures.append(dict(reason="ffdec_script_unreadable", path=path, error=str(error)))
    if paths_by_format["as"] != paths_by_format["pcode"]:
        failures.append(dict(reason="as_and_pcode_script_paths_differ",
                             asOnly=sorted(paths_by_format["as"] - paths_by_format["pcode"]),
                             pcodeOnly=sorted(paths_by_format["pcode"] - paths_by_format["as"])))
    return writes, review, failures


def write_failures(source, compiled):
    failures = []
    if source:
        failures.append(dict(reason="source_global_transform_writes", count=len(source)))
    if compiled["as"] or compiled["pcode"]:
        failures.append(dict(reason="swf_global_transform_writes",
                             asHits=len(compiled["as"]), pcodeHits=len(compiled["pcode"])))
    if bool(source) != bool(compiled["as"] or compiled["pcode"]):
        failures.append(dict(reason="source_and_swf_camera_scan_disagree"))
    return failures


def verify_target(repo, swf, target, work, java, jar):
    destination = work / Path(swf).stem
    destination.mkdir()
    binary_path = repo / swf
    result = dict(swfPath=swf, sources={}, sourceWrites=[], dynamicReview=[], failures=[])
    failures = result["failures"]
    try:
        data, binary = capture(binary_path)
        result["swfIdentity"] = binary
        snapshot = destination / binary_path.name
        snapshot.write_bytes(data)
        container = avm1_container(data)
        result["container"] = container
        failures.extend(check_linkages(container, target))
    except (OSError, ValueError, IndexError, struct.error, zlib.error, LZMAError) as error:
        failures.append(dict(reason="swf_container_unreadable", error=str(error)))
        return result
    del data

    for path in target["sourceFiles"]:
        try:
            data, identity = capture(repo / path)
            result["sources"][path] = identity
            blocks = xml_scripts(data, path, failures)
            if blocks:
                found, review, _ = scan_blocks(path, blocks)
                result["sourceWrites"].extend(found)
                result["dynamicReview"].extend(review)
        except (OSError, ValueError) as error:
            failures.append(dict(reason="source_unreadable", sourcePath=path, error=str(error)))
    failures.extend(freshness_errors(binary, result["sources"], target["preCleanupSha256"]))

    result["exports"] = [export_scripts(java, jar, snapshot, destination / fmt, fmt) for fmt in FORMATS]
    writes, review, export_failures = inspect_exports(swf, destination, result["exports"], container["actionBlocks"])
    result["swfWrites"] = writes
    result["dynamicReview"].extend(review)
    failures.extend(export_failures)
    failures.extend(write_failures(result["sourceWrites"], writes))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--java")
    parser.add_argument("--workers", type=int, choices=range(1, 5), default=4)
    args = parser.parse_args()
    repo = args.repo.resolve()
    out = external_output(repo, args.out)
    out.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="publish-audit-", dir=out))
    java = java_executable(args.java)
    jar = repo / "tools/ffdec/ffdec.jar"
    jar_sha, policy_sha = sha256(jar), sha256(POLICY)
    policy = json.loads(POLICY.read_text(encoding="utf-8"))
    targets = policy["publishedSwfs"]
    source_files = {path for target in targets.values() for path in target["sourceFiles"]}
    if (len(targets) != 6 or len(source_files) != 11
            or set(policy["liveClosureFiles"]) != source_files | targets.keys()):
        raise ValueError("incorrect publish policy closure")
    head = git_head(repo)
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        jobs = [pool.submit(verify_target, repo, swf, target, work, java, jar)
                for swf, target in targets.items()]
        results = [job.result() for job in jobs]
    for result in results:
        inputs = dict(result["sources"])
        if "swfIdentity" in result:
            inputs[result["swfPath"]] = result["swfIdentity"]
        for path, identity in inputs.items():
            try:
                valid = unchanged(repo / path, identity)
            except OSError:
                valid = False
            if not valid:
                result["failures"].append(dict(reason="input_changed_during_verification", path=path))
    tool_inputs_stable = head == git_head(repo) and jar_sha == sha256(jar) and policy_sha == sha256(POLICY)
    failed = [result["swfPath"] for result in results if result["failures"]]
    report = dict(
        postPublishGatePassed=tool_inputs_stable and not failed, head=head,
        toolVersion=TOOL_VERSION, policyVersion=policy["policyVersion"], policySha256=policy_sha,
        ffdecJarSha256=jar_sha, toolInputsStable=tool_inputs_stable,
        failedSwfs=failed, swfs=results,
        limitations=[
            "Static AVM1 lexical/alias and bounded P-code checks. Dynamic review entries remain unresolved.",
            "Source identities cover the eleven frozen XML files. Timestamp and camera agreement checks "
            "do not establish complete build provenance or runtime behavior.",
        ],
    )
    receipt = work / "published-swf-receipt.json"
    write_json(receipt, report)
    print(json.dumps(dict(postPublishGatePassed=report["postPublishGatePassed"],
                          failedSwfs=failed, receipt=str(receipt)), ensure_ascii=False))
    return 0 if report["postPublishGatePassed"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
