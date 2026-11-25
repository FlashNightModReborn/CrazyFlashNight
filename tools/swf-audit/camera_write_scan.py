#!/usr/bin/env python3
"""Read-only bounded AS2/XFL camera-writer inventory. Not a full AS2 interpreter.

Comment-aware lexer, constant bracket members, file-local simple alias closure,
compound/post/pre-increment and setProperty. Reports dynamic constructs for review.
No repository mutations; --out is required and must be outside --repo.
"""
import argparse
from collections import Counter
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import zipfile
from pathlib import Path
from lxml import etree

TOOL_VERSION = "1.0.0"
SOURCE_SUFFIXES = {".as", ".xml", ".fla"}
SIZE_LIMIT = 256 * 1024 * 1024
LIMITATIONS = [
    "The full inventory includes Git-tracked files and non-ignored untracked files.",
    "Bounded lexical detection with file-local aliases, up to eight passes. "
    "No whole-program points-to, dynamic parent-chain or reachability proof.",
    "Computed members, eval, with and transform constructs can require manual review.",
    "XML is inspected for script tags. XML without script tags is not parsed.",
    "Malformed script XML is recorded. Raw CDATA fallback is only a secondary lexical check.",
    "ZIP FLA XML is scanned; binary FLA internals and compiled SWF are outside source coverage.",
]
ROOTS = {"_root", "_root.gameworld", "_root.天空盒", "_root.collisionLayer"}
PROPS = {"_x", "_y", "_xscale", "_yscale", "_rotation"}
PROPERTY_IDS = {0: "_x", 1: "_y", 2: "_xscale", 3: "_yscale", 10: "_rotation"}
SCAN_HINT = re.compile(r"_root|setProperty|with|eval|Transform")
INCREMENTS = {"++", "--"}
WRITES = {"=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>=", ">>>="} | INCREMENTS
IDENT = r"[A-Za-z_$\u0080-\uffff][\w$\u0080-\uffff]*"
IDENTIFIER = re.compile(IDENT)
TOKEN = re.compile(
    r"""//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|"""
    + IDENT + r"|\d+(?:\.\d*)?|===|!==|==|!=|[+\-*/%&|^]=|>>>?=|<<=|\+\+|--|<=|>=|&&|\|\||[^\s]"
)
LITERAL_ESCAPE = re.compile(r"""\\(?:u([0-9a-fA-F]{4})|x([0-9a-fA-F]{2})|([\\'"]))""")
CLIP_EVENT = re.compile(r"\bon(?:ClipEvent)?\s*\(")
CAMERA_CLASSES = "scripts/类定义/org/flashNight/arki/camera/"
PARAMETER_ALIASES = {
    CAMERA_CLASSES + "HorizontalScroller.as": {
        "world": "_root.gameworld", "gameWorld": "_root.gameworld", "gw": "_root.gameworld", "bgLayer": "_root.天空盒",
    },
    CAMERA_CLASSES + "ZoomController.as": {"gameWorld": "_root.gameworld", "bgLayer": "_root.天空盒"},
}


def tokens(text):
    return [(m[0], m.start(), m.end()) for m in TOKEN.finditer(text) if not m[0].startswith(("//", "/*"))]


def literal(token):
    if len(token) < 2 or token[0] not in "\"'" or token[-1] != token[0]:
        return None

    def decode(match):
        digits = match[1] or match[2]
        return chr(int(digits, 16)) if digits else match[3]

    return LITERAL_ESCAPE.sub(decode, token[1:-1])


def constant_string(ts, start):
    parts = []
    while start < len(ts):
        part = literal(ts[start][0])
        if part is None:
            break
        parts.append(part)
        start += 1
        if start == len(ts) or ts[start][0] != "+":
            return "".join(parts), start
        start += 1
    return None, start


