from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
import zlib
from collections import Counter, OrderedDict, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from asset_timeline_export import FrameDedupeIndex, compressed_timeline_entries

try:
    from PIL import Image, ImageFilter
except ImportError as exc:
    raise SystemExit(
        "Pillow is required. Install it in the active Python environment before running this tool."
    ) from exc


ICON_SIZE = 256
ICON_PREFIX = "图标-"

MICRO_DIFF_MAX_CHANGED_PIXELS = 18000
MICRO_DIFF_MAX_SINGLE_CHANNEL_DELTA = 255
MICRO_DIFF_MAX_TOTAL_CHANNEL_DELTA = 450000
MICRO_DIFF_MAX_CHANGED_ALPHA_PIXELS = 1250
PROJECTION_MAX_CHANGED_PIXELS = 42000
PROJECTION_MAX_CHANGED_ALPHA_PIXELS = 30000
PROJECTION_MAX_TOTAL_CHANNEL_DELTA = 1800000

DEFAULT_TIER_KEYS = ["data_2", "data_3", "data_4", "data_ice", "data_fire"]
BARE_AMPERSAND_RE = re.compile(r"&(?!#\d+;|#x[0-9A-Fa-f]+;|[A-Za-z][A-Za-z0-9_.:-]*;)")
STOP_CALL_RE = re.compile(r"\bstop\s*\(\s*\)\s*;?")
SCRIPT_DEFINE_DIR_RE = re.compile(r"^DefineSprite_(\d+)(?:_|$)")
SCRIPT_FRAME_DIR_RE = re.compile(r"^frame_(\d+)$")
BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.S)
LINE_COMMENT_RE = re.compile(r"//.*?(?=\r?\n|$)")


@dataclass(frozen=True)
class IconTarget:
    name: str
    linkage_id: str
    scope: str
    source_hint: str


@dataclass
class AssetSource:
    swf: str
    symbol_name: str | None = None
    conflict: bool = False


@dataclass
class DiffStats:
    exact: bool = False
    micro: bool = False
    changed_pixels: int = 0
    changed_alpha_pixels: int = 0
    max_channel_delta: int = 0
    total_channel_delta: int = 0


@dataclass(frozen=True)
class Matrix:
    a: float = 1.0
    b: float = 0.0
    c: float = 0.0
    d: float = 1.0
    tx: float = 0.0
    ty: float = 0.0

    def to_json(self) -> dict[str, float]:
        return {
            "a": round(self.a, 6),
            "b": round(self.b, 6),
            "c": round(self.c, 6),
            "d": round(self.d, 6),
            "tx": round(self.tx, 6),
            "ty": round(self.ty, 6),
        }


IDENTITY = Matrix()


def multiply(left: Matrix, right: Matrix) -> Matrix:
    return Matrix(
        a=left.a * right.a + left.c * right.b,
        b=left.b * right.a + left.d * right.b,
        c=left.a * right.c + left.c * right.d,
        d=left.b * right.c + left.d * right.d,
        tx=left.a * right.tx + left.c * right.ty + left.tx,
        ty=left.b * right.tx + left.d * right.ty + left.ty,
    )


def parse_args() -> argparse.Namespace:
    project_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description=(
            "Offline-bake launcher/web icon PNGs from Flash linkage symbols via FFDec. "
            "This bypasses AS2 BitmapData sampling and XMLSocket chunk transport."
        )
    )
    parser.add_argument(
        "--scope",
        choices=["items", "skills", "all"],
        default="all",
        help="Which runtime icon set to derive. Default: all.",
    )
    parser.add_argument("--limit", type=int, default=0, help="Only bake the first N derived targets.")
    parser.add_argument(
        "--name",
        action="append",
        default=[],
        help="Bake only this naked icon name. May be repeated. Comma-separated values are also accepted.",
    )
    parser.add_argument(
        "--output-dir",
        default=str(project_root / "launcher" / "web" / "icons"),
        help="Icon output directory. Default: launcher/web/icons.",
    )
    parser.add_argument(
        "--tmp-dir",
        default=str(project_root / "tmp" / "icon-bake-offline"),
        help="Temporary FFDec export directory. Default: tmp/icon-bake-offline.",
    )
    parser.add_argument(
        "--report",
        default=str(project_root / "tmp" / "icon-bake-offline-report.json"),
        help="JSON report path. Default: tmp/icon-bake-offline-report.json.",
    )
    parser.add_argument(
        "--asset-map",
        default=str(project_root / "data" / "items" / "asset_source_map.xml"),
        help="Linkage source map XML path.",
    )
    parser.add_argument(
        "--ffdec",
        default=str(project_root / "tools" / "ffdec" / "ffdec-cli.exe"),
        help="FFDec CLI executable path.",
    )
    parser.add_argument("--zoom", type=int, default=10, help="FFDec sprite export zoom. Default: 10.")
    parser.add_argument(
        "--animation-fps",
        type=float,
        default=24.0,
        help="Frame rate metadata for exported animated icon frame sequences. Default: 24.",
    )
    parser.add_argument(
        "--export-animated-frames",
        action="store_true",
        help=(
            "When a symbol's own exported PNG frames contain more than one unique frame, write frames[]/"
            "timelineFrames[] metadata and all unique PNG frame files. Single-child nested-only MovieClip "
            "animation with an empty stripped base is exported as full-canvas child frames instead of LCM "
            "precomposition."
        ),
    )
    parser.add_argument("--dry-run", action="store_true", help="Do not write PNGs or manifest.")
    parser.add_argument(
        "--force-overwrite-existing",
        action="store_true",
        help=(
            "Allow FFDec output to overwrite existing PNGs. By default existing icons are layout-protected: "
            "large diffs are reported but the old PNG is kept, so offline bake only fills missing icons safely."
        ),
    )
    parser.add_argument(
        "--resolve-only",
        action="store_true",
        help="Only resolve XML targets against asset_source_map.xml and write the report; skip FFDec export.",
    )
    parser.add_argument(
        "--animation-structure-audit-only",
        action="store_true",
        help=(
            "Resolve symbols and audit SWF timeline structure with script/xml exports only. This skips PNG "
            "sprite export and reports first-frame stop, nested animation, and layered export candidates."
        ),
    )
    parser.add_argument(
        "--animation-candidates-only",
        action="store_true",
        help=(
            "After structure analysis, export only nested animation candidates that can be represented as "
            "single-child canvas or direct layered icon sequences. Requires --export-animated-frames."
        ),
    )
    parser.add_argument(
        "--animation-candidate-report",
        default="",
        help=(
            "Optional structure-audit report to seed --animation-candidates-only. When provided, the bake "
            "filters targets from animationStructureCandidates before exporting scripts/xml/png, so promotion "
            "runs do not rescan every resolved icon."
        ),
    )
    parser.add_argument(
        "--animation-candidate-strategy",
        choices=["all", "direct-layered", "single-child"],
        default="all",
        help=(
            "Limit --animation-candidates-only to a candidate strategy. Default: all."
        ),
    )
    parser.add_argument(
        "--animated-candidate-max-source-frames",
        type=int,
        default=0,
        help=(
            "Optional source-frame ceiling for --animation-candidates-only. Candidates whose longest "
            "animated descendant exceeds this value are skipped before PNG export. Use 0 to disable."
        ),
    )
    parser.add_argument(
        "--keep-tmp",
        action="store_true",
        help="Keep temporary FFDec exports after completion.",
    )
    parser.add_argument(
        "--purge",
        action="store_true",
        help="After a full all-scope bake, remove manifest entries/files not in the derived target set.",
    )
    parser.add_argument(
        "--conflict-policy",
        choices=["skip", "first", "last"],
        default="skip",
        help="How to handle linkage ids with multiple source SWFs. Default: skip.",
    )
    parser.add_argument(
        "--ffdec-timeout-seconds",
        type=int,
        default=120,
        help="Timeout for each FFDec subprocess. Use 0 to disable. Default: 120.",
    )
    parser.add_argument(
        "--max-animated-icon-bytes",
        type=int,
        default=0,
        help=(
            "Optional per-icon byte budget for animated outputs. Entries over the budget are "
            "reported and downgraded to a static first-frame icon. Use 0 to disable. Default: 0."
        ),
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit nonzero if any target cannot be resolved/exported.",
    )
    return parser.parse_args()


def xml_root(path: Path) -> ET.Element:
    text = path.read_text(encoding="utf-8")
    # Some shipped data descriptions contain prose like "C&T"; keep source files untouched.
    text = BARE_AMPERSAND_RE.sub("&amp;", text)
    try:
        return ET.fromstring(text)
    except ET.ParseError as exc:
        raise ET.ParseError(f"{path}: {exc}") from exc


def child_text(element: ET.Element, tag: str) -> str | None:
    child = element.find(tag)
    if child is None or child.text is None:
        return None
    text = child.text.strip()
    return text or None


def crc32_hex(text: str) -> str:
    return f"{zlib.crc32(text.encode('utf-8')) & 0xFFFFFFFF:08x}"


def normalized_names(raw_names: list[str]) -> set[str]:
    names: set[str] = set()
    for raw in raw_names:
        for part in raw.split(","):
            name = part.strip()
            if name:
                names.add(name)
    return names


def add_target(targets: OrderedDict[str, IconTarget], name: str | None, scope: str, source_hint: str) -> None:
    if not name:
        return
    # Runtime code always calls attachMovie("图标-" + iconName). Manifest keys stay naked.
    naked = name.removeprefix(ICON_PREFIX)
    if naked and naked not in targets:
        targets[naked] = IconTarget(
            name=naked,
            linkage_id=ICON_PREFIX + naked,
            scope=scope,
            source_hint=source_hint,
        )


def load_tier_keys(project_root: Path) -> list[str]:
    config_path = project_root / "data" / "equipment" / "equipment_config.xml"
    if not config_path.exists():
        return list(DEFAULT_TIER_KEYS)
    root = xml_root(config_path)
    keys: list[str] = []
    for mapping in root.findall(".//TierMapping"):
        key = (mapping.get("key") or "").strip()
        if key and key not in keys:
            keys.append(key)
    return keys or list(DEFAULT_TIER_KEYS)


def load_item_targets(project_root: Path) -> OrderedDict[str, IconTarget]:
    targets: OrderedDict[str, IconTarget] = OrderedDict()
    items_dir = project_root / "data" / "items"
    list_root = xml_root(items_dir / "list.xml")
    tier_keys = load_tier_keys(project_root)

    for node in list_root.findall("items"):
        if node.text is None:
            continue
        rel = node.text.strip()
        if not rel:
            continue
        source_path = items_dir / rel
        if not source_path.exists():
            raise FileNotFoundError(f"Missing item XML referenced by list.xml: {source_path}")
        file_root = xml_root(source_path)
        for item in file_root.findall("item"):
            item_name = child_text(item, "name") or rel
            add_target(targets, child_text(item, "icon"), "item", f"{rel}:{item_name}")
            for tier_key in tier_keys:
                tier = item.find(tier_key)
                if tier is not None:
                    add_target(
                        targets,
                        child_text(tier, "icon"),
                        "item-tier",
                        f"{rel}:{item_name}:{tier_key}",
                    )
    return targets


def load_skill_targets(project_root: Path) -> OrderedDict[str, IconTarget]:
    targets: OrderedDict[str, IconTarget] = OrderedDict()
    skills_path = project_root / "data" / "skills" / "skills.xml"
    if not skills_path.exists():
        return targets
    root = xml_root(skills_path)
    for skill in root.findall("Skill"):
        name = child_text(skill, "Name")
        add_target(targets, name, "skill", f"skills.xml:{skill.get('id', '?')}")
    return targets


def derive_targets(project_root: Path, scope: str) -> OrderedDict[str, IconTarget]:
    targets: OrderedDict[str, IconTarget] = OrderedDict()
    if scope in ("items", "all"):
        targets.update(load_item_targets(project_root))
    if scope in ("skills", "all"):
        for name, target in load_skill_targets(project_root).items():
            if name not in targets:
                targets[name] = target
    return targets


def apply_target_filters(
    targets: OrderedDict[str, IconTarget], names: set[str], limit: int
) -> OrderedDict[str, IconTarget]:
    filtered: OrderedDict[str, IconTarget] = OrderedDict()
    for name, target in targets.items():
        if names and name not in names:
            continue
        filtered[name] = target
        if limit > 0 and len(filtered) >= limit:
            break
    return filtered


def parse_asset_map(path: Path) -> tuple[dict[str, AssetSource], dict[str, list[AssetSource]]]:
    root = xml_root(path)
    assets: dict[str, AssetSource] = {}
    conflicts: dict[str, list[AssetSource]] = {}

    for node in root.findall("asset"):
        linkage_id = node.get("id")
        swf = node.get("swf")
        if linkage_id and swf:
            assets[linkage_id] = AssetSource(swf=swf, symbol_name=node.get("symbolName"))

    for node in root.findall("conflict"):
        linkage_id = node.get("id")
        if not linkage_id:
            continue
        sources: list[AssetSource] = []
        for source in node.findall("source"):
            swf = source.get("swf")
            if swf:
                sources.append(
                    AssetSource(swf=swf, symbol_name=source.get("symbolName"), conflict=True)
                )
        if sources:
            conflicts[linkage_id] = sources
    return assets, conflicts


def resolve_target_source(
    target: IconTarget,
    assets: dict[str, AssetSource],
    conflicts: dict[str, list[AssetSource]],
    conflict_policy: str,
) -> tuple[AssetSource | None, str | None]:
    if target.linkage_id in conflicts:
        sources = conflicts[target.linkage_id]
        if conflict_policy == "skip":
            return None, "conflict"
        if conflict_policy == "first":
            return sources[0], "conflict:first"
        return sources[-1], "conflict:last"

    source = assets.get(target.linkage_id)
    if source is None:
        return None, "missing_asset"
    return source, None