def chain(ts, start):
    if start >= len(ts) or not IDENTIFIER.fullmatch(ts[start][0]):
        return None, start
    parts = [ts[start][0]]
    pos = start + 1
    while pos < len(ts):
        member = ts[pos][0]
        if member == "." and pos + 1 < len(ts) and IDENTIFIER.fullmatch(ts[pos + 1][0]):
            parts.append(ts[pos + 1][0])
            pos += 2
        elif member == "[":
            name, end = constant_string(ts, pos + 1)
            if name is None or end == len(ts) or ts[end][0] != "]":
                break
            parts.append(name)
            pos = end + 1
        else:
            break
    return ".".join(parts), pos


def canon(name, aliases):
    if name in ROOTS:
        return name
    if name in aliases:
        return aliases[name]
    if name and "." in name:
        prefix, _, suffix = name.rpartition(".")
        if prefix in aliases:
            target = aliases[prefix] + "." + suffix
            if target in ROOTS:
                return target
    return None


def property_name(value):
    if isinstance(value, str) and value.isascii() and value.isdecimal():
        value = int(value)
    return PROPERTY_IDS.get(value, value)


def literal_target(value):
    if value in ROOTS:
        return value
    if value == "/":
        return "_root"
    if value:
        path = "_root." + value.strip("/")
        if path in ROOTS:
            return path
    return None


def get_aliases(blocks, reviewed):
    aliases = reviewed.copy()
    for _ in range(8):
        previous = aliases.copy()
        for block in blocks:
            ts = block["tokens"]
            for i in range(len(ts)):
                if i and ts[i - 1][0] in (".", ":"):
                    continue
                lhs, pos = chain(ts, i)
                if lhs is None:
                    continue
                if pos + 1 < len(ts) and ts[pos][0] == ":":
                    _, pos = chain(ts, pos + 1)
                if pos == len(ts) or ts[pos][0] != "=":
                    continue
                rhs, end = chain(ts, pos + 1)
                if rhs is None:
                    continue
                if rhs == "_root.createEmptyMovieClip" and end + 2 < len(ts) and ts[end][0] == "(":
                    target = literal_target(literal(ts[end + 1][0]))
                    if target and target != "_root":
                        aliases[lhs] = target
                # Root publication also proves the RHS is a camera reference.
                complete = end == len(ts) or ts[end][0] in (";", ",", ")", "}")
                if complete and lhs in ROOTS and rhs not in ROOTS and end < len(ts):
                    aliases[rhs] = lhs
                if not complete and "\n" not in block["text"][ts[end - 1][2]:ts[end][1]]:
                    continue
                target = canon(rhs, aliases)
                if target and lhs not in ROOTS and lhs.rpartition(".")[2] not in PROPS:
                    aliases[lhs] = target
        if previous == aliases:
            break
    return aliases


def call_arguments(ts, start):
    depth = 0
    arguments = []
    begin = start
    for i in range(start, len(ts)):
        token = ts[i][0]
        if depth == 0 and token in (",", ")"):
            arguments.append((begin, i))
            if token == ")":
                return arguments, i
            begin = i + 1
        elif token in ("(", "[", "{"):
            depth += 1
        elif token in (")", "]", "}"):
            depth -= 1
    return [], start