def run_command(
    args: list[str],
    cwd: Path,
    timeout_seconds: int | None = None,
) -> subprocess.CompletedProcess[str]:
    timeout = timeout_seconds if timeout_seconds and timeout_seconds > 0 else None
    try:
        return subprocess.run(
            args,
            cwd=str(cwd),
            text=True,
            encoding="utf-8",
            errors="replace",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout if isinstance(exc.stdout, str) else ""
        return subprocess.CompletedProcess(args, 124, output + f"\n[timeout after {timeout_seconds}s]")


def remove_tree(path: Path, *, retries: int = 3, delay_seconds: float = 0.2) -> bool:
    for attempt in range(max(1, retries)):
        if not path.exists():
            return True
        try:
            shutil.rmtree(path)
            return True
        except OSError:
            if attempt >= retries - 1:
                return False
            time.sleep(delay_seconds)
    return not path.exists()


def safe_key(value: str) -> str:
    return f"{zlib.crc32(value.encode('utf-8')) & 0xFFFFFFFF:08x}"


def load_symbol_class(
    ffdec: Path, project_root: Path, tmp_dir: Path, swf_rel: str, timeout_seconds: int | None = None
) -> tuple[dict[str, int], dict[str, Any] | None]:
    swf_path = project_root / swf_rel
    if not swf_path.exists():
        return {}, {"swf": swf_rel, "error": "missing_swf"}

    out_dir = tmp_dir / "symbols" / safe_key(swf_rel)
    if out_dir.exists():
        remove_tree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    result = run_command([str(ffdec), "-export", "symbolClass", str(out_dir), str(swf_path)], project_root, timeout_seconds)
    if result.returncode != 0:
        return {}, {
            "swf": swf_rel,
            "error": "symbolClass_failed",
            "exitCode": result.returncode,
            "outputTail": result.stdout[-2000:],
        }

    csv_path = out_dir / "symbols.csv"
    if not csv_path.exists():
        return {}, {"swf": swf_rel, "error": "symbols_csv_missing"}

    mapping: dict[str, int] = {}
    for raw in csv_path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        line = raw.strip()
        if not line or ";" not in line:
            continue
        char_id_text, linkage_id = line.split(";", 1)
        try:
            mapping[linkage_id] = int(char_id_text)
        except ValueError:
            continue
    return mapping, None


def export_sprites(
    ffdec: Path,
    project_root: Path,
    tmp_dir: Path,
    swf_rel: str,
    character_ids: list[int],
    zoom: int,
    timeout_seconds: int | None = None,
) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    if not character_ids:
        return None, None
    swf_path = project_root / swf_rel
    out_dir = raw_export_dir(tmp_dir, swf_rel)
    if out_dir.exists():
        remove_tree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    unique_ids = sorted(set(character_ids))
    select_id = ",".join(str(i) for i in unique_ids)
    result = run_command(
        [
            str(ffdec),
            "-zoom",
            str(zoom),
            "-format",
            "sprite:png",
            "-selectid",
            select_id,
            "-export",
            "sprite",
            str(out_dir),
            str(swf_path),
        ],
        project_root,
        timeout_seconds,
    )
    if result.returncode == 0:
        return None, None

    failed: list[dict[str, Any]] = []
    recovered = 0
    for character_id in unique_ids:
        retry = run_command(
            [
                str(ffdec),
                "-zoom",
                str(zoom),
                "-format",
                "sprite:png",
                "-selectid",
                str(character_id),
                "-export",
                "sprite",
                str(out_dir),
                str(swf_path),
            ],
            project_root,
            timeout_seconds,
        )
        if retry.returncode == 0:
            recovered += 1
        else:
            failed.append(
                {
                    "characterId": character_id,
                    "exitCode": retry.returncode,
                    "outputTail": retry.stdout[-1200:],
                }
            )

    fallback = {
        "swf": swf_rel,
        "batchExitCode": result.returncode,
        "requested": len(unique_ids),
        "recovered": recovered,
        "failed": len(failed),
    }
    if failed:
        fallback["failedCharacterIds"] = [item["characterId"] for item in failed]
        fallback["failedSamples"] = failed[:5]
        return {
            "swf": swf_rel,
            "error": "sprite_export_partial_failed",
            "batchExitCode": result.returncode,
            "requested": len(unique_ids),
            "recovered": recovered,
            "failed": len(failed),
            "failedCharacterIds": fallback["failedCharacterIds"],
            "outputTail": result.stdout[-2000:],
        }, fallback
    return None, fallback


def export_sprites_from_swf_path(
    ffdec: Path,
    project_root: Path,
    swf_path: Path,
    out_dir: Path,
    swf_label: str,
    character_ids: list[int],
    zoom: int,
    timeout_seconds: int | None = None,
) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    if not character_ids:
        return None, None
    if out_dir.exists():
        remove_tree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    unique_ids = sorted(set(character_ids))
    select_id = ",".join(str(i) for i in unique_ids)
    result = run_command(
        [
            str(ffdec),
            "-zoom",
            str(zoom),
            "-format",
            "sprite:png",
            "-selectid",
            select_id,
            "-export",
            "sprite",
            str(out_dir),
            str(swf_path),
        ],
        project_root,
        timeout_seconds,
    )
    if result.returncode == 0:
        return None, None

    failed: list[dict[str, Any]] = []
    recovered = 0
    for character_id in unique_ids:
        retry = run_command(
            [
                str(ffdec),
                "-zoom",
                str(zoom),
                "-format",
                "sprite:png",
                "-selectid",
                str(character_id),
                "-export",
                "sprite",
                str(out_dir),
                str(swf_path),
            ],
            project_root,
            timeout_seconds,
        )
        if retry.returncode == 0:
            recovered += 1
        else:
            failed.append(
                {
                    "characterId": character_id,
                    "exitCode": retry.returncode,
                    "outputTail": retry.stdout[-1200:],
                }
            )

    fallback = {
        "swf": swf_label,
        "batchExitCode": result.returncode,
        "requested": len(unique_ids),
        "recovered": recovered,
        "failed": len(failed),
    }
    if failed:
        fallback["failedCharacterIds"] = [item["characterId"] for item in failed]
        fallback["failedSamples"] = failed[:5]
        return {
            "swf": swf_label,
            "error": "sprite_export_partial_failed",
            "batchExitCode": result.returncode,
            "requested": len(unique_ids),
            "recovered": recovered,
            "failed": len(failed),
            "failedCharacterIds": fallback["failedCharacterIds"],
            "outputTail": result.stdout[-2000:],
        }, fallback
    return None, fallback


def raw_export_dir(tmp_dir: Path, swf_rel: str) -> Path:
    return tmp_dir / "raw" / safe_key(swf_rel)


def raw_script_export_dir(tmp_dir: Path, swf_rel: str) -> Path:
    return tmp_dir / "scripts" / safe_key(swf_rel)


def is_safe_export_dir_name(directory_name: str, character_id: int) -> bool:
    prefix = f"DefineSprite_{character_id}"
    return directory_name == prefix or directory_name.startswith(prefix + "_")


def find_exported_frame_dir(tmp_dir: Path, swf_rel: str, character_id: int) -> Path | None:
    base = raw_export_dir(tmp_dir, swf_rel)
    if not base.exists():
        return None
    for directory in base.iterdir():
        if directory.is_dir() and is_safe_export_dir_name(directory.name, character_id):
            return directory
    return None


def find_exported_frame(tmp_dir: Path, swf_rel: str, character_id: int, frame_number: int) -> Path | None:
    directory = find_exported_frame_dir(tmp_dir, swf_rel, character_id)
    if directory is None:
        return None
    candidate = directory / f"{frame_number}.png"
    return candidate if candidate.exists() else None


def find_exported_frame_paths(tmp_dir: Path, swf_rel: str, character_id: int) -> list[Path]:
    directory = find_exported_frame_dir(tmp_dir, swf_rel, character_id)
    if directory is None:
        return []
    return find_exported_frame_paths_in_dir(directory)


def find_exported_frame_dir_in_base(base: Path, character_id: int) -> Path | None:
    if not base.exists():
        return None
    for directory in base.iterdir():
        if directory.is_dir() and is_safe_export_dir_name(directory.name, character_id):
            return directory
    return None


def find_exported_frame_paths_in_dir(directory: Path | None) -> list[Path]:
    if directory is None:
        return []
    frames: list[tuple[int, Path]] = []
    for path in directory.glob("*.png"):
        try:
            frames.append((int(path.stem), path))
        except ValueError:
            continue
    frames.sort(key=lambda item: item[0])
    return [path for _index, path in frames]


def raw_xml_export_path(tmp_dir: Path, swf_rel: str) -> Path:
    return tmp_dir / "raw-xml" / safe_key(swf_rel) / "swf.xml"


def export_swf_xml(
    ffdec: Path,
    project_root: Path,
    tmp_dir: Path,
    swf_rel: str,
    timeout_seconds: int | None = None,
) -> tuple[Path | None, dict[str, Any] | None]:
    swf_path = project_root / swf_rel
    out_path = raw_xml_export_path(tmp_dir, swf_rel)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        return out_path, None
    result = run_command([str(ffdec), "-swf2xml", str(swf_path), str(out_path)], project_root, timeout_seconds)
    if result.returncode != 0 or not out_path.exists():
        error = "swf_xml_timeout" if result.returncode == 124 else "swf_xml_failed"
        return None, {
            "swf": swf_rel,
            "error": error,
            "exitCode": result.returncode,
            "outputTail": result.stdout[-2000:],
        }
    return out_path, None


def xml2swf(
    ffdec: Path,
    project_root: Path,
    xml_path: Path,
    swf_path: Path,
    swf_label: str,
    timeout_seconds: int | None = None,
) -> dict[str, Any] | None:
    swf_path.parent.mkdir(parents=True, exist_ok=True)
    if swf_path.exists():
        swf_path.unlink()
    result = run_command([str(ffdec), "-xml2swf", str(xml_path), str(swf_path)], project_root, timeout_seconds)
    if result.returncode == 0 and swf_path.exists():
        return None
    return {
        "swf": swf_label,
        "error": "xml2swf_failed",
        "exitCode": result.returncode,
        "outputTail": result.stdout[-2000:],
    }


def export_scripts(
    ffdec: Path,
    project_root: Path,
    tmp_dir: Path,
    swf_rel: str,
    timeout_seconds: int | None = None,
) -> dict[str, Any] | None:
    swf_path = project_root / swf_rel
    out_dir = raw_script_export_dir(tmp_dir, swf_rel)
    if out_dir.exists():
        remove_tree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    result = run_command(
        [
            str(ffdec),
            "-format",
            "script:as",
            "-export",
            "script",
            str(out_dir),
            str(swf_path),
        ],
        project_root,
        timeout_seconds,
    )
    if result.returncode == 0:
        return None
    return {
        "swf": swf_rel,
        "error": "script_export_failed",
        "exitCode": result.returncode,
        "outputTail": result.stdout[-2000:],
    }


def first_child_named(element: ET.Element, tag: str) -> ET.Element | None:
    for child in list(element):
        if child.tag == tag:
            return child
    return None


def parse_xml_matrix(element: ET.Element | None) -> Matrix:
    if element is None:
        return IDENTITY
    has_scale = element.get("hasScale") == "true"
    has_rotate = element.get("hasRotate") == "true"
    a = float(element.get("scaleX") or 1) if has_scale else 1.0
    d = float(element.get("scaleY") or 1) if has_scale else 1.0
    c = float(element.get("rotateSkew0") or 0) if has_rotate else 0.0
    b = float(element.get("rotateSkew1") or 0) if has_rotate else 0.0
    tx = float(element.get("translateX") or 0) / 20.0
    ty = float(element.get("translateY") or 0) / 20.0
    return Matrix(a=a, b=b, c=c, d=d, tx=tx, ty=ty)


def parse_rgba(element: ET.Element | None) -> dict[str, int] | None:
    if element is None:
        return None
    return {
        "red": int(float(element.get("red") or 0)),
        "green": int(float(element.get("green") or 0)),
        "blue": int(float(element.get("blue") or 0)),
        "alpha": int(float(element.get("alpha") or 255)),
    }


def parse_color_transform(element: ET.Element | None) -> dict[str, Any] | None:
    if element is None:
        return None
    return {
        "type": "colorTransform",
        "redMultTerm": int(float(element.get("redMultTerm") or 256)),
        "greenMultTerm": int(float(element.get("greenMultTerm") or 256)),
        "blueMultTerm": int(float(element.get("blueMultTerm") or 256)),
        "alphaMultTerm": int(float(element.get("alphaMultTerm") or 256)),
        "redAddTerm": int(float(element.get("redAddTerm") or 0)),
        "greenAddTerm": int(float(element.get("greenAddTerm") or 0)),
        "blueAddTerm": int(float(element.get("blueAddTerm") or 0)),
        "alphaAddTerm": int(float(element.get("alphaAddTerm") or 0)),
    }


def parse_filter_list(element: ET.Element) -> list[dict[str, Any]]:
    filters: list[dict[str, Any]] = []
    color_transform = parse_color_transform(first_child_named(element, "colorTransform"))
    if color_transform is not None:
        filters.append(color_transform)

    surface_filter_list = first_child_named(element, "surfaceFilterList")
    if surface_filter_list is None:
        return filters

    for item in list(surface_filter_list):
        filter_type = item.get("type") or ""
        if filter_type == "COLORMATRIXFILTER":
            matrix_element = first_child_named(item, "matrix")
            values: list[float] = []
            if matrix_element is not None:
                for value_item in list(matrix_element):
                    if value_item.text is None:
                        continue
                    values.append(float(value_item.text.strip()))
            if len(values) == 20:
                filters.append({"type": "colorMatrix", "matrix": values})
            else:
                filters.append({"type": "unsupported", "filterType": filter_type, "reason": "invalid_matrix"})
        elif filter_type == "GLOWFILTER":
            filters.append(
                {
                    "type": "glow",
                    "blurX": float(item.get("blurX") or 0),
                    "blurY": float(item.get("blurY") or 0),
                    "strength": float(item.get("strength") or 1),
                    "innerGlow": item.get("innerGlow") == "true",
                    "knockout": item.get("knockout") == "true",
                    "compositeSource": item.get("compositeSource") != "false",
                    "passes": int(float(item.get("passes") or 1)),
                    "color": parse_rgba(first_child_named(item, "glowColor")) or {
                        "red": 0,
                        "green": 0,
                        "blue": 0,
                        "alpha": 255,
                    },
                }
            )
        else:
            filters.append({"type": "unsupported", "filterType": filter_type or "<unknown>"})
    return filters


def parse_sprite_graph(xml_path: Path) -> dict[int, dict[str, Any]]:
    root = ET.parse(xml_path).getroot()
    graph: dict[int, dict[str, Any]] = {}
    for item in root.iter("item"):
        if item.get("type") != "DefineSpriteTag":
            continue
        sprite_id_text = item.get("spriteId")
        if not sprite_id_text:
            continue
        sprite_id = int(sprite_id_text)
        children: list[int] = []
        children_by_frame: dict[int, list[int]] = defaultdict(list)
        child_instances: list[dict[str, Any]] = []
        frame = 1
        sub_tags = first_child_named(item, "subTags")
        if sub_tags is None:
            continue
        for child in list(sub_tags):
            child_type = child.get("type") or ""
            child_id = child.get("characterId")
            if child_type.startswith("PlaceObject") and child_id:
                character_id = int(child_id)
                children.append(character_id)
                children_by_frame[frame].append(character_id)
                instance: dict[str, Any] = {"characterId": character_id, "frame": frame}
                depth = child.get("depth")
                if depth and depth.lstrip("-").isdigit():
                    instance["depth"] = int(depth)
                instance["matrix"] = parse_xml_matrix(first_child_named(child, "matrix"))
                filters = parse_filter_list(child)
                if filters:
                    instance["filters"] = filters
                child_instances.append(instance)
            if child_type == "ShowFrameTag":
                frame += 1
        graph[sprite_id] = {
            "frameCount": int(item.get("frameCount") or 0),
            "children": list(dict.fromkeys(children)),
            "childrenByFrame": {
                str(frame_number): list(dict.fromkeys(frame_children))
                for frame_number, frame_children in children_by_frame.items()
            },
            "childInstances": child_instances,
        }
    return graph


def script_define_id(path_part: str) -> int | None:
    match = SCRIPT_DEFINE_DIR_RE.match(path_part)
    if not match:
        return None
    return int(match.group(1))


def script_frame_number(path_part: str) -> int | None:
    match = SCRIPT_FRAME_DIR_RE.match(path_part)
    if not match:
        return None
    return int(match.group(1))


def compact_action_script(script: str) -> str:
    without_block = BLOCK_COMMENT_RE.sub("", script)
    without_line = LINE_COMMENT_RE.sub("", without_block)
    return re.sub(r"\s+", "", without_line)


def is_plain_stop_script(script: str) -> bool:
    compact = compact_action_script(script)
    return compact in ("stop();", "stop()")


def collect_timeline_scripts(tmp_dir: Path, swf_rel: str) -> dict[int, dict[str, Any]]:
    base = raw_script_export_dir(tmp_dir, swf_rel) / "scripts"
    controls: dict[int, dict[str, Any]] = defaultdict(lambda: {"frameScripts": defaultdict(list), "clipActions": []})
    if not base.exists():
        return {}
    for path in base.rglob("*.as"):
        rel_parts = path.relative_to(base).parts
        char_id: int | None = None
        frame_number: int | None = None
        for part in rel_parts:
            if char_id is None:
                char_id = script_define_id(part)
            if frame_number is None:
                frame_number = script_frame_number(part)
        if char_id is None:
            continue
        try:
            script = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        is_clip_action = any("CLIPACTIONRECORD" in part or "onClipEvent" in part for part in rel_parts)
        if is_clip_action:
            controls[char_id]["clipActions"].append({"frame": frame_number, "path": path.name})
        else:
            controls[char_id]["frameScripts"][frame_number or 0].append(script)
    return controls


def has_plain_frame1_stop(controls: dict[int, dict[str, Any]], character_id: int) -> bool:
    control = controls.get(character_id) or {}
    frame_scripts = control.get("frameScripts") or {}
    return any(is_plain_stop_script(script) for script in (frame_scripts.get(1) or []))


def animated_descendants(
    graph: dict[int, dict[str, Any]],
    controls: dict[int, dict[str, Any]],
    character_id: int,
    *,
    max_depth: int = 8,
) -> tuple[list[dict[str, Any]], int]:
    descendants: list[dict[str, Any]] = []
    stopped_descendants = 0
    visited: set[tuple[int, bool]] = set()

    def child_ids_for(info: dict[str, Any], frame1_only: bool) -> list[int]:
        if frame1_only:
            return list((info.get("childrenByFrame") or {}).get("1") or [])
        return list(info.get("children") or [])

    def visit(sprite_id: int, depth: int, path: list[int], frame1_only: bool) -> None:
        nonlocal stopped_descendants
        visit_key = (sprite_id, frame1_only)
        if depth > max_depth or visit_key in visited:
            return
        visited.add(visit_key)
        info = graph.get(sprite_id)
        if not info:
            return
        for child_id in child_ids_for(info, frame1_only):
            child = graph.get(child_id)
            if not child:
                continue
            child_frames = int(child.get("frameCount") or 0)
            child_path = path + [child_id]
            child_stopped = has_plain_frame1_stop(controls, child_id)
            if child_frames > 1:
                if child_stopped:
                    stopped_descendants += 1
                else:
                    descendants.append(
                        {
                            "characterId": child_id,
                            "frameCount": child_frames,
                            "depth": depth + 1,
                            "path": child_path,
                        }
                    )
            visit(child_id, depth + 1, child_path, child_stopped)

    visit(character_id, 0, [character_id], has_plain_frame1_stop(controls, character_id))
    descendants.sort(key=lambda item: (item["depth"], -item["frameCount"], item["characterId"]))
    return descendants, stopped_descendants


def nested_animation_audit(
    graph: dict[int, dict[str, Any]],
    controls: dict[int, dict[str, Any]],
    character_id: int,
    *,
    max_depth: int = 8,
) -> dict[str, Any]:
    descendants, stopped_descendants = animated_descendants(
        graph,
        controls,
        character_id,
        max_depth=max_depth,
    )
    max_frame_count = max((item["frameCount"] for item in descendants), default=0)
    return {
        "nestedAnimatedDescendantCount": len(descendants),
        "nestedStoppedDescendantCount": stopped_descendants,
        "maxNestedDescendantFrameCount": max_frame_count,
        "sampleNestedDescendants": descendants[:5],
    }


def first_frame_instance(
    graph: dict[int, dict[str, Any]],
    parent_id: int,
    child_id: int,
) -> dict[str, Any] | None:
    info = graph.get(parent_id) or {}
    for instance in info.get("childInstances") or []:
        if instance.get("frame") == 1 and instance.get("characterId") == child_id:
            return instance
    return None


def accumulated_frame1_matrix(
    graph: dict[int, dict[str, Any]],
    path: list[int],
) -> Matrix | None:
    matrix = IDENTITY
    for index in range(len(path) - 1):
        instance = first_frame_instance(graph, path[index], path[index + 1])
        if not instance:
            return None
        matrix = multiply(matrix, instance.get("matrix") or IDENTITY)
    return matrix


def accumulated_frame1_filters(
    graph: dict[int, dict[str, Any]],
    path: list[int],
) -> list[dict[str, Any]]:
    filters: list[dict[str, Any]] = []
    for index in range(len(path) - 1):
        instance = first_frame_instance(graph, path[index], path[index + 1])
        if not instance:
            continue
        filters.extend(list(instance.get("filters") or []))
    return filters


def remove_direct_layer_children(
    xml_path: Path,
    out_xml_path: Path,
    removals: set[tuple[int, int]],
) -> int:
    tree = ET.parse(xml_path)
    root = tree.getroot()
    removed = 0
    for item in root.iter("item"):
        if item.get("type") != "DefineSpriteTag":
            continue
        sprite_id_text = item.get("spriteId")
        if not sprite_id_text:
            continue
        parent_id = int(sprite_id_text)
        sub_tags = first_child_named(item, "subTags")
        if sub_tags is None:
            continue
        frame = 1
        for child in list(sub_tags):
            child_type = child.get("type") or ""
            child_id = child.get("characterId")
            if (
                frame == 1
                and child_type.startswith("PlaceObject")
                and child_id
                and (parent_id, int(child_id)) in removals
            ):
                sub_tags.remove(child)
                removed += 1
                continue
            if child_type == "ShowFrameTag":
                frame += 1
    out_xml_path.parent.mkdir(parents=True, exist_ok=True)
    tree.write(out_xml_path, encoding="utf-8", xml_declaration=True)
    return removed


def single_nested_icon_canvas_plan(
    graph: dict[int, dict[str, Any]],
    controls: dict[int, dict[str, Any]],
    character_id: int,
) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    descendants, _stopped_descendants = animated_descendants(graph, controls, character_id)
    if not descendants:
        return None, None
    if len(descendants) != 1:
        return None, {
            "reason": "multiple_animated_descendants",
            "descendantCount": len(descendants),
            "sample": descendants[:5],
        }

    descendant = descendants[0]
    path = [int(part) for part in descendant.get("path") or []]
    if len(path) < 2:
        return None, {"reason": "invalid_descendant_path", "path": path}

    matrix = accumulated_frame1_matrix(graph, path)
    if matrix is None:
        return None, {"reason": "missing_frame1_matrix", "path": path}
    if matrix.b != 0 or matrix.c != 0 or matrix.a <= 0 or matrix.d <= 0:
        return None, {
            "reason": "unsupported_matrix",
            "path": path,
            "matrix": matrix.to_json(),
        }
    filters = accumulated_frame1_filters(graph, path)
    filters_supported, filter_error = supported_icon_filters(filters)
    if not filters_supported:
        return None, filter_error

    child_id = path[-1]
    source_parent_id = path[-2]
    return {
        "characterId": child_id,
        "sourceParentId": source_parent_id,
        "sourceFrameCount": int(descendant.get("frameCount") or 1),
        "path": path,
        "matrix": matrix,
        "filters": filters,
    }, None


def matrix_is_icon_canvas_supported(matrix: Matrix) -> bool:
    return matrix.a > 0 and matrix.d > 0 and matrix.b == 0 and matrix.c == 0


def direct_layered_icon_canvas_plan(
    graph: dict[int, dict[str, Any]],
    controls: dict[int, dict[str, Any]],
    character_id: int,
) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    descendants, _stopped_descendants = animated_descendants(graph, controls, character_id)
    if not descendants:
        return None, None
    direct_descendants: list[dict[str, Any]] = []
    for descendant in descendants:
        path = [int(part) for part in descendant.get("path") or []]
        if len(path) != 2 or path[0] != character_id:
            return None, {
                "reason": "non_direct_animated_descendant",
                "path": path,
                "sample": descendants[:5],
            }
        direct_descendants.append(descendant)

    layer_ids = {int(descendant["characterId"]) for descendant in direct_descendants}
    parent_info = graph.get(character_id) or {}
    base_depths = [
        int(instance["depth"])
        for instance in (parent_info.get("childInstances") or [])
        if instance.get("frame") == 1
        and int(instance.get("characterId") or 0) not in layer_ids
        and "depth" in instance
    ]
    max_base_depth = max(base_depths, default=None)
    layers: list[dict[str, Any]] = []
    for descendant in direct_descendants:
        child_id = int(descendant["characterId"])
        instance = first_frame_instance(graph, character_id, child_id)
        if instance is None:
            return None, {"reason": "missing_direct_instance", "characterId": child_id}
        depth = instance.get("depth")
        if depth is None:
            return None, {"reason": "missing_layer_depth", "characterId": child_id}
        matrix = instance.get("matrix") or IDENTITY
        if not matrix_is_icon_canvas_supported(matrix):
            return None, {
                "reason": "unsupported_matrix",
                "characterId": child_id,
                "matrix": matrix.to_json(),
            }
        filters = list(instance.get("filters") or [])
        filters_supported, filter_error = supported_icon_filters(filters)
        if not filters_supported:
            payload = {"characterId": child_id}
            payload.update(filter_error or {"reason": "unsupported_filter"})
            return None, payload
        if max_base_depth is not None and int(depth) <= max_base_depth:
            return None, {
                "reason": "layer_interleaves_static_base",
                "characterId": child_id,
                "layerDepth": int(depth),
                "maxBaseDepth": max_base_depth,
            }
        layers.append(
            {
                "characterId": child_id,
                "sourceParentId": character_id,
                "sourceFrameCount": int(descendant.get("frameCount") or 1),
                "path": [character_id, child_id],
                "matrix": matrix,
                "filters": filters,
                "depth": int(depth),
            }
        )

    layers.sort(key=lambda layer: int(layer.get("depth") or 0))
    return {
        "layers": layers,
        "removals": {(character_id, int(layer["characterId"])) for layer in layers},
        "baseDepthCount": len(base_depths),
    }, None


def matrix_payload(matrix: Any) -> dict[str, float] | None:
    return matrix.to_json() if isinstance(matrix, Matrix) else None


def nested_plan_payload(plan: dict[str, Any]) -> dict[str, Any]:
    payload = {
        "characterId": int(plan.get("characterId") or 0),
        "sourceParentId": int(plan.get("sourceParentId") or 0),
        "sourceFrameCount": int(plan.get("sourceFrameCount") or 0),
        "path": plan.get("path") or [],
    }
    matrix = matrix_payload(plan.get("matrix"))
    if matrix is not None:
        payload["matrix"] = matrix
    filters = plan.get("filters") or []
    if filters:
        payload["filters"] = filters
    return payload


def layered_plan_payload(plan: dict[str, Any]) -> dict[str, Any]:
    layers = []
    for layer in plan.get("layers") or []:
        payload = nested_plan_payload(layer)
        if "depth" in layer:
            payload["depth"] = int(layer.get("depth") or 0)
        layers.append(payload)
    return {
        "strategy": "direct-layered-icon-canvas",
        "layerCount": len(layers),
        "baseDepthCount": int(plan.get("baseDepthCount") or 0),
        "layers": layers[:8],
    }


def default_nested_audit() -> dict[str, Any]:
    return {
        "nestedAnimatedDescendantCount": 0,
        "nestedStoppedDescendantCount": 0,
        "maxNestedDescendantFrameCount": 0,
        "sampleNestedDescendants": [],
    }


def icon_animation_structure_payload(
    target: IconTarget,
    swf_rel: str,
    character_id: int,
    graph: dict[int, dict[str, Any]],
    controls: dict[int, dict[str, Any]],
) -> dict[str, Any]:
    parent_info = graph.get(character_id) if graph else None
    parent_frame_count = int((parent_info or {}).get("frameCount") or 0)
    parent_plain_stop = has_plain_frame1_stop(controls, character_id)
    nested_audit = nested_animation_audit(graph, controls, character_id) if parent_info else default_nested_audit()
    payload: dict[str, Any] = {
        "name": target.name,
        "linkageId": target.linkage_id,
        "scope": target.scope,
        "swf": swf_rel,
        "characterId": character_id,
        "parentFrameCount": parent_frame_count,
        "parentPlainFrame1Stop": bool(parent_plain_stop),
        **nested_audit,
    }
    if not parent_info:
        payload["classification"] = "sprite-graph-missing"
        return payload

    if nested_audit["nestedAnimatedDescendantCount"] > 0:
        layered_plan, layered_error = direct_layered_icon_canvas_plan(graph, controls, character_id)
        single_plan, single_error = single_nested_icon_canvas_plan(graph, controls, character_id)
        layered_candidate = layered_plan is not None and (
            len(layered_plan.get("layers") or []) > 1
            or int(layered_plan.get("baseDepthCount") or 0) > 0
        )
        if parent_plain_stop:
            payload["parentPlayback"] = "static-first-frame"
        if layered_candidate:
            payload["classification"] = "direct-layered-candidate"
            payload["exportPlan"] = layered_plan_payload(layered_plan)
        elif single_plan is not None:
            payload["classification"] = "single-child-canvas-candidate"
            payload["exportPlan"] = {
                "strategy": "single-child-icon-canvas",
                **nested_plan_payload(single_plan),
            }
        else:
            error = layered_error or single_error or {"reason": "no_nested_icon_canvas_plan"}
            payload["classification"] = "nested-animation-unsupported"
            payload["unsupportedReason"] = error
        return payload

    if parent_frame_count > 1:
        if parent_plain_stop:
            payload["classification"] = "plain-stop-static"
            payload["staticReason"] = "frame1_plain_stop"
            payload["collapsedFrameCount"] = max(0, parent_frame_count - 1)
        else:
            payload["classification"] = "parent-timeline-needs-png-audit"
    else:
        payload["classification"] = "static"
    return payload


def animation_candidate_filter_decision(
    payload: dict[str, Any],
    *,
    strategy: str,
    max_source_frames: int,
) -> tuple[bool, str]:
    classification = str(payload.get("classification") or "unknown")
    if classification not in ("direct-layered-candidate", "single-child-canvas-candidate"):
        return False, classification
    if strategy == "direct-layered" and classification != "direct-layered-candidate":
        return False, "strategy_not_direct_layered"
    if strategy == "single-child" and classification != "single-child-canvas-candidate":
        return False, "strategy_not_single_child"
    max_frames = int(payload.get("maxNestedDescendantFrameCount") or 0)
    if max_source_frames > 0 and max_frames > max_source_frames:
        return False, "source_frame_budget"
    return True, "selected"


def collect_animation_structure_payloads(
    by_swf: dict[str, list[tuple[IconTarget, AssetSource]]],
    char_ids_by_swf: dict[str, dict[str, int]],
    sprite_graphs: dict[str, dict[int, dict[str, Any]]],
    timeline_controls_by_swf: dict[str, dict[int, dict[str, Any]]],
) -> dict[tuple[str, str], dict[str, Any]]:
    payloads: dict[tuple[str, str], dict[str, Any]] = {}
    for swf_rel, entries in by_swf.items():
        char_ids = char_ids_by_swf.get(swf_rel, {})
        sprite_graph = sprite_graphs.get(swf_rel) or {}
        timeline_controls = timeline_controls_by_swf.get(swf_rel) or {}
        for target, _source in entries:
            char_id = char_ids.get(target.name)
            if char_id is None:
                continue
            payloads[(swf_rel, target.name)] = icon_animation_structure_payload(
                target,
                swf_rel,
                char_id,
                sprite_graph,
                timeline_controls,
            )
    return payloads


def load_animation_candidate_report_targets(
    path: Path,
    *,
    strategy: str,
    max_source_frames: int,
) -> tuple[set[str], dict[str, Any]]:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    names: set[str] = set()
    counts: Counter[str] = Counter()
    selected: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    for payload in data.get("animationStructureCandidates") or []:
        name = str(payload.get("name") or "")
        if not name:
            counts["missing_name"] += 1
            continue
        keep, reason = animation_candidate_filter_decision(
            payload,
            strategy=strategy,
            max_source_frames=max_source_frames,
        )
        counts["checked"] += 1
        if keep:
            names.add(name)
            counts["selected"] += 1
            selected.append(
                {
                    "name": name,
                    "linkageId": payload.get("linkageId"),
                    "swf": payload.get("swf"),
                    "classification": payload.get("classification"),
                    "maxNestedDescendantFrameCount": payload.get("maxNestedDescendantFrameCount"),
                    "parentPlainFrame1Stop": payload.get("parentPlainFrame1Stop"),
                }
            )
        else:
            counts["skipped"] += 1
            counts["skipped_" + reason] += 1
            skipped.append(
                {
                    "name": name,
                    "linkageId": payload.get("linkageId"),
                    "swf": payload.get("swf"),
                    "classification": payload.get("classification"),
                    "maxNestedDescendantFrameCount": payload.get("maxNestedDescendantFrameCount"),
                    "reason": reason,
                }
            )
    return names, {
        "path": str(path),
        "counts": dict(counts),
        "selected": selected[:200],
        "skipped": skipped[:200],
    }


def normalize_icon_image(img: Image.Image, profile_size: tuple[int, int] | None = None) -> Image.Image:
    width, height = img.size
    if width <= 0 or height <= 0:
        return Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))

    basis_w, basis_h = profile_size if profile_size is not None else (width, height)
    if basis_w <= 0 or basis_h <= 0:
        basis_w, basis_h = width, height
    scale = ICON_SIZE / float(max(basis_w, basis_h))
    target_w = max(1, int(round(width * scale)))
    target_h = max(1, int(round(height * scale)))
    resized = img.resize((target_w, target_h), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    offset_x = int(round((ICON_SIZE - target_w) / 2.0))
    offset_y = int(round((ICON_SIZE - target_h) / 2.0))
    src_left = max(0, -offset_x)
    src_top = max(0, -offset_y)
    dst_left = max(0, offset_x)
    dst_top = max(0, offset_y)
    paste_w = min(target_w - src_left, ICON_SIZE - dst_left)
    paste_h = min(target_h - src_top, ICON_SIZE - dst_top)
    if paste_w > 0 and paste_h > 0:
        crop = resized.crop((src_left, src_top, src_left + paste_w, src_top + paste_h))
        canvas.alpha_composite(crop, (dst_left, dst_top))
    return canvas


def normalize_icon(source_png: Path, profile_size: tuple[int, int] | None = None) -> Image.Image:
    with Image.open(source_png) as raw:
        return normalize_icon_image(raw.convert("RGBA"), profile_size)


def paste_clipped(canvas: Image.Image, image: Image.Image, left: int, top: int) -> None:
    src_left = max(0, -left)
    src_top = max(0, -top)
    dst_left = max(0, left)
    dst_top = max(0, top)
    paste_w = min(image.width - src_left, canvas.width - dst_left)
    paste_h = min(image.height - src_top, canvas.height - dst_top)
    if paste_w <= 0 or paste_h <= 0:
        return
    crop = image.crop((src_left, src_top, src_left + paste_w, src_top + paste_h))
    canvas.alpha_composite(crop, (dst_left, dst_top))


def clamp_u8(value: float) -> int:
    if value <= 0:
        return 0
    if value >= 255:
        return 255
    return int(round(value))


def apply_color_transform_filter(image: Image.Image, filter_def: dict[str, Any]) -> Image.Image:
    source = image.convert("RGBA")
    data = source.tobytes()
    out = bytearray(len(data))
    red_mult = float(filter_def.get("redMultTerm", 256)) / 256.0
    green_mult = float(filter_def.get("greenMultTerm", 256)) / 256.0
    blue_mult = float(filter_def.get("blueMultTerm", 256)) / 256.0
    alpha_mult = float(filter_def.get("alphaMultTerm", 256)) / 256.0
    red_add = float(filter_def.get("redAddTerm", 0))
    green_add = float(filter_def.get("greenAddTerm", 0))
    blue_add = float(filter_def.get("blueAddTerm", 0))
    alpha_add = float(filter_def.get("alphaAddTerm", 0))
    for index in range(0, len(data), 4):
        red = data[index]
        green = data[index + 1]
        blue = data[index + 2]
        alpha = data[index + 3]
        out[index] = clamp_u8(red * red_mult + red_add)
        out[index + 1] = clamp_u8(green * green_mult + green_add)
        out[index + 2] = clamp_u8(blue * blue_mult + blue_add)
        out[index + 3] = clamp_u8(alpha * alpha_mult + alpha_add)
    return Image.frombytes("RGBA", source.size, bytes(out))


def apply_color_matrix_filter(image: Image.Image, filter_def: dict[str, Any]) -> Image.Image:
    matrix = list(filter_def.get("matrix") or [])
    if len(matrix) != 20:
        return image.convert("RGBA")
    source = image.convert("RGBA")
    data = source.tobytes()
    out = bytearray(len(data))
    for index in range(0, len(data), 4):
        red = data[index]
        green = data[index + 1]
        blue = data[index + 2]
        alpha = data[index + 3]
        out[index] = clamp_u8(
            red * matrix[0] + green * matrix[1] + blue * matrix[2] + alpha * matrix[3] + matrix[4]
        )
        out[index + 1] = clamp_u8(
            red * matrix[5] + green * matrix[6] + blue * matrix[7] + alpha * matrix[8] + matrix[9]
        )
        out[index + 2] = clamp_u8(
            red * matrix[10] + green * matrix[11] + blue * matrix[12] + alpha * matrix[13] + matrix[14]
        )
        out[index + 3] = clamp_u8(
            red * matrix[15] + green * matrix[16] + blue * matrix[17] + alpha * matrix[18] + matrix[19]
        )
    return Image.frombytes("RGBA", source.size, bytes(out))


def apply_glow_filter(image: Image.Image, filter_def: dict[str, Any]) -> Image.Image:
    source = image.convert("RGBA")
    if filter_def.get("innerGlow") or filter_def.get("knockout"):
        return source
    color = filter_def.get("color") or {}
    blur_x = float(filter_def.get("blurX") or 0)
    blur_y = float(filter_def.get("blurY") or 0)
    radius = max(0.0, (blur_x + blur_y) / 4.0)
    alpha = source.getchannel("A")
    if radius > 0:
        alpha = alpha.filter(ImageFilter.GaussianBlur(radius=radius))
    strength = max(0.0, float(filter_def.get("strength") or 1.0))
    color_alpha = clamp_u8(float(color.get("alpha", 255)) * strength)
    glow = Image.new(
        "RGBA",
        source.size,
        (
            clamp_u8(float(color.get("red", 0))),
            clamp_u8(float(color.get("green", 0))),
            clamp_u8(float(color.get("blue", 0))),
            color_alpha,
        ),
    )
    glow.putalpha(alpha.point(lambda value: clamp_u8(value * strength)))
    out = Image.new("RGBA", source.size, (0, 0, 0, 0))
    out.alpha_composite(glow)
    if filter_def.get("compositeSource", True):
        out.alpha_composite(source)
    return out


def supported_icon_filters(filters: list[dict[str, Any]]) -> tuple[bool, dict[str, Any] | None]:
    for filter_def in filters:
        filter_type = filter_def.get("type")
        if filter_type in ("colorTransform", "colorMatrix"):
            continue
        if filter_type == "glow" and not filter_def.get("innerGlow") and not filter_def.get("knockout"):
            continue
        return False, {
            "reason": "unsupported_filter",
            "filterType": filter_def.get("filterType") or filter_type or "<unknown>",
        }
    return True, None


def apply_icon_filters(image: Image.Image, filters: list[dict[str, Any]] | None) -> Image.Image:
    out = image.convert("RGBA")
    for filter_def in filters or []:
        filter_type = filter_def.get("type")
        if filter_type == "colorTransform":
            out = apply_color_transform_filter(out, filter_def)
        elif filter_type == "glow":
            out = apply_glow_filter(out, filter_def)
        elif filter_type == "colorMatrix":
            out = apply_color_matrix_filter(out, filter_def)
    return out


def nested_layer_frame_icon(
    source_png: Path,
    parent_profile_size: tuple[int, int],
    matrix: Matrix,
    filters: list[dict[str, Any]] | None = None,
    offset: tuple[int, int] = (0, 0),
) -> Image.Image:
    with Image.open(source_png) as raw:
        layer = apply_icon_filters(raw.convert("RGBA"), filters)
    target_w = max(1, int(round(layer.width * matrix.a)))
    target_h = max(1, int(round(layer.height * matrix.d)))
    layer = layer.resize((target_w, target_h), Image.Resampling.LANCZOS)

    parent_canvas = Image.new("RGBA", parent_profile_size, (0, 0, 0, 0))
    # FFDec exports sprite PNGs cropped to transformed bounds; for an empty stripped base,
    # the child layer's transformed bbox defines the parent sprite bbox, so its local origin is (0, 0).
    paste_clipped(parent_canvas, layer, int(offset[0]), int(offset[1]))
    return normalize_icon_image(parent_canvas, parent_profile_size)


def projection_score(stats: DiffStats) -> tuple[int, int, int, int]:
    return (
        stats.total_channel_delta,
        stats.changed_pixels,
        stats.changed_alpha_pixels,
        stats.max_channel_delta,
    )


def calibrate_layer_projection_offset(
    *,
    parent_reference: Image.Image,
    base_image: Image.Image,
    source_frame: Path,
    parent_profile_size: tuple[int, int],
    matrix: Matrix,
    filters: list[dict[str, Any]],
    search_radius: int = 6,
) -> tuple[tuple[int, int], Image.Image, DiffStats, bool]:
    best_offset = (0, 0)
    best_image = nested_layer_frame_icon(source_frame, parent_profile_size, matrix, filters, best_offset)
    best_composite = composite_icon_layers(base_image, [best_image])
    best_close, best_stats = full_image_diff_images(parent_reference, best_composite)
    best_score = projection_score(best_stats)

    for y_offset in range(-search_radius, search_radius + 1):
        for x_offset in range(-search_radius, search_radius + 1):
            if x_offset == 0 and y_offset == 0:
                continue
            layer_image = nested_layer_frame_icon(
                source_frame,
                parent_profile_size,
                matrix,
                filters,
                (x_offset, y_offset),
            )
            composite = composite_icon_layers(base_image, [layer_image])
            close, stats = full_image_diff_images(parent_reference, composite)
            score = projection_score(stats)
            if close or score < best_score:
                best_offset = (x_offset, y_offset)
                best_image = layer_image
                best_stats = stats
                best_close = close
                best_score = score
                if close and icon_canvas_projection_close(stats, close):
                    return best_offset, best_image, best_stats, best_close

    return best_offset, best_image, best_stats, best_close


def image_diff_images(reference: Image.Image, candidate: Image.Image) -> tuple[bool, DiffStats]:
    stats = DiffStats()
    existing = reference.convert("RGBA")
    new_image = candidate.convert("RGBA")
    if existing.size != (ICON_SIZE, ICON_SIZE) or new_image.size != (ICON_SIZE, ICON_SIZE):
        return False, stats

    existing_bytes = existing.tobytes()
    new_bytes = new_image.tobytes()
    if existing_bytes == new_bytes:
        stats.exact = True
        return True, stats

    for i in range(0, len(existing_bytes), 4):
        r_delta = abs(existing_bytes[i] - new_bytes[i])
        g_delta = abs(existing_bytes[i + 1] - new_bytes[i + 1])
        b_delta = abs(existing_bytes[i + 2] - new_bytes[i + 2])
        a_delta = abs(existing_bytes[i + 3] - new_bytes[i + 3])
        if r_delta == 0 and g_delta == 0 and b_delta == 0 and a_delta == 0:
            continue

        stats.changed_pixels += 1
        if a_delta != 0:
            stats.changed_alpha_pixels += 1
        max_delta = max(r_delta, g_delta, b_delta, a_delta)
        stats.max_channel_delta = max(stats.max_channel_delta, max_delta)
        stats.total_channel_delta += r_delta + g_delta + b_delta + a_delta

        if (
            stats.changed_pixels > MICRO_DIFF_MAX_CHANGED_PIXELS
            or stats.max_channel_delta > MICRO_DIFF_MAX_SINGLE_CHANNEL_DELTA
            or stats.total_channel_delta > MICRO_DIFF_MAX_TOTAL_CHANNEL_DELTA
            or stats.changed_alpha_pixels > MICRO_DIFF_MAX_CHANGED_ALPHA_PIXELS
        ):
            return False, stats

    stats.micro = stats.changed_pixels > 0
    return True, stats


def full_image_diff_images(reference: Image.Image, candidate: Image.Image) -> tuple[bool, DiffStats]:
    stats = DiffStats()
    existing = reference.convert("RGBA")
    new_image = candidate.convert("RGBA")
    if existing.size != (ICON_SIZE, ICON_SIZE) or new_image.size != (ICON_SIZE, ICON_SIZE):
        return False, stats

    existing_bytes = existing.tobytes()
    new_bytes = new_image.tobytes()
    if existing_bytes == new_bytes:
        stats.exact = True
        return True, stats

    for index in range(0, len(existing_bytes), 4):
        red_delta = abs(existing_bytes[index] - new_bytes[index])
        green_delta = abs(existing_bytes[index + 1] - new_bytes[index + 1])
        blue_delta = abs(existing_bytes[index + 2] - new_bytes[index + 2])
        alpha_delta = abs(existing_bytes[index + 3] - new_bytes[index + 3])
        if red_delta == 0 and green_delta == 0 and blue_delta == 0 and alpha_delta == 0:
            continue
        stats.changed_pixels += 1
        if alpha_delta != 0:
            stats.changed_alpha_pixels += 1
        max_delta = max(red_delta, green_delta, blue_delta, alpha_delta)
        stats.max_channel_delta = max(stats.max_channel_delta, max_delta)
        stats.total_channel_delta += red_delta + green_delta + blue_delta + alpha_delta

    stats.micro = stats.changed_pixels > 0
    return False, stats


def image_diff(existing_path: Path, new_image: Image.Image) -> tuple[bool, DiffStats]:
    if not existing_path.exists():
        return False, DiffStats()

    try:
        with Image.open(existing_path) as raw_existing:
            return image_diff_images(raw_existing.convert("RGBA"), new_image)
    except Exception:
        return False, DiffStats()


def icon_canvas_projection_close(stats: DiffStats, close: bool) -> bool:
    return close or (
        stats.changed_pixels <= PROJECTION_MAX_CHANGED_PIXELS
        and stats.changed_alpha_pixels <= PROJECTION_MAX_CHANGED_ALPHA_PIXELS
        and stats.total_channel_delta <= PROJECTION_MAX_TOTAL_CHANNEL_DELTA
        and stats.max_channel_delta <= MICRO_DIFF_MAX_SINGLE_CHANNEL_DELTA
    )


def composite_icon_layers(base: Image.Image, layers: list[Image.Image]) -> Image.Image:
    canvas = base.convert("RGBA").copy()
    for layer in layers:
        canvas.alpha_composite(layer.convert("RGBA"))
    return canvas


def crop_icon_canvas(image: Image.Image) -> tuple[Image.Image, dict[str, int]]:
    source = image.convert("RGBA")
    bbox = source.getbbox()
    if bbox is None:
        crop = Image.new("RGBA", (1, 1), (0, 0, 0, 0))
        return crop, {
            "cropX": 0,
            "cropY": 0,
            "cropWidth": 1,
            "cropHeight": 1,
            "canvasWidth": source.width,
            "canvasHeight": source.height,
        }
    left, top, right, bottom = bbox
    crop = source.crop(bbox)
    return crop, {
        "cropX": int(left),
        "cropY": int(top),
        "cropWidth": int(right - left),
        "cropHeight": int(bottom - top),
        "canvasWidth": source.width,
        "canvasHeight": source.height,
    }


def load_manifest(path: Path) -> OrderedDict[str, dict[str, Any]]:
    if not path.exists():
        return OrderedDict()
    raw = json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=OrderedDict)
    manifest: OrderedDict[str, dict[str, Any]] = OrderedDict()
    for key, value in raw.items():
        if isinstance(value, str):
            manifest[key] = {"f1": value}
        elif isinstance(value, dict):
            manifest[key] = OrderedDict((str(k), v) for k, v in value.items())
    return manifest


def save_manifest(path: Path, manifest: OrderedDict[str, dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8-sig")


def write_icon_if_needed(
    output_dir: Path,
    filename: str,
    image: Image.Image,
    dry_run: bool,
    protect_existing_layout: bool,
) -> tuple[str, DiffStats]:
    output_path = output_dir / filename
    unchanged, stats = image_diff(output_path, image)
    if unchanged:
        return "unchanged", stats
    if output_path.exists() and protect_existing_layout:
        return "layout_protected", stats
    action = "updated" if output_path.exists() else "created"
    if not dry_run:
        output_dir.mkdir(parents=True, exist_ok=True)
        image.save(output_path, format="PNG", optimize=True)
    return action, stats


def record_icon_write_result(
    report: dict[str, Any],
    *,
    action: str,
    stats: DiffStats,
    icon_name: str,
    frame_label: str,
    filename: str,
) -> None:
    report["counts"][action] += 1
    if action == "layout_protected":
        record_issue(
            report,
            "layoutProtected",
            {
                "name": icon_name,
                "frame": frame_label,
                "filename": filename,
                "changedPixels": stats.changed_pixels,
                "maxChannelDelta": stats.max_channel_delta,
                "totalChannelDelta": stats.total_channel_delta,
                "changedAlphaPixels": stats.changed_alpha_pixels,
            },
        )
    if stats.micro:
        record_issue(
            report,
            "microdiff",
            {
                "name": icon_name,
                "frame": frame_label,
                "changedPixels": stats.changed_pixels,
                "maxChannelDelta": stats.max_channel_delta,
                "totalChannelDelta": stats.total_channel_delta,
                "changedAlphaPixels": stats.changed_alpha_pixels,
            },
        )


def write_static_icon_image(
    output_dir: Path,
    filename: str,
    image: Image.Image,
    icon_name: str,
    frame_label: str,
    dry_run: bool,
    protect_existing_layout: bool,
    report: dict[str, Any],
) -> None:
    action, stats = write_icon_if_needed(
        output_dir,
        filename,
        image,
        dry_run,
        protect_existing_layout=protect_existing_layout,
    )
    record_icon_write_result(
        report,
        action=action,
        stats=stats,
        icon_name=icon_name,
        frame_label=frame_label,
        filename=filename,
    )


def png_is_fully_transparent(path: Path) -> bool:
    try:
        with Image.open(path) as raw:
            return raw.convert("RGBA").getbbox() is None
    except Exception:
        return False


def normalized_frame_digest(source_png: Path, profile_size: tuple[int, int] | None) -> str:
    normalized = normalize_icon(source_png, profile_size)
    digest = zlib.crc32(normalized.tobytes()) & 0xFFFFFFFF
    return f"{normalized.width}x{normalized.height}:{digest:08x}"


def icon_animation_audit(
    frames: list[Path],
    profile_size: tuple[int, int] | None,
) -> dict[str, Any]:
    digest_to_first_frame: dict[str, int] = {}
    timeline_entries = 0
    duplicate_refs = 0
    longest_hold = 1
    previous_digest: str | None = None
    current_hold = 0

    for index, frame in enumerate(frames, start=1):
        digest = normalized_frame_digest(frame, profile_size)
        if digest in digest_to_first_frame:
            duplicate_refs += 1
        else:
            digest_to_first_frame[digest] = index

        if digest == previous_digest:
            current_hold += 1
        else:
            if current_hold:
                longest_hold = max(longest_hold, current_hold)
            timeline_entries += 1
            previous_digest = digest
            current_hold = 1

    if current_hold:
        longest_hold = max(longest_hold, current_hold)

    return {
        "sourceFrameCount": len(frames),
        "uniqueFrameImages": len(digest_to_first_frame),
        "duplicateFrameRefs": duplicate_refs,
        "timelineFrameEntries": timeline_entries,
        "timelineCompressedFrameRefs": max(0, len(frames) - timeline_entries),
        "longestHoldFrames": longest_hold,
        "animatedCandidate": len(digest_to_first_frame) > 1,
    }


def write_animated_icon_frames(
    frames: list[Path],
    output_dir: Path,
    hash_base: str,
    icon_name: str,
    profile_size: tuple[int, int],
    dry_run: bool,
    protect_existing_layout: bool,
    report: dict[str, Any],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    frame_entries: list[dict[str, Any]] = []
    dedupe = FrameDedupeIndex()

    for index, source_frame in enumerate(frames, start=1):
        normalized = normalize_icon(source_frame, profile_size)
        digest = f"{normalized.width}x{normalized.height}:{zlib.crc32(normalized.tobytes()) & 0xFFFFFFFF:08x}"
        frame_ref = dedupe.resolve(digest, index, f"{hash_base}_{index}.png")
        filename = frame_ref.filename
        if not frame_ref.is_duplicate:
            action, stats = write_icon_if_needed(
                output_dir,
                filename,
                normalized,
                dry_run,
                protect_existing_layout=protect_existing_layout,
            )
            report["counts"][action] += 1
            if action == "layout_protected":
                record_issue(
                    report,
                    "layoutProtected",
                    {
                        "name": icon_name,
                        "frame": f"frames[{index}]",
                        "filename": filename,
                        "changedPixels": stats.changed_pixels,
                        "maxChannelDelta": stats.max_channel_delta,
                        "totalChannelDelta": stats.total_channel_delta,
                        "changedAlphaPixels": stats.changed_alpha_pixels,
                    },
                )
            if stats.micro:
                record_issue(
                    report,
                    "microdiff",
                    {
                        "name": icon_name,
                        "frame": f"frames[{index}]",
                        "changedPixels": stats.changed_pixels,
                        "maxChannelDelta": stats.max_channel_delta,
                        "totalChannelDelta": stats.total_channel_delta,
                        "changedAlphaPixels": stats.changed_alpha_pixels,
                    },
                )

        entry: dict[str, Any] = {
            "frame": index,
            "sourceFrame": index,
            "uri": filename,
        }
        if frame_ref.duplicate_of_frame is not None:
            entry["duplicateOfFrame"] = frame_ref.duplicate_of_frame
        frame_entries.append(entry)

    return frame_entries, compressed_timeline_entries(frame_entries)


def write_nested_icon_canvas_frames(
    frames: list[Path],
    output_dir: Path,
    hash_base: str,
    icon_name: str,
    layer_id: int,
    parent_profile_size: tuple[int, int],
    matrix: Matrix,
    filters: list[dict[str, Any]] | None,
    offset: tuple[int, int],
    dry_run: bool,
    protect_existing_layout: bool,
    report: dict[str, Any],
    first_frame_override: Image.Image | None = None,
    crop_frames: bool = False,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], int]:
    frame_entries: list[dict[str, Any]] = []
    dedupe = FrameDedupeIndex()

    for index, source_frame in enumerate(frames, start=1):
        normalized = (
            first_frame_override.copy()
            if index == 1 and first_frame_override is not None
            else nested_layer_frame_icon(source_frame, parent_profile_size, matrix, filters, offset)
        )
        image_to_write = normalized
        crop_meta: dict[str, int] = {}
        if crop_frames:
            image_to_write, crop_meta = crop_icon_canvas(normalized)
            report["counts"]["nested_icon_layer_crop_frame_entries"] += 1
            report["counts"]["nested_icon_layer_crop_canvas_pixels"] += normalized.width * normalized.height
            report["counts"]["nested_icon_layer_crop_pixels"] += image_to_write.width * image_to_write.height
            report["counts"]["nested_icon_layer_crop_saved_pixels"] += (
                normalized.width * normalized.height - image_to_write.width * image_to_write.height
            )
            if len(report.get("nestedIconLayerCropSamples", [])) < 20:
                record_issue(
                    report,
                    "nestedIconLayerCropSamples",
                    {
                        "name": icon_name,
                        "layerId": layer_id,
                        "frame": index,
                        **crop_meta,
                    },
                )
        digest_parts = [
            f"{image_to_write.width}x{image_to_write.height}",
            f"{zlib.crc32(image_to_write.tobytes()) & 0xFFFFFFFF:08x}",
        ]
        if crop_meta:
            digest_parts.append(
                "{cropX},{cropY},{cropWidth},{cropHeight},{canvasWidth},{canvasHeight}".format(**crop_meta)
            )
        digest = ":".join(digest_parts)
        frame_ref = dedupe.resolve(digest, index, f"{hash_base}_layer{layer_id}_{index}.png")
        filename = frame_ref.filename
        if not frame_ref.is_duplicate:
            action, stats = write_icon_if_needed(
                output_dir,
                filename,
                image_to_write,
                dry_run,
                protect_existing_layout=protect_existing_layout,
            )
            report["counts"][action] += 1
            if action == "layout_protected":
                record_issue(
                    report,
                    "layoutProtected",
                    {
                        "name": icon_name,
                        "frame": f"nestedLayer[{layer_id}][{index}]",
                        "filename": filename,
                        "changedPixels": stats.changed_pixels,
                        "maxChannelDelta": stats.max_channel_delta,
                        "totalChannelDelta": stats.total_channel_delta,
                        "changedAlphaPixels": stats.changed_alpha_pixels,
                    },
                )
            if stats.micro:
                record_issue(
                    report,
                    "microdiff",
                    {
                        "name": icon_name,
                        "frame": f"nestedLayer[{layer_id}][{index}]",
                        "changedPixels": stats.changed_pixels,
                        "maxChannelDelta": stats.max_channel_delta,
                        "totalChannelDelta": stats.total_channel_delta,
                        "changedAlphaPixels": stats.changed_alpha_pixels,
                    },
                )

        entry: dict[str, Any] = {
            "frame": index,
            "sourceFrame": index,
            "uri": filename,
        }
        if crop_meta:
            entry.update(crop_meta)
        if frame_ref.duplicate_of_frame is not None:
            entry["duplicateOfFrame"] = frame_ref.duplicate_of_frame
        frame_entries.append(entry)

    return frame_entries, compressed_timeline_entries(frame_entries), dedupe.unique_count


def manifest_entry_files(entry: dict[str, Any]) -> set[str]:
    files: set[str] = set()
    for key in ("f1", "f2"):
        value = entry.get(key)
        if isinstance(value, str) and value:
            files.add(value)
    for key in ("frames", "timelineFrames"):
        values = entry.get(key)
        if isinstance(values, list):
            for item in values:
                if isinstance(item, dict) and isinstance(item.get("uri"), str):
                    files.add(Path(item["uri"]).name)
    nested = entry.get("nestedAnimation")
    if isinstance(nested, dict):
        base = nested.get("base")
        if isinstance(base, dict) and isinstance(base.get("uri"), str):
            files.add(Path(base["uri"]).name)
        for layer in nested.get("layers") or []:
            if not isinstance(layer, dict):
                continue
            for key in ("frames", "timelineFrames"):
                values = layer.get(key)
                if isinstance(values, list):
                    for item in values:
                        if isinstance(item, dict) and isinstance(item.get("uri"), str):
                            files.add(Path(item["uri"]).name)
    return files


def manifest_entry_bytes(output_dir: Path, entry: dict[str, Any]) -> tuple[int, list[str]]:
    total = 0
    missing: list[str] = []
    for filename in sorted(manifest_entry_files(entry)):
        path = output_dir / filename
        if path.exists():
            total += path.stat().st_size
        else:
            missing.append(filename)
    return total, missing


def downgrade_to_static_first_frame(entry: dict[str, Any]) -> dict[str, Any]:
    downgraded = dict(entry)
    for stale_key in (
        "f2",
        "frames",
        "timelineFrames",
        "fps",
        "format",
        "uniqueFrameImages",
        "nestedAnimation",
    ):
        downgraded.pop(stale_key, None)
    downgraded["playback"] = "static-first-frame"
    downgraded["animated"] = False
    downgraded["frameCount"] = 1
    return downgraded


def unlink_unreferenced_entry_files(
    output_dir: Path,
    before: dict[str, Any],
    after: dict[str, Any],
    *,
    dry_run: bool,
    report: dict[str, Any],
    count_key: str = "animated_budget_purged_files",
) -> None:
    before_files = manifest_entry_files(before)
    after_files = manifest_entry_files(after)
    for filename in sorted(before_files - after_files):
        path = output_dir / filename
        if path.exists() and not dry_run:
            path.unlink()
        report["counts"][count_key] += 1


def frame_visual_key(frame: dict[str, Any]) -> tuple[Any, ...]:
    return (
        frame.get("uri"),
        frame.get("cropX"),
        frame.get("cropY"),
        frame.get("cropWidth"),
        frame.get("cropHeight"),
        frame.get("canvasWidth"),
        frame.get("canvasHeight"),
    )


def frame_sequence_has_temporal_motion(frames: list[dict[str, Any]]) -> bool:
    keys = {frame_visual_key(frame) for frame in frames if frame.get("uri")}
    return len(keys) > 1


def manifest_entry_has_temporal_motion(entry: dict[str, Any]) -> bool:
    frames = entry.get("timelineFrames") or entry.get("frames") or []
    if frame_sequence_has_temporal_motion(frames):
        return True
    nested = entry.get("nestedAnimation") or {}
    for layer in nested.get("layers") or []:
        layer_frames = layer.get("timelineFrames") or layer.get("frames") or []
        if frame_sequence_has_temporal_motion(layer_frames):
            return True
    return False


def downgrade_visually_static_animation(
    *,
    output_dir: Path,
    entry: dict[str, Any],
    icon_name: str,
    linkage_id: str,
    dry_run: bool,
    report: dict[str, Any],
) -> dict[str, Any]:
    if not entry.get("animated") or manifest_entry_has_temporal_motion(entry):
        return entry
    downgraded = downgrade_to_static_first_frame(entry)
    unlink_unreferenced_entry_files(
        output_dir,
        entry,
        downgraded,
        dry_run=dry_run,
        report=report,
        count_key="animated_visual_static_purged_files",
    )
    report["counts"]["animated_visual_static_downgraded"] += 1
    record_issue(
        report,
        "animatedVisualStaticDowngraded",
        {
            "name": icon_name,
            "linkageId": linkage_id,
            "fileCount": len(manifest_entry_files(entry)),
            "keptFiles": sorted(manifest_entry_files(downgraded)),
        },
    )
    return downgraded


def apply_animated_icon_budget(
    *,
    output_dir: Path,
    entry: dict[str, Any],
    icon_name: str,
    linkage_id: str,
    max_bytes: int,
    dry_run: bool,
    report: dict[str, Any],
) -> dict[str, Any]:
    if max_bytes <= 0 or not entry.get("animated"):
        return entry
    total_bytes, missing = manifest_entry_bytes(output_dir, entry)
    report["counts"]["animated_icon_budget_checked"] += 1
    report["counts"]["animated_icon_bytes"] += total_bytes
    report["counts"]["animated_icon_missing_byte_files"] += len(missing)
    report["counts"]["animated_icon_max_bytes"] = max(
        int(report["counts"].get("animated_icon_max_bytes", 0)),
        total_bytes,
    )
    if len(report.get("animatedIconSizeSamples", [])) < 50:
        record_issue(
            report,
            "animatedIconSizeSamples",
            {
                "name": icon_name,
                "linkageId": linkage_id,
                "bytes": total_bytes,
                "fileCount": len(manifest_entry_files(entry)),
                "missingFiles": missing[:5],
            },
        )
    if missing or total_bytes <= max_bytes:
        return entry

    downgraded = downgrade_to_static_first_frame(entry)
    unlink_unreferenced_entry_files(output_dir, entry, downgraded, dry_run=dry_run, report=report)
    report["counts"]["animated_icon_budget_skipped"] += 1
    record_issue(
        report,
        "animatedIconBudgetSkipped",
        {
            "name": icon_name,
            "linkageId": linkage_id,
            "bytes": total_bytes,
            "maxBytes": max_bytes,
            "fileCount": len(manifest_entry_files(entry)),
            "keptFiles": sorted(manifest_entry_files(downgraded)),
        },
    )
    return downgraded


def record_issue(report: dict[str, Any], category: str, payload: dict[str, Any]) -> None:
    report.setdefault(category, []).append(payload)


def source_to_json(source: AssetSource) -> dict[str, Any]:
    return {
        "swf": source.swf,
        "symbolName": source.symbol_name or "",
    }


def export_nested_icon_canvas_entry(
    *,
    ffdec: Path,
    project_root: Path,
    tmp_dir: Path,
    output_dir: Path,
    swf_rel: str,
    xml_path: Path,
    target: IconTarget,
    character_id: int,
    parent_frame: Path,
    parent_profile_size: tuple[int, int],
    hash_base: str,
    plan: dict[str, Any],
    zoom: int,
    fps: float,
    dry_run: bool,
    protect_existing_layout: bool,
    freeze_parent_frame1: bool,
    report: dict[str, Any],
    timeout_seconds: int | None = None,
) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    child_id = int(plan["characterId"])
    source_parent_id = int(plan["sourceParentId"])
    matrix = plan["matrix"]
    if not isinstance(matrix, Matrix):
        return None, {"reason": "missing_matrix", "characterId": child_id}
    filters = list(plan.get("filters") or [])

    work_dir = tmp_dir / "nested-icon-canvas" / safe_key(f"{swf_rel}:{target.name}:{character_id}:{child_id}")
    stripped_xml = work_dir / "stripped.xml"
    removed = remove_direct_layer_children(
        xml_path,
        stripped_xml,
        {(source_parent_id, child_id)},
    )
    if removed <= 0:
        return None, {
            "reason": "strip_removed_no_children",
            "characterId": child_id,
            "sourceParentId": source_parent_id,
        }

    stripped_swf = work_dir / "stripped.swf"
    xml_error = xml2swf(
        ffdec,
        project_root,
        stripped_xml,
        stripped_swf,
        f"{swf_rel}#nested-icon-stripped",
        timeout_seconds,
    )
    if xml_error is not None:
        return None, {"reason": "xml2swf_failed", "detail": xml_error}

    stripped_out_dir = work_dir / "stripped-png"
    stripped_error, stripped_fallback = export_sprites_from_swf_path(
        ffdec,
        project_root,
        stripped_swf,
        stripped_out_dir,
        f"{swf_rel}#nested-icon-stripped",
        [character_id],
        zoom,
        timeout_seconds,
    )
    if stripped_fallback is not None:
        record_issue(report, "export_fallbacks", stripped_fallback)
        report["counts"]["export_fallbacks"] += 1
    if stripped_error is not None:
        return None, {"reason": "stripped_parent_export_failed", "detail": stripped_error}

    stripped_parent_dir = find_exported_frame_dir_in_base(stripped_out_dir, character_id)
    stripped_parent_frames = find_exported_frame_paths_in_dir(stripped_parent_dir)
    if not stripped_parent_frames:
        return None, {"reason": "stripped_parent_missing_frames", "characterId": character_id}
    base_frames_to_check = stripped_parent_frames[:1] if freeze_parent_frame1 else stripped_parent_frames
    non_empty_base = [path.name for path in base_frames_to_check if not png_is_fully_transparent(path)]
    if non_empty_base:
        return None, {
            "reason": "stripped_base_not_empty",
            "characterId": character_id,
            "nonEmptyFrameSamples": non_empty_base[:5],
        }

    child_out_dir = work_dir / "child-png"
    child_error, child_fallback = export_sprites_from_swf_path(
        ffdec,
        project_root,
        project_root / swf_rel,
        child_out_dir,
        f"{swf_rel}#nested-icon-child",
        [child_id],
        zoom,
        timeout_seconds,
    )
    if child_fallback is not None:
        record_issue(report, "export_fallbacks", child_fallback)
        report["counts"]["export_fallbacks"] += 1
    if child_error is not None:
        return None, {"reason": "child_export_failed", "detail": child_error}

    child_dir = find_exported_frame_dir_in_base(child_out_dir, child_id)
    child_frames = find_exported_frame_paths_in_dir(child_dir)
    if not child_frames:
        return None, {"reason": "child_missing_frames", "characterId": child_id}

    parent_reference = normalize_icon(parent_frame, parent_profile_size)
    generated_first = nested_layer_frame_icon(child_frames[0], parent_profile_size, matrix, filters)
    close, stats = full_image_diff_images(parent_reference, generated_first)
    if not icon_canvas_projection_close(stats, close):
        return None, {
            "reason": "generated_frame1_diff_too_large",
            "characterId": child_id,
            "changedPixels": stats.changed_pixels,
            "changedAlphaPixels": stats.changed_alpha_pixels,
            "maxChannelDelta": stats.max_channel_delta,
            "totalChannelDelta": stats.total_channel_delta,
        }

    frame_entries, timeline_entries, unique_count = write_nested_icon_canvas_frames(
        child_frames,
        output_dir,
        hash_base,
        target.name,
        child_id,
        parent_profile_size,
        matrix,
        filters,
        (0, 0),
        dry_run,
        protect_existing_layout,
        report,
        first_frame_override=parent_reference,
    )
    if not frame_entries:
        return None, {"reason": "no_frame_entries_written", "characterId": child_id}

    entry: dict[str, Any] = {
        "f1": frame_entries[0]["uri"],
        "frames": frame_entries,
        "playback": "nested-animation",
        "animated": True,
        "fps": fps,
        "format": "png-sequence",
        "frameCount": len(frame_entries),
        "uniqueFrameImages": unique_count,
        "nestedAnimation": {
            "strategy": "single-child-icon-canvas",
            "base": "empty-stripped-parent",
            "characterId": child_id,
            "sourceParentId": source_parent_id,
            "sourceFrameCount": int(plan.get("sourceFrameCount") or len(child_frames)),
            "matrix": matrix.to_json(),
            "filters": filters,
            "offset": {"x": 0, "y": 0},
            "path": plan.get("path") or [],
            "frame1Diff": {
                "exact": bool(stats.exact),
                "micro": bool(stats.micro),
                "changedPixels": stats.changed_pixels,
                "changedAlphaPixels": stats.changed_alpha_pixels,
                "maxChannelDelta": stats.max_channel_delta,
                "totalChannelDelta": stats.total_channel_delta,
            },
        },
    }
    if len(frame_entries) > 1:
        entry["f2"] = frame_entries[1]["uri"]
    if len(timeline_entries) < len(frame_entries):
        entry["timelineFrames"] = timeline_entries

    return entry, None


def diff_payload(stats: DiffStats) -> dict[str, Any]:
    return {
        "exact": bool(stats.exact),
        "micro": bool(stats.micro),
        "changedPixels": stats.changed_pixels,
        "changedAlphaPixels": stats.changed_alpha_pixels,
        "maxChannelDelta": stats.max_channel_delta,
        "totalChannelDelta": stats.total_channel_delta,
    }


def export_layered_icon_canvas_entry(
    *,
    ffdec: Path,
    project_root: Path,
    tmp_dir: Path,
    output_dir: Path,
    swf_rel: str,
    xml_path: Path,
    target: IconTarget,
    character_id: int,
    parent_frame: Path,
    parent_profile_size: tuple[int, int],
    hash_base: str,
    plan: dict[str, Any],
    zoom: int,
    fps: float,
    dry_run: bool,
    protect_existing_layout: bool,
    report: dict[str, Any],
    timeout_seconds: int | None = None,
) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    layers = list(plan.get("layers") or [])
    if not layers:
        return None, {"reason": "no_layers"}
    removals = set(plan.get("removals") or [])
    if not removals:
        return None, {"reason": "no_layer_removals"}

    work_dir = tmp_dir / "layered-icon-canvas" / safe_key(f"{swf_rel}:{target.name}:{character_id}")
    stripped_xml = work_dir / "stripped.xml"
    removed = remove_direct_layer_children(xml_path, stripped_xml, removals)
    if removed < len(removals):
        return None, {
            "reason": "strip_removed_too_few_children",
            "removed": removed,
            "expected": len(removals),
        }

    stripped_swf = work_dir / "stripped.swf"
    xml_error = xml2swf(
        ffdec,
        project_root,
        stripped_xml,
        stripped_swf,
        f"{swf_rel}#layered-icon-stripped",
        timeout_seconds,
    )
    if xml_error is not None:
        return None, {"reason": "xml2swf_failed", "detail": xml_error}

    stripped_out_dir = work_dir / "stripped-png"
    stripped_error, stripped_fallback = export_sprites_from_swf_path(
        ffdec,
        project_root,
        stripped_swf,
        stripped_out_dir,
        f"{swf_rel}#layered-icon-stripped",
        [character_id],
        zoom,
        timeout_seconds,
    )
    if stripped_fallback is not None:
        record_issue(report, "export_fallbacks", stripped_fallback)
        report["counts"]["export_fallbacks"] += 1
    if stripped_error is not None:
        return None, {"reason": "stripped_parent_export_failed", "detail": stripped_error}

    stripped_parent_dir = find_exported_frame_dir_in_base(stripped_out_dir, character_id)
    stripped_parent_frames = find_exported_frame_paths_in_dir(stripped_parent_dir)
    if not stripped_parent_frames:
        return None, {"reason": "stripped_parent_missing_frames", "characterId": character_id}

    child_ids = [int(layer["characterId"]) for layer in layers]
    child_out_dir = work_dir / "child-png"
    child_error, child_fallback = export_sprites_from_swf_path(
        ffdec,
        project_root,
        project_root / swf_rel,
        child_out_dir,
        f"{swf_rel}#layered-icon-child",
        child_ids,
        zoom,
        timeout_seconds,
    )
    if child_fallback is not None:
        record_issue(report, "export_fallbacks", child_fallback)
        report["counts"]["export_fallbacks"] += 1
    if child_error is not None:
        return None, {"reason": "child_export_failed", "detail": child_error}

    base_image = normalize_icon(stripped_parent_frames[0], parent_profile_size)
    parent_reference = normalize_icon(parent_frame, parent_profile_size)
    first_layer_images: list[Image.Image] = []
    layer_frame_paths: dict[int, list[Path]] = {}
    layer_offsets: dict[int, tuple[int, int]] = {}
    for layer in layers:
        child_id = int(layer["characterId"])
        child_dir = find_exported_frame_dir_in_base(child_out_dir, child_id)
        child_frames = find_exported_frame_paths_in_dir(child_dir)
        if not child_frames:
            return None, {"reason": "child_missing_frames", "characterId": child_id}
        matrix = layer.get("matrix")
        if not isinstance(matrix, Matrix):
            return None, {"reason": "missing_layer_matrix", "characterId": child_id}
        layer_frame_paths[child_id] = child_frames
        filters = list(layer.get("filters") or [])
        if len(layers) == 1:
            offset, layer_image, _offset_stats, _offset_close = calibrate_layer_projection_offset(
                parent_reference=parent_reference,
                base_image=base_image,
                source_frame=child_frames[0],
                parent_profile_size=parent_profile_size,
                matrix=matrix,
                filters=filters,
            )
            layer_offsets[child_id] = offset
            first_layer_images.append(layer_image)
        else:
            layer_offsets[child_id] = (0, 0)
            first_layer_images.append(
                nested_layer_frame_icon(child_frames[0], parent_profile_size, matrix, filters)
            )

    generated_first = composite_icon_layers(base_image, first_layer_images)
    close, stats = full_image_diff_images(parent_reference, generated_first)
    if not icon_canvas_projection_close(stats, close):
        return None, {
            "reason": "layered_frame1_diff_too_large",
            **diff_payload(stats),
        }

    fallback_filename = f"{hash_base}_1.png"
    base_filename = f"{hash_base}_base.png"
    write_static_icon_image(
        output_dir,
        fallback_filename,
        parent_reference,
        target.name,
        "layeredFallback[1]",
        dry_run,
        protect_existing_layout,
        report,
    )
    write_static_icon_image(
        output_dir,
        base_filename,
        base_image,
        target.name,
        "layeredBase",
        dry_run,
        protect_existing_layout,
        report,
    )

    layer_entries: list[dict[str, Any]] = []
    total_frames = 0
    total_timeline = 0
    total_unique = 0
    for layer in layers:
        child_id = int(layer["characterId"])
        matrix = layer["matrix"]
        child_frames = layer_frame_paths[child_id]
        filters = list(layer.get("filters") or [])
        offset = layer_offsets.get(child_id, (0, 0))
        frame_entries, timeline_entries, unique_count = write_nested_icon_canvas_frames(
            child_frames,
            output_dir,
            hash_base,
            target.name,
            child_id,
            parent_profile_size,
            matrix,
            filters,
            offset,
            dry_run,
            protect_existing_layout,
            report,
            crop_frames=True,
        )
        layer_entry: dict[str, Any] = {
            "characterId": child_id,
            "sourceParentId": int(layer.get("sourceParentId") or character_id),
            "sourceFrameCount": int(layer.get("sourceFrameCount") or len(child_frames)),
            "depth": int(layer.get("depth") or 0),
            "path": layer.get("path") or [character_id, child_id],
            "matrix": matrix.to_json(),
            "filters": filters,
            "offset": {"x": int(offset[0]), "y": int(offset[1])},
            "fps": fps,
            "frameCount": len(frame_entries),
            "uniqueFrameImages": unique_count,
            "frames": frame_entries,
        }
        if len(timeline_entries) < len(frame_entries):
            layer_entry["timelineFrames"] = timeline_entries
        layer_entries.append(layer_entry)
        total_frames += len(frame_entries)
        total_timeline += len(timeline_entries)
        total_unique += unique_count

    entry: dict[str, Any] = {
        "f1": fallback_filename,
        "playback": "nested-animation",
        "animated": True,
        "fps": fps,
        "format": "layered-png-sequence",
        "nestedAnimation": {
            "strategy": "direct-layered-icon-canvas",
            "base": {"uri": base_filename},
            "layers": layer_entries,
            "frame1Diff": diff_payload(stats),
        },
    }
    entry["_layeredStats"] = {
        "frameEntries": total_frames,
        "timelineEntries": total_timeline,
        "uniqueFrameImages": total_unique,
        "layerCount": len(layer_entries),
    }
    return entry, None


def summarize_unresolved(entries: list[dict[str, Any]]) -> dict[str, Any]:
    by_reason: Counter[str] = Counter()
    by_scope: Counter[str] = Counter()
    by_source_file: Counter[str] = Counter()
    for entry in entries:
        by_reason[str(entry.get("reason") or "<unknown>")] += 1
        by_scope[str(entry.get("scope") or "<unknown>")] += 1
        source_hint = str(entry.get("sourceHint") or "<unknown>")
        by_source_file[source_hint.split(":", 1)[0]] += 1
    return {
        "byReason": dict(sorted(by_reason.items())),
        "byScope": dict(sorted(by_scope.items())),
        "bySourceFile": dict(sorted(by_source_file.items())),
    }


def resolve_cli_path(path_text: str, project_root: Path) -> Path:
    path = Path(path_text)
    if path.is_absolute():
        return path
    return project_root / path


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
    except ValueError:
        return False
    return True


def validate_tmp_dir(tmp_dir: Path, project_root: Path) -> None:
    resolved_tmp = tmp_dir.resolve()
    resolved_root = project_root.resolve()
    allowed_parent = (project_root / "tmp").resolve()
    if not is_relative_to(resolved_tmp, allowed_parent):
        raise SystemExit(f"--tmp-dir must stay under {allowed_parent}")
    if resolved_tmp == resolved_root or resolved_tmp == allowed_parent:
        raise SystemExit("--tmp-dir must name a dedicated subdirectory under tmp/.")


def main() -> int:
    args = parse_args()
    project_root = Path(__file__).resolve().parents[1]
    output_dir = resolve_cli_path(args.output_dir, project_root)
    tmp_dir = resolve_cli_path(args.tmp_dir, project_root)
    report_path = resolve_cli_path(args.report, project_root)
    ffdec = resolve_cli_path(args.ffdec, project_root)
    asset_map = resolve_cli_path(args.asset_map, project_root)

    if args.purge and (args.scope != "all" or args.limit > 0 or args.name):
        raise SystemExit("--purge is only allowed with a full --scope all bake and no --limit/--name filter.")
    if args.resolve_only and args.animation_structure_audit_only:
        raise SystemExit("--resolve-only and --animation-structure-audit-only are mutually exclusive.")
    if args.resolve_only and args.animation_candidates_only:
        raise SystemExit("--resolve-only and --animation-candidates-only are mutually exclusive.")
    if args.animation_structure_audit_only and args.animation_candidates_only:
        raise SystemExit("--animation-structure-audit-only and --animation-candidates-only are mutually exclusive.")
    if args.animation_candidates_only and not args.export_animated_frames:
        raise SystemExit("--animation-candidates-only requires --export-animated-frames.")
    if args.animation_candidate_report and not args.animation_candidates_only:
        raise SystemExit("--animation-candidate-report requires --animation-candidates-only.")
    if args.purge and args.animation_structure_audit_only:
        raise SystemExit("--purge cannot be used with --animation-structure-audit-only.")
    if args.purge and args.animation_candidates_only:
        raise SystemExit("--purge cannot be used with --animation-candidates-only.")
    if args.zoom <= 0:
        raise SystemExit("--zoom must be positive.")
    if args.animated_candidate_max_source_frames < 0:
        raise SystemExit("--animated-candidate-max-source-frames must be non-negative.")
    if not ffdec.exists():
        raise SystemExit(f"Missing FFDec CLI: {ffdec}")
    if not asset_map.exists():
        raise SystemExit(f"Missing asset source map: {asset_map}")
    validate_tmp_dir(tmp_dir, project_root)

    start = time.time()
    if tmp_dir.exists() and not args.keep_tmp:
        remove_tree(tmp_dir)
    tmp_dir.mkdir(parents=True, exist_ok=True)

    derived_targets = derive_targets(project_root, args.scope)
    filters = normalized_names(args.name)
    targets = apply_target_filters(derived_targets, filters, args.limit)
    candidate_report_info: dict[str, Any] | None = None
    if args.animation_candidate_report:
        candidate_report_path = resolve_cli_path(args.animation_candidate_report, project_root)
        if not candidate_report_path.exists():
            raise SystemExit(f"Missing animation candidate report: {candidate_report_path}")
        candidate_names, candidate_report_info = load_animation_candidate_report_targets(
            candidate_report_path,
            strategy=args.animation_candidate_strategy,
            max_source_frames=args.animated_candidate_max_source_frames,
        )
        targets = OrderedDict((name, target) for name, target in targets.items() if name in candidate_names)
    assets, conflicts = parse_asset_map(asset_map)
    manifest_path = output_dir / "manifest.json"
    manifest = load_manifest(manifest_path)

    report: dict[str, Any] = {
        "tool": "tools/bake-icons-offline.py",
        "scope": args.scope,
        "dryRun": bool(args.dry_run),
        "zoom": args.zoom,
        "protectExistingLayout": not bool(args.force_overwrite_existing),
        "targetCount": len(targets),
        "derivedTargetCount": len(derived_targets),
        "outputDir": str(output_dir),
        "tmpDir": str(tmp_dir),
        "counts": defaultdict(int),
    }
    if candidate_report_info is not None:
        report["animationCandidateReport"] = candidate_report_info["path"]
        report["animationCandidateReportSelected"] = candidate_report_info["selected"]
        report["animationCandidateReportSkipped"] = candidate_report_info["skipped"]
        for key, value in candidate_report_info["counts"].items():
            report["counts"]["animation_candidate_report_" + key] = value

    by_swf: dict[str, list[tuple[IconTarget, AssetSource]]] = defaultdict(list)
    target_names = set(targets.keys())

    for target in targets.values():
        source, issue = resolve_target_source(target, assets, conflicts, args.conflict_policy)
        if source is None:
            conflict_sources = conflicts.get(target.linkage_id, [])
            payload = {
                "name": target.name,
                "linkageId": target.linkage_id,
                "scope": target.scope,
                "sourceHint": target.source_hint,
                "reason": issue or "unresolved",
                "conflictCount": len(conflict_sources),
            }
            if conflict_sources:
                payload["conflictSources"] = [source_to_json(item) for item in conflict_sources]
            record_issue(
                report,
                "unresolved",
                payload,
            )
            report["counts"]["unresolved"] += 1
            continue
        if issue:
            record_issue(
                report,
                "resolved_conflicts",
                {
                    "name": target.name,
                    "linkageId": target.linkage_id,
                    "policy": args.conflict_policy,
                    "swf": source.swf,
                },
            )
        by_swf[source.swf].append((target, source))

    if args.resolve_only:
        report["counts"] = dict(report["counts"])
        report["unresolvedSummary"] = summarize_unresolved(report.get("unresolved", []))
        report["resolvedTargetCount"] = sum(len(entries) for entries in by_swf.values())
        report["swfCount"] = len(by_swf)
        report["elapsedSeconds"] = round(time.time() - start, 3)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(
            "[icon-bake-offline] resolve-only targets={targetCount} swfs={swfCount} "
            "resolved={resolved} unresolved={unresolved} report={report}".format(
                targetCount=report["targetCount"],
                swfCount=report["swfCount"],
                resolved=report["resolvedTargetCount"],
                unresolved=report["counts"].get("unresolved", 0),
                report=report_path,
            )
        )
        if args.strict and report["counts"].get("unresolved", 0) > 0:
            return 1
        return 0

    char_ids_by_swf: dict[str, dict[str, int]] = {}
    for swf_rel, entries in by_swf.items():
        symbol_map, error = load_symbol_class(
            ffdec,
            project_root,
            tmp_dir,
            swf_rel,
            args.ffdec_timeout_seconds,
        )
        if error is not None:
            record_issue(report, "symbol_errors", error)
            report["counts"]["symbol_errors"] += 1
            continue
        char_ids: dict[str, int] = {}
        for target, _source in entries:
            char_id = symbol_map.get(target.linkage_id)
            if char_id is None:
                record_issue(
                    report,
                    "missing_symbol",
                    {"name": target.name, "linkageId": target.linkage_id, "swf": swf_rel},
                )
                report["counts"]["missing_symbol"] += 1
                continue
            char_ids[target.name] = char_id
        char_ids_by_swf[swf_rel] = char_ids

    sprite_graphs: dict[str, dict[int, dict[str, Any]]] = {}
    xml_paths_by_swf: dict[str, Path] = {}
    timeline_controls_by_swf: dict[str, dict[int, dict[str, Any]]] = {}
    for swf_rel, char_ids in char_ids_by_swf.items():
        if not char_ids:
            continue
        script_error = export_scripts(ffdec, project_root, tmp_dir, swf_rel, args.ffdec_timeout_seconds)
        if script_error is not None:
            record_issue(report, "script_errors", script_error)
            report["counts"]["script_errors"] += 1
            timeline_controls_by_swf[swf_rel] = {}
        else:
            timeline_controls_by_swf[swf_rel] = collect_timeline_scripts(tmp_dir, swf_rel)

        xml_path, graph_error = export_swf_xml(
            ffdec,
            project_root,
            tmp_dir,
            swf_rel,
            args.ffdec_timeout_seconds,
        )
        if graph_error is not None:
            record_issue(report, "sprite_graph_errors", graph_error)
            report["counts"]["sprite_graph_errors"] += 1
            sprite_graphs[swf_rel] = {}
        elif xml_path is not None:
            xml_paths_by_swf[swf_rel] = xml_path
            try:
                sprite_graphs[swf_rel] = parse_sprite_graph(xml_path)
            except Exception as exc:
                record_issue(
                    report,
                    "sprite_graph_errors",
                    {"swf": swf_rel, "error": "swf_xml_parse_failed", "message": str(exc)},
                )
                report["counts"]["sprite_graph_errors"] += 1
                sprite_graphs[swf_rel] = {}

    structure_payloads: dict[tuple[str, str], dict[str, Any]] = {}
    if args.animation_structure_audit_only or args.animation_candidates_only:
        structure_payloads = collect_animation_structure_payloads(
            by_swf,
            char_ids_by_swf,
            sprite_graphs,
            timeline_controls_by_swf,
        )

    if args.animation_candidates_only:
        filtered_by_swf: dict[str, list[tuple[IconTarget, AssetSource]]] = defaultdict(list)
        filtered_char_ids_by_swf: dict[str, dict[str, int]] = {}
        filtered_target_names: set[str] = set()
        for swf_rel, entries in by_swf.items():
            char_ids = char_ids_by_swf.get(swf_rel, {})
            kept_char_ids: dict[str, int] = {}
            for target, source in entries:
                char_id = char_ids.get(target.name)
                payload = structure_payloads.get((swf_rel, target.name))
                if char_id is None or payload is None:
                    report["counts"]["animation_candidate_filter_skipped"] += 1
                    record_issue(
                        report,
                        "animationCandidateFilterSkipped",
                        {
                            "name": target.name,
                            "linkageId": target.linkage_id,
                            "swf": swf_rel,
                            "reason": "missing_symbol_or_structure",
                        },
                    )
                    continue
                keep, reason = animation_candidate_filter_decision(
                    payload,
                    strategy=args.animation_candidate_strategy,
                    max_source_frames=args.animated_candidate_max_source_frames,
                )
                report["counts"]["animation_candidate_filter_checked"] += 1
                if keep:
                    filtered_by_swf[swf_rel].append((target, source))
                    kept_char_ids[target.name] = char_id
                    filtered_target_names.add(target.name)
                    report["counts"]["animation_candidate_filter_selected"] += 1
                    record_issue(
                        report,
                        "animationCandidateFilterSelected",
                        {
                            "name": target.name,
                            "linkageId": target.linkage_id,
                            "swf": swf_rel,
                            "classification": payload.get("classification"),
                            "maxNestedDescendantFrameCount": payload.get("maxNestedDescendantFrameCount"),
                            "parentPlainFrame1Stop": payload.get("parentPlainFrame1Stop"),
                        },
                    )
                else:
                    report["counts"]["animation_candidate_filter_skipped"] += 1
                    report["counts"]["animation_candidate_filter_skipped_" + reason] += 1
                    record_issue(
                        report,
                        "animationCandidateFilterSkipped",
                        {
                            "name": target.name,
                            "linkageId": target.linkage_id,
                            "swf": swf_rel,
                            "classification": payload.get("classification"),
                            "maxNestedDescendantFrameCount": payload.get("maxNestedDescendantFrameCount"),
                            "reason": reason,
                        },
                    )
            if kept_char_ids:
                filtered_char_ids_by_swf[swf_rel] = kept_char_ids
        by_swf = filtered_by_swf
        char_ids_by_swf = filtered_char_ids_by_swf
        target_names = filtered_target_names
        report["animationCandidateStrategy"] = args.animation_candidate_strategy
        report["animatedCandidateMaxSourceFrames"] = args.animated_candidate_max_source_frames
        report["filteredTargetCount"] = len(filtered_target_names)
        report["filteredSwfCount"] = len(by_swf)

    if args.animation_structure_audit_only:
        unsupported_reasons: Counter[str] = Counter()
        for swf_rel, entries in by_swf.items():
            char_ids = char_ids_by_swf.get(swf_rel, {})
            for target, _source in entries:
                char_id = char_ids.get(target.name)
                if char_id is None:
                    continue
                payload = structure_payloads.get((swf_rel, target.name))
                if payload is None:
                    continue
                classification = str(payload.get("classification") or "unknown")
                report["counts"]["structure_audit_processed"] += 1
                report["counts"]["structure_" + classification.replace("-", "_")] += 1
                if int(payload.get("parentFrameCount") or 0) > 1:
                    report["counts"]["structure_parent_multiframe"] += 1
                if payload.get("parentPlainFrame1Stop"):
                    report["counts"]["structure_parent_plain_frame1_stop"] += 1
                nested_count = int(payload.get("nestedAnimatedDescendantCount") or 0)
                if nested_count > 0:
                    report["counts"]["structure_nested_animation_candidates"] += 1
                    report["counts"]["structure_nested_animation_descendants"] += nested_count
                    report["counts"]["structure_nested_stopped_descendants"] += int(
                        payload.get("nestedStoppedDescendantCount") or 0
                    )
                    if payload.get("parentPlainFrame1Stop"):
                        report["counts"]["structure_parent_stop_with_nested_animation"] += 1
                if classification != "static":
                    record_issue(report, "animationStructureAudit", payload)
                if classification in ("direct-layered-candidate", "single-child-canvas-candidate"):
                    record_issue(report, "animationStructureCandidates", payload)
                if payload.get("parentPlainFrame1Stop") and nested_count > 0:
                    record_issue(report, "animationStructureParentStopNested", payload)
                if classification == "plain-stop-static":
                    record_issue(report, "animationStructurePlainStop", payload)
                if classification == "parent-timeline-needs-png-audit":
                    record_issue(report, "animationStructureParentTimeline", payload)
                if classification == "nested-animation-unsupported":
                    reason = str((payload.get("unsupportedReason") or {}).get("reason") or "unknown")
                    unsupported_reasons[reason] += 1
                    record_issue(report, "animationStructureUnsupported", payload)

        for list_key in (
            "animationStructureAudit",
            "animationStructureCandidates",
            "animationStructureParentStopNested",
            "animationStructurePlainStop",
            "animationStructureParentTimeline",
            "animationStructureUnsupported",
        ):
            if list_key in report:
                report[list_key] = report[list_key][:300]
        report["animationStructureUnsupportedSummary"] = dict(unsupported_reasons)
        report["counts"] = dict(report["counts"])
        report["unresolvedSummary"] = summarize_unresolved(report.get("unresolved", []))
        report["resolvedTargetCount"] = sum(len(entries) for entries in by_swf.values())
        report["swfCount"] = len(by_swf)
        report["elapsedSeconds"] = round(time.time() - start, 3)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if not args.keep_tmp and tmp_dir.exists() and not remove_tree(tmp_dir):
            report["tmpCleanupWarning"] = {"path": str(tmp_dir), "reason": "remove_failed"}
        counts = report["counts"]
        print(
            "[icon-bake-offline] animation-structure-audit targets={targetCount} swfs={swfCount} "
            "processed={processed} parent_stop={parentStop} nested={nested} layered={layered} "
            "single={single} unsupported={unsupported} report={report}".format(
                targetCount=report["targetCount"],
                swfCount=report["swfCount"],
                processed=counts.get("structure_audit_processed", 0),
                parentStop=counts.get("structure_parent_plain_frame1_stop", 0),
                nested=counts.get("structure_nested_animation_candidates", 0),
                layered=counts.get("structure_direct_layered_candidate", 0),
                single=counts.get("structure_single_child_canvas_candidate", 0),
                unsupported=counts.get("structure_nested_animation_unsupported", 0),
                report=report_path,
            )
        )
        if args.strict and (
            counts.get("unresolved", 0) > 0
            or counts.get("symbol_errors", 0) > 0
            or counts.get("missing_symbol", 0) > 0
            or counts.get("sprite_graph_errors", 0) > 0
            or counts.get("script_errors", 0) > 0
        ):
            return 1
        return 0

    for swf_rel, char_ids in char_ids_by_swf.items():
        if not char_ids:
            continue
        error, fallback = export_sprites(
            ffdec,
            project_root,
            tmp_dir,
            swf_rel,
            list(char_ids.values()),
            args.zoom,
            args.ffdec_timeout_seconds,
        )
        if fallback is not None:
            record_issue(report, "export_fallbacks", fallback)
            report["counts"]["export_fallbacks"] += 1
        if error is not None:
            record_issue(report, "export_errors", error)
            report["counts"]["export_errors"] += 1

    f1_profile_size: tuple[int, int] | None = None

    for swf_rel, entries in by_swf.items():
        char_ids = char_ids_by_swf.get(swf_rel, {})
        sprite_graph = sprite_graphs.get(swf_rel) or {}
        xml_path = xml_paths_by_swf.get(swf_rel)
        timeline_controls = timeline_controls_by_swf.get(swf_rel) or {}
        for target, _source in entries:
            char_id = char_ids.get(target.name)
            if char_id is None:
                continue

            f1 = find_exported_frame(tmp_dir, swf_rel, char_id, 1)
            if f1 is None:
                record_issue(
                    report,
                    "missing_frame",
                    {"name": target.name, "linkageId": target.linkage_id, "swf": swf_rel, "frame": 1},
                )
                report["counts"]["missing_frame"] += 1
                continue

            with Image.open(f1) as profile_image:
                target_profile_size = profile_image.size
            if f1_profile_size is None:
                f1_profile_size = target_profile_size
                report["f1Profile"] = {
                    "name": target.name,
                    "linkageId": target.linkage_id,
                    "swf": swf_rel,
                    "characterId": char_id,
                    "rawSize": list(f1_profile_size),
                }

            exported_frames = find_exported_frame_paths(tmp_dir, swf_rel, char_id)
            audit = icon_animation_audit(exported_frames, target_profile_size)
            nested_audit = (
                nested_animation_audit(sprite_graph, timeline_controls, char_id)
                if sprite_graph
                else {
                    "nestedAnimatedDescendantCount": 0,
                    "nestedStoppedDescendantCount": 0,
                    "maxNestedDescendantFrameCount": 0,
                    "sampleNestedDescendants": [],
                }
            )
            parent_info = sprite_graph.get(char_id) if sprite_graph else None
            parent_frame_count = int((parent_info or {}).get("frameCount") or len(exported_frames) or 0)
            parent_frame1_stop = has_plain_frame1_stop(timeline_controls, char_id)
            if len(exported_frames) > 1 or nested_audit["nestedAnimatedDescendantCount"] > 0:
                audit_payload = {
                    "name": target.name,
                    "linkageId": target.linkage_id,
                    "swf": swf_rel,
                    "characterId": char_id,
                    "parentFrameCount": parent_frame_count,
                    "parentPlainFrame1Stop": bool(parent_frame1_stop),
                    **audit,
                    **nested_audit,
                }
                if parent_frame1_stop and len(exported_frames) > 1:
                    audit_payload["staticReason"] = "frame1_plain_stop"
                    audit_payload["collapsedFrameCount"] = len(exported_frames) - 1
                record_issue(report, "animationAudit", audit_payload)
                report["counts"]["multi_frame_symbols"] += 1 if len(exported_frames) > 1 else 0
                report["counts"]["animation_candidates"] += (
                    1
                    if (audit["animatedCandidate"] and not parent_frame1_stop)
                    or nested_audit["nestedAnimatedDescendantCount"] > 0
                    else 0
                )
                report["counts"]["static_multi_frame_symbols"] += (
                    1
                    if len(exported_frames) > 1 and (parent_frame1_stop or not audit["animatedCandidate"])
                    else 0
                )
                report["counts"]["frame1_stop_multi_frame_symbols"] += (
                    1 if len(exported_frames) > 1 and parent_frame1_stop else 0
                )
                report["counts"]["nested_animation_candidates"] += (
                    1 if nested_audit["nestedAnimatedDescendantCount"] > 0 else 0
                )
                report["counts"]["nested_animation_descendants"] += int(
                    nested_audit["nestedAnimatedDescendantCount"]
                )
                report["counts"]["nested_stopped_descendants"] += int(
                    nested_audit["nestedStoppedDescendantCount"]
                )
                report["counts"]["animation_duplicate_frame_refs"] += int(audit["duplicateFrameRefs"])
                report["counts"]["animation_timeline_compressed_frame_refs"] += int(
                    audit["timelineCompressedFrameRefs"]
                )
                report["counts"]["animation_max_source_frame_count"] = max(
                    int(report["counts"].get("animation_max_source_frame_count", 0)),
                    int(audit["sourceFrameCount"]),
                )

            hash_base = crc32_hex(target.name)
            entry = dict(manifest.get(target.name, {}))
            export_parent_animation = (
                args.export_animated_frames
                and not parent_frame1_stop
                and len(exported_frames) > 1
                and bool(audit["animatedCandidate"])
            )
            nested_canvas_entry: dict[str, Any] | None = None
            nested_canvas_plan_error: dict[str, Any] | None = None
            layered_canvas_entry: dict[str, Any] | None = None
            layered_canvas_plan_error: dict[str, Any] | None = None
            export_nested_canvas_animation = (
                args.export_animated_frames
                and not export_parent_animation
                and nested_audit["nestedAnimatedDescendantCount"] > 0
                and xml_path is not None
                and (len(exported_frames) == 1 or parent_frame1_stop)
            )
            if export_nested_canvas_animation:
                report["counts"]["nested_icon_canvas_candidates"] += 1
                layered_plan, layered_plan_error = direct_layered_icon_canvas_plan(
                    sprite_graph,
                    timeline_controls,
                    char_id,
                )
                if layered_plan is not None and (
                    len(layered_plan.get("layers") or []) > 1
                    or int(layered_plan.get("baseDepthCount") or 0) > 0
                ):
                    report["counts"]["nested_icon_layered_candidates"] += 1
                    layered_canvas_entry, layered_canvas_plan_error = export_layered_icon_canvas_entry(
                        ffdec=ffdec,
                        project_root=project_root,
                        tmp_dir=tmp_dir,
                        output_dir=output_dir,
                        swf_rel=swf_rel,
                        xml_path=xml_path,
                        target=target,
                        character_id=char_id,
                        parent_frame=f1,
                        parent_profile_size=target_profile_size,
                        hash_base=hash_base,
                        plan=layered_plan,
                        zoom=args.zoom,
                        fps=args.animation_fps,
                        dry_run=args.dry_run,
                        protect_existing_layout=not args.force_overwrite_existing,
                        report=report,
                        timeout_seconds=args.ffdec_timeout_seconds,
                    )
                    if layered_canvas_entry is None:
                        record_issue(
                            report,
                            "nestedIconLayeredUnsupported",
                            {
                                "name": target.name,
                                "linkageId": target.linkage_id,
                                "swf": swf_rel,
                                "characterId": char_id,
                                **(layered_canvas_plan_error or {"reason": "unknown"}),
                            },
                        )
                        report["counts"]["nested_icon_layered_unsupported"] += 1

                if layered_canvas_entry is None:
                    plan, plan_error = single_nested_icon_canvas_plan(sprite_graph, timeline_controls, char_id)
                    if plan is None:
                        nested_canvas_plan_error = (
                            layered_plan_error
                            or plan_error
                            or {"reason": "no_nested_icon_canvas_plan"}
                        )
                    else:
                        nested_canvas_entry, nested_canvas_plan_error = export_nested_icon_canvas_entry(
                            ffdec=ffdec,
                            project_root=project_root,
                            tmp_dir=tmp_dir,
                            output_dir=output_dir,
                            swf_rel=swf_rel,
                            xml_path=xml_path,
                            target=target,
                            character_id=char_id,
                            parent_frame=f1,
                            parent_profile_size=target_profile_size,
                            hash_base=hash_base,
                            plan=plan,
                            zoom=args.zoom,
                            fps=args.animation_fps,
                            dry_run=args.dry_run,
                            protect_existing_layout=not args.force_overwrite_existing,
                            freeze_parent_frame1=parent_frame1_stop,
                            report=report,
                            timeout_seconds=args.ffdec_timeout_seconds,
                        )
                if layered_canvas_entry is None and nested_canvas_entry is None:
                    payload = {
                        "name": target.name,
                        "linkageId": target.linkage_id,
                        "swf": swf_rel,
                        "characterId": char_id,
                        **(nested_canvas_plan_error or {"reason": "unknown"}),
                    }
                    record_issue(report, "nestedIconCanvasUnsupported", payload)
                    report["counts"]["nested_icon_canvas_unsupported"] += 1

            if export_parent_animation:
                frame_entries, timeline_entries = write_animated_icon_frames(
                    exported_frames,
                    output_dir,
                    hash_base,
                    target.name,
                    target_profile_size,
                    args.dry_run,
                    protect_existing_layout=not args.force_overwrite_existing,
                    report=report,
                )
                if frame_entries:
                    entry["f1"] = frame_entries[0]["uri"]
                    if len(frame_entries) > 1:
                        entry["f2"] = frame_entries[1]["uri"]
                    else:
                        entry.pop("f2", None)
                    entry["frames"] = frame_entries
                    if len(timeline_entries) < len(frame_entries):
                        entry["timelineFrames"] = timeline_entries
                    else:
                        entry.pop("timelineFrames", None)
                    entry["playback"] = "loop"
                    entry["animated"] = True
                    entry["fps"] = args.animation_fps
                    entry["format"] = "png-sequence"
                    entry["frameCount"] = len(frame_entries)
                    entry["uniqueFrameImages"] = int(audit["uniqueFrameImages"])
                    entry.pop("nestedAnimation", None)
                    report["counts"]["animated_manifest_entries"] += 1
                    report["counts"]["animated_frame_entries"] += len(frame_entries)
                    report["counts"]["animated_timeline_entries"] += len(timeline_entries)
                    report["counts"]["animated_unique_frame_images"] += int(audit["uniqueFrameImages"])
            elif layered_canvas_entry is not None:
                layered_stats = layered_canvas_entry.pop("_layeredStats", {})
                entry.update(layered_canvas_entry)
                report["counts"]["nested_icon_layered_manifest_entries"] += 1
                report["counts"]["nested_icon_layered_layers"] += int(layered_stats.get("layerCount") or 0)
                report["counts"]["nested_icon_layered_frame_entries"] += int(layered_stats.get("frameEntries") or 0)
                report["counts"]["nested_icon_layered_timeline_entries"] += int(
                    layered_stats.get("timelineEntries") or 0
                )
                report["counts"]["nested_icon_layered_unique_frame_images"] += int(
                    layered_stats.get("uniqueFrameImages") or 0
                )
                record_issue(
                    report,
                    "nestedIconLayered",
                    {
                        "name": target.name,
                        "linkageId": target.linkage_id,
                        "swf": swf_rel,
                        "characterId": char_id,
                        "layerCount": layered_stats.get("layerCount"),
                        "frameEntries": layered_stats.get("frameEntries"),
                        "uniqueFrameImages": layered_stats.get("uniqueFrameImages"),
                        "frame1Diff": layered_canvas_entry.get("nestedAnimation", {}).get("frame1Diff"),
                    },
                )
            elif nested_canvas_entry is not None:
                entry.update(nested_canvas_entry)
                report["counts"]["nested_icon_canvas_manifest_entries"] += 1
                report["counts"]["nested_icon_canvas_frame_entries"] += len(nested_canvas_entry.get("frames") or [])
                report["counts"]["nested_icon_canvas_timeline_entries"] += len(
                    nested_canvas_entry.get("timelineFrames") or nested_canvas_entry.get("frames") or []
                )
                report["counts"]["nested_icon_canvas_unique_frame_images"] += int(
                    nested_canvas_entry.get("uniqueFrameImages") or 0
                )
                record_issue(
                    report,
                    "nestedIconCanvas",
                    {
                        "name": target.name,
                        "linkageId": target.linkage_id,
                        "swf": swf_rel,
                        "characterId": char_id,
                        "childCharacterId": nested_canvas_entry.get("nestedAnimation", {}).get("characterId"),
                        "frameCount": nested_canvas_entry.get("frameCount"),
                        "uniqueFrameImages": nested_canvas_entry.get("uniqueFrameImages"),
                        "frame1Diff": nested_canvas_entry.get("nestedAnimation", {}).get("frame1Diff"),
                    },
                )
            else:
                for stale_key in (
                    "frames",
                    "timelineFrames",
                    "playback",
                    "animated",
                    "fps",
                    "format",
                    "frameCount",
                    "uniqueFrameImages",
                    "nestedAnimation",
                ):
                    entry.pop(stale_key, None)
                if parent_frame1_stop:
                    stale_f2 = entry.pop("f2", None)
                    entry["playback"] = "static-first-frame"
                    entry["animated"] = False
                    entry["frameCount"] = 1
                    report["counts"]["frame1_stop_static_entries"] += 1
                    if stale_f2:
                        record_issue(
                            report,
                            "frame1StopStatic",
                            {
                                "name": target.name,
                                "linkageId": target.linkage_id,
                                "swf": swf_rel,
                                "characterId": char_id,
                                "removedFrame": "f2",
                                "removedFilename": stale_f2,
                            },
                        )
                        report["counts"]["frame1_stop_removed_f2_manifest"] += 1
                frame_pairs = ((1, "f1"),) if parent_frame1_stop else ((1, "f1"), (2, "f2"))
                for frame_number, frame_key in frame_pairs:
                    source_frame = find_exported_frame(tmp_dir, swf_rel, char_id, frame_number)
                    if source_frame is None:
                        if frame_number == 2 and frame_key in entry:
                            if not args.force_overwrite_existing:
                                record_issue(
                                    report,
                                    "layoutProtected",
                                    {
                                        "name": target.name,
                                        "frame": frame_key,
                                        "filename": entry[frame_key],
                                        "reason": "stale_frame_kept",
                                    },
                                )
                                report["counts"]["layout_protected"] += 1
                                continue
                            stale_name = entry.pop(frame_key)
                            stale_path = output_dir / stale_name
                            if stale_path.exists() and not args.dry_run:
                                stale_path.unlink()
                            report["counts"]["purged_frames"] += 1
                        continue

                    filename = f"{hash_base}_{frame_number}.png"
                    normalized = normalize_icon(
                        source_frame,
                        f1_profile_size if frame_number == 1 else None,
                    )
                    action, stats = write_icon_if_needed(
                        output_dir,
                        filename,
                        normalized,
                        args.dry_run,
                        protect_existing_layout=not args.force_overwrite_existing,
                    )
                    entry[frame_key] = filename
                    report["counts"][action] += 1
                    if action == "layout_protected":
                        record_issue(
                            report,
                            "layoutProtected",
                            {
                                "name": target.name,
                                "frame": frame_key,
                                "filename": filename,
                                "changedPixels": stats.changed_pixels,
                                "maxChannelDelta": stats.max_channel_delta,
                                "totalChannelDelta": stats.total_channel_delta,
                                "changedAlphaPixels": stats.changed_alpha_pixels,
                            },
                        )
                    if stats.micro:
                        record_issue(
                            report,
                            "microdiff",
                            {
                                "name": target.name,
                                "frame": frame_key,
                                "changedPixels": stats.changed_pixels,
                                "maxChannelDelta": stats.max_channel_delta,
                                "totalChannelDelta": stats.total_channel_delta,
                                "changedAlphaPixels": stats.changed_alpha_pixels,
                            },
                        )

            entry = downgrade_visually_static_animation(
                output_dir=output_dir,
                entry=entry,
                icon_name=target.name,
                linkage_id=target.linkage_id,
                dry_run=args.dry_run,
                report=report,
            )
            entry = apply_animated_icon_budget(
                output_dir=output_dir,
                entry=entry,
                icon_name=target.name,
                linkage_id=target.linkage_id,
                max_bytes=args.max_animated_icon_bytes,
                dry_run=args.dry_run,
                report=report,
            )

            if not args.dry_run:
                manifest[target.name] = entry
            report["counts"]["processed"] += 1

    if args.purge:
        all_files = {"manifest.json"}
        for name in list(manifest.keys()):
            if name not in target_names:
                entry = manifest.pop(name)
                for filename in manifest_entry_files(entry):
                    path = output_dir / filename
                    if path.exists() and not args.dry_run:
                        path.unlink()
                    report["counts"]["purged_files"] += 1
                report["counts"]["purged_manifest"] += 1
            else:
                all_files.update(manifest_entry_files(manifest[name]))

        if output_dir.exists():
            for path in output_dir.iterdir():
                if path.is_file() and path.name not in all_files:
                    if not args.dry_run:
                        path.unlink()
                    report["counts"]["purged_files"] += 1

    if not args.dry_run:
        save_manifest(manifest_path, manifest)

    for list_key in (
        "animationAudit",
        "nestedIconCanvas",
        "nestedIconLayered",
        "nestedIconCanvasUnsupported",
        "nestedIconLayeredUnsupported",
        "frame1StopStatic",
        "animatedIconSizeSamples",
        "animatedIconBudgetSkipped",
        "animatedVisualStaticDowngraded",
        "animationCandidateFilterSelected",
        "animationCandidateFilterSkipped",
        "nestedIconLayerCropSamples",
        "layoutProtected",
        "microdiff",
    ):
        if list_key in report:
            report[list_key] = report[list_key][:200]

    report["counts"] = dict(report["counts"])
    report["unresolvedSummary"] = summarize_unresolved(report.get("unresolved", []))
    report["swfCount"] = len(by_swf)
    report["elapsedSeconds"] = round(time.time() - start, 3)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if not args.keep_tmp and tmp_dir.exists() and not remove_tree(tmp_dir):
        report["tmpCleanupWarning"] = {"path": str(tmp_dir), "reason": "remove_failed"}

    counts = report["counts"]
    print(
        "[icon-bake-offline] targets={targetCount} swfs={swfCount} "
        "processed={processed} created={created} updated={updated} unchanged={unchanged} protected={protected} "
        "unresolved={unresolved} missing_symbol={missing_symbol} missing_frame={missing_frame} "
        "report={report}".format(
            targetCount=report["targetCount"],
            swfCount=report["swfCount"],
            processed=counts.get("processed", 0),
            created=counts.get("created", 0),
            updated=counts.get("updated", 0),
            unchanged=counts.get("unchanged", 0),
            protected=counts.get("layout_protected", 0),
            unresolved=counts.get("unresolved", 0),
            missing_symbol=counts.get("missing_symbol", 0),
            missing_frame=counts.get("missing_frame", 0),
            report=report_path,
        )
    )

    if args.strict:
        strict_keys = ["unresolved", "symbol_errors", "missing_symbol", "export_errors", "missing_frame"]
        if any(counts.get(key, 0) > 0 for key in strict_keys):
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