def scan_blocks(path, blocks):
    reviewed = PARAMETER_ALIASES.get(path, {})
    if not reviewed and not any(SCAN_HINT.search(block["text"]) for block in blocks):
        return [], [], {}
    blocks = [dict(block, tokens=tokens(block["text"])) for block in blocks]
    aliases = get_aliases(blocks, reviewed)
    hits, unresolved = [], []
    for index, block in enumerate(blocks):
        ts, text = block["tokens"], block["text"]
        seen = set()
        root_reference = any(root in text for root in ("gameworld", "天空盒", "collisionLayer", "_root"))

        def record(start, end, target, prop, operator, evidence):
            if (start, end, prop) in seen:
                return
            seen.add((start, end, prop))
            hits.append(dict(
                sourcePath=path, line=block["line"] + text.count("\n", 0, start),
                symbolName=block.get("symbol", ""), linkageIdentifier=block.get("linkage", ""),
                frameOrClipEvent=block.get("frame", "unknown"), scriptKind=block.get("kind", "as"),
                target=target, property=prop, operator=operator, writeExpression=text[start:end].strip(),
                aliasEvidence=evidence, scriptBlock=index, sourcePresent=True, compiledPresent="unknown",
                reachability="source_only",
            ))

        def review(start, end, reason, *, context=False):
            fragment = text[max(0, start - 50):end + 150] if context else text[start:end]
            unresolved.append(dict(sourcePath=path, line=block["line"] + text.count("\n", 0, start),
                                   reason=reason, fragment=fragment))

        for i, (token, start, stop) in enumerate(ts):
            prefix = ts[i - 1][0] if i else ""
            if prefix == ".":
                continue
            name, end = chain(ts, i)
            if name:
                obj, _, prop = name.rpartition(".")
                target = canon(obj, aliases) if prop in PROPS else None
                if target:
                    operation = ts[end][0] if end < len(ts) else ""
                    evidence = "direct" if obj in ROOTS else "reviewed_parameter" if obj in reviewed else "file_alias"
                    if operation in WRITES:
                        end += 1
                        while end < len(ts) and ts[end][0] not in (";", "}"):
                            end += 1
                        record(start, ts[min(end, len(ts) - 1)][2], target, prop, operation, evidence)
                    elif prefix in INCREMENTS:
                        record(ts[i - 1][1], ts[end - 1][2], target, prop, prefix, evidence)
                elif end < len(ts) and ts[end][0] == "[" and canon(name, aliases):
                    # Computed descendants are common reads. Flag lines that also contain a write.
                    line_end = text.find("\n", ts[end][2])
                    if line_end < 0:
                        line_end = len(text)
                    for j in range(end, len(ts)):
                        op, offset, _ = ts[j]
                        if offset >= line_end or op == ";":
                            break
                        if op in WRITES:
                            review(start, line_end, "computed_camera_member")
                            break

            if token == "setProperty" and i + 1 < len(ts) and ts[i + 1][0] == "(":
                args, end = call_arguments(ts, i + 2)
                if len(args) >= 3:
                    first, first_end = args[0]
                    obj, cursor = chain(ts, first)
                    target = canon(obj, aliases) if cursor == first_end else None
                    if not target:
                        value, cursor = constant_string(ts, first)
                        if cursor == first_end:
                            target = literal_target(value)
                    if target:
                        first, stop_arg = args[1]
                        value, cursor = constant_string(ts, first)
                        if cursor != stop_arg:
                            value = ts[first][0] if stop_arg - first == 1 else None
                        prop = property_name(value)
                        if prop in PROPS:
                            record(start, ts[end][2], target, prop, "setProperty", "setProperty")
                        else:
                            review(start, ts[end][2], "dynamic_setProperty")
            if token in ("with", "eval", "Transform") and root_reference:
                review(start, stop, "dynamic_or_transform_review", context=True)
    return hits, unresolved, aliases


def blocks_xml(data, path):
    root = etree.fromstring(data, etree.XMLParser(huge_tree=True, resolve_entities=False, no_network=True))
    symbol = root.get("name", "DOMDocument")
    linkage = root.get("linkageIdentifier", "unknown")
    blocks = []
    for element in root.iter():
        if not isinstance(element.tag, str) or element.tag.rsplit("}", 1)[-1].lower() != "script":
            continue
        text = "".join(element.itertext())
        frame, kind = "unknown", "script"
        for ancestor in element.iterancestors():
            name = ancestor.tag.rsplit("}", 1)[-1]
            if name == "DOMFrame":
                frame = int(ancestor.get("index", "0")) + 1
            if name in ("DOMSymbolInstance", "DOMMovieClipInstance"):
                kind = "instance_ClipActions"
        if CLIP_EVENT.search(text):
            kind = "clip_or_button_actions"
        blocks.append(dict(make_block(text, line=element.sourceline or 1, symbol=symbol,
                                      frame=frame, kind=kind), linkage=linkage))
    return blocks


SCRIPT_TAG = re.compile(rb"<(?:[\w.-]+:)?script(?=[\s/>])", re.IGNORECASE)
CDATA_SCRIPT = re.compile(
    r"<(?:[\w.-]+:)?script\b[^>]*>\s*<!\[CDATA\[(.*?)\]\]>",
    re.IGNORECASE | re.DOTALL,
)


def make_block(text, *, line=1, symbol="", frame="as_source", kind="as"):
    return dict(text=text, line=line, symbol=symbol, frame=frame, kind=kind)


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def git_head(repo):
    return subprocess.check_output(
        ["git", "rev-parse", "--verify", "HEAD"], cwd=repo, text=True
    ).strip()


def external_output(repo, out):
    out = out.resolve()
    if out.is_relative_to(repo.resolve()):
        raise ValueError("output must be outside the repository")
    return out


def bounded_read(path):
    with path.open("rb") as stream:
        size = os.fstat(stream.fileno()).st_size
        if size > SIZE_LIMIT:
            raise ValueError("input exceeds 256 MiB")
        data = stream.read(size + 1)
        if len(data) != size:
            raise ValueError("input size changed while reading")
    return data


def xml_scripts(data, path, failures):
    utf16 = data.startswith((b"\xff\xfe", b"\xfe\xff", b"<\x00", b"\x00<"))
    if not SCRIPT_TAG.search(data.replace(b"\x00", b"") if utf16 else data):
        return None
    try:
        return blocks_xml(data, path)
    except (ValueError, etree.XMLSyntaxError) as error:
        # Keep the XML failure even if a raw CDATA block can still be inspected.
        encoding = "utf-8-sig"
        if utf16:
            encoding = "utf-16" if data.startswith((b"\xff\xfe", b"\xfe\xff")) else (
                "utf-16-le" if data.startswith(b"<\x00") else "utf-16-be"
            )
        text = data.decode(encoding, errors="replace")
        blocks = [
            make_block(m[1], line=text.count("\n", 0, m.start(1)) + 1,
                       frame="unknown", kind="malformed_xml_cdata")
            for m in CDATA_SCRIPT.finditer(text)
        ]
        failures.append(dict(sourcePath=path, error=str(error),
                             rawScriptTags=len(SCRIPT_TAG.findall(text.encode("utf-8"))),
                             rawCdataScanned=len(blocks)))
        return blocks


def source_paths(repo, paths):
    if paths is not None:
        selected = set()
        for path in paths:
            selected_path = (repo / path).resolve()
            if not selected_path.is_relative_to(repo) or selected_path.suffix.lower() not in SOURCE_SUFFIXES:
                raise ValueError(f"expected an AS, XML or FLA file inside --repo: {path}")
            selected.add(selected_path)
        yield from sorted(selected)
        return

    names = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=repo
    ).decode("utf-8").split("\0")
    for name in sorted(set(names)):
        if os.path.splitext(name)[1].lower() in SOURCE_SUFFIXES:
            yield repo / name


def archive_opener():
    # Reuse the repository's in-memory correction of Adobe's ZIP directory length.
    helper = Path(__file__).resolve().parents[1] / "heal-numbers" / "verify_assets.py"
    spec = importlib.util.spec_from_file_location("heal_asset_archive", helper)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.open_archive


def scan_sources(repo, paths=None):
    head = git_head(repo)
    stats = Counter()
    hits, review, failures, flas, unsupported, hit_files = [], [], [], [], [], []
    open_archive = None

    def inspect_blocks(path, blocks, *, archive=False):
        if blocks is None:
            return 0
        stats["fla_script_blocks" if archive else "script_blocks"] += len(blocks)
        stats["clip_action_blocks"] += sum(
            b["kind"] in ("instance_ClipActions", "clip_or_button_actions") for b in blocks
        )
        found, dynamic, aliases = scan_blocks(path, blocks)
        hits.extend(found)
        review.extend(dynamic)
        if found:
            hit_files.append(dict(sourcePath=path, aliases=aliases, hits=len(found)))
        return len(found)

    for file in source_paths(repo, paths):
        path = file.relative_to(repo).as_posix()
        suffix = file.suffix.lower()
        stats["files_" + suffix] += 1
        try:
            if suffix != ".fla":
                data = bounded_read(file)
                stats["bytes"] += len(data)
                blocks = (xml_scripts(data, path, failures) if suffix == ".xml" else
                          [make_block(data.decode("utf-8-sig"), symbol=file.stem)])
                if blocks is not None:
                    stats["inspected_files_" + suffix] += 1
                    inspect_blocks(path, blocks)
                continue

            info = dict(flaPath=path, format="non_zip", scriptXml=0, scriptBlocks=0, writes=0)
            flas.append(info)
            try:
                archive = zipfile.ZipFile(file)
            except zipfile.BadZipFile:
                with file.open("rb") as stream:
                    header = stream.read(4)
                if not header.startswith(b"PK"):
                    unsupported.append(dict(sourcePath=path, reason="unresolved_source_binary_format"))
                    continue
                info["format"] = "zip_unreadable"
                if open_archive is None:
                    open_archive = archive_opener()
                archive = open_archive(bounded_read(file))
            info["format"] = "zip"
            stats["zip_fla"] += 1
            with archive:
                for member in archive.infolist():
                    if not member.filename.lower().endswith(".xml"):
                        continue
                    stats["fla_xml_members"] += 1
                    member_path = path + "::" + member.filename
                    try:
                        if member.file_size > SIZE_LIMIT:
                            raise ValueError("XML member exceeds 256 MiB")
                        blocks = xml_scripts(archive.read(member), member_path, failures)
                        if blocks is not None:
                            info["scriptXml"] += 1
                            info["scriptBlocks"] += len(blocks)
                            info["writes"] += inspect_blocks(member_path, blocks, archive=True)
                    except (OSError, ValueError, RuntimeError, zipfile.BadZipFile) as error:
                        failures.append(dict(sourcePath=member_path, error=str(error)))
        except (OSError, ValueError, RuntimeError, zipfile.BadZipFile) as error:
            failures.append(dict(sourcePath=path, error=str(error)))

    if head != git_head(repo):
        failures.append(dict(sourcePath="HEAD", error="Git HEAD changed during source scan"))
    coverage = dict(head=head, toolVersion=TOOL_VERSION, scope="full" if paths is None else "scoped",
                    statistics=dict(stats), writeExpressions=len(hits), hitFiles=len(hit_files),
                    parseFailures=failures, dynamicReview=review, unsupportedSourceContainers=unsupported,
                    aliasesByHitFile=hit_files, limitations=LIMITATIONS)
    return hits, coverage, flas


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--paths", type=Path, nargs="+")
    args = parser.parse_args()
    repo = args.repo.resolve()
    out = external_output(repo, args.out)
    out.mkdir(parents=True, exist_ok=True)
    hits, coverage, flas = scan_sources(repo, args.paths)
    inventory = out / "source-writes.json"
    write_json(inventory, hits)
    coverage["inventorySha256"] = sha256(inventory)
    write_json(out / "source-scan-coverage.json", coverage)
    write_json(out / "fla-source-coverage.json", flas)
    summary = {k: coverage[k] for k in ("head", "toolVersion", "scope", "statistics", "writeExpressions", "hitFiles")}
    for key in ("parseFailures", "dynamicReview", "unsupportedSourceContainers"):
        summary[key] = len(coverage[key])
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()

