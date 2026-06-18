from __future__ import annotations

import argparse
import io
import json
import math
import subprocess
import sys
from pathlib import Path
from typing import Any

from PIL import Image


def parse_args() -> argparse.Namespace:
    project_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description=(
            "Compare launcher/web/icons PNGs against a git baseline and optionally restore "
            "tracked files. This is a safety tool for FFDec offline icon bake regressions."
        )
    )
    parser.add_argument(
        "--icons-dir",
        default=str(project_root / "launcher" / "web" / "icons"),
        help="Icon directory. Default: launcher/web/icons.",
    )
    parser.add_argument(
        "--baseline-ref",
        default="HEAD",
        help="Git ref used as the stable baseline. Default: HEAD.",
    )
    parser.add_argument(
        "--report",
        default=str(project_root / "tmp" / "icon-layout-regressions.json"),
        help="JSON report path. Default: tmp/icon-layout-regressions.json.",
    )
    parser.add_argument(
        "--restore",
        action="store_true",
        help="Restore every changed tracked PNG from --baseline-ref after writing the report.",
    )
    parser.add_argument(
        "--all-tracked",
        action="store_true",
        help="Inspect all tracked PNGs instead of only currently modified tracked PNGs.",
    )
    parser.add_argument(
        "--metrics-limit",
        type=int,
        default=250,
        help="Compute bbox/center metrics for at most N changed PNGs. Use 0 for all. Default: 250.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Only inspect the first N tracked PNGs. Intended for quick smoke checks.",
    )
    return parser.parse_args()


def run_git(args: list[str], project_root: Path, *, check: bool = True) -> subprocess.CompletedProcess[bytes]:
    result = subprocess.run(
        ["git", *args],
        cwd=str(project_root),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and result.returncode != 0:
        raise RuntimeError(result.stderr.decode("utf-8", errors="replace") or result.stdout.decode("utf-8", errors="replace"))
    return result


def tracked_pngs(project_root: Path, icons_dir: Path, modified_only: bool) -> list[str]:
    rel_dir = icons_dir.relative_to(project_root).as_posix()
    args = ["ls-files"]
    if modified_only:
        args.append("-m")
    args.append(f"{rel_dir}/*.png")
    result = run_git(args, project_root)
    return [
        line.decode("utf-8", errors="replace").strip()
        for line in result.stdout.splitlines()
        if line.strip()
    ]


def baseline_tree(project_root: Path, ref: str, icons_dir: Path) -> dict[str, str]:
    rel_dir = icons_dir.relative_to(project_root).as_posix()
    result = run_git(["ls-tree", "-r", "-z", ref, "--", rel_dir], project_root)
    blobs: dict[str, str] = {}
    for raw in result.stdout.split(b"\0"):
        if not raw:
            continue
        meta, path_raw = raw.split(b"\t", 1)
        parts = meta.decode("ascii", errors="replace").split()
        if len(parts) >= 3 and parts[1] == "blob":
            path = path_raw.decode("utf-8", errors="replace")
            if path.endswith(".png"):
                blobs[path] = parts[2]
    return blobs


def cat_file_batch(project_root: Path, object_ids: list[str]) -> dict[str, bytes]:
    unique_ids = list(dict.fromkeys(object_ids))
    if not unique_ids:
        return {}
    # run_git cannot stream stdin; use Popen for batch input.
    proc = subprocess.Popen(
        ["git", "cat-file", "--batch"],
        cwd=str(project_root),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    input_data = ("".join(object_id + "\n" for object_id in unique_ids)).encode("ascii")
    stdout, stderr = proc.communicate(input_data)
    if proc.returncode != 0:
        raise RuntimeError(stderr.decode("utf-8", errors="replace") or stdout.decode("utf-8", errors="replace"))

    blobs: dict[str, bytes] = {}
    pos = 0
    for object_id in unique_ids:
        header_end = stdout.find(b"\n", pos)
        if header_end < 0:
            raise RuntimeError("git cat-file --batch output ended unexpectedly")
        header = stdout[pos:header_end].decode("ascii", errors="replace")
        pos = header_end + 1
        parts = header.split()
        if len(parts) < 3 or parts[0] != object_id:
            raise RuntimeError(f"unexpected cat-file header: {header}")
        size = int(parts[2])
        blobs[object_id] = stdout[pos : pos + size]
        pos += size
        if pos < len(stdout) and stdout[pos : pos + 1] == b"\n":
            pos += 1
    return blobs


def alpha_bbox_and_center(image: Image.Image) -> tuple[list[int] | None, list[float] | None, int]:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    min_x = width
    min_y = height
    max_x = -1
    max_y = -1
    alpha_sum = 0
    x_sum = 0.0
    y_sum = 0.0
    for y in range(height):
        for x in range(width):
            alpha = pixels[x, y][3]
            if alpha <= 0:
                continue
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x)
            max_y = max(max_y, y)
            alpha_sum += alpha
            x_sum += x * alpha
            y_sum += y * alpha
    if alpha_sum <= 0:
        return None, None, 0
    return [min_x, min_y, max_x + 1, max_y + 1], [x_sum / alpha_sum, y_sum / alpha_sum], alpha_sum


def bbox_iou(a: list[int] | None, b: list[int] | None) -> float:
    if a is None or b is None:
        return 0.0
    ix0 = max(a[0], b[0])
    iy0 = max(a[1], b[1])
    ix1 = min(a[2], b[2])
    iy1 = min(a[3], b[3])
    iw = max(0, ix1 - ix0)
    ih = max(0, iy1 - iy0)
    inter = iw * ih
    area_a = max(0, a[2] - a[0]) * max(0, a[3] - a[1])
    area_b = max(0, b[2] - b[0]) * max(0, b[3] - b[1])
    union = area_a + area_b - inter
    return float(inter) / float(union) if union > 0 else 0.0


def changed_alpha_pixels(old_image: Image.Image, new_image: Image.Image) -> int:
    old = old_image.convert("RGBA")
    new = new_image.convert("RGBA")
    if old.size != new.size:
        return -1
    old_bytes = old.tobytes()
    new_bytes = new.tobytes()
    changed = 0
    for i in range(3, len(old_bytes), 4):
        if old_bytes[i] != new_bytes[i]:
            changed += 1
    return changed


def compare_png(old_bytes: bytes, new_path: Path) -> dict[str, Any]:
    old_image = Image.open(io.BytesIO(old_bytes)).convert("RGBA")
    new_image = Image.open(new_path).convert("RGBA")
    old_bbox, old_center, old_alpha = alpha_bbox_and_center(old_image)
    new_bbox, new_center, new_alpha = alpha_bbox_and_center(new_image)
    center_shift = None
    if old_center is not None and new_center is not None:
        center_shift = math.dist(old_center, new_center)
    return {
        "oldSize": list(old_image.size),
        "newSize": list(new_image.size),
        "oldBBox": old_bbox,
        "newBBox": new_bbox,
        "oldCenter": old_center,
        "newCenter": new_center,
        "centerShift": center_shift,
        "bboxIoU": bbox_iou(old_bbox, new_bbox),
        "oldAlphaSum": old_alpha,
        "newAlphaSum": new_alpha,
        "changedAlphaPixels": changed_alpha_pixels(old_image, new_image),
    }


def main() -> int:
    args = parse_args()
    project_root = Path(__file__).resolve().parents[1]
    icons_dir = Path(args.icons_dir)
    if not icons_dir.is_absolute():
        icons_dir = project_root / icons_dir
    report_path = Path(args.report)
    if not report_path.is_absolute():
        report_path = project_root / report_path

    rel_paths = tracked_pngs(project_root, icons_dir, modified_only=not args.all_tracked)
    if args.limit > 0:
        rel_paths = rel_paths[: args.limit]

    report: dict[str, Any] = {
        "tool": "tools/audit-icon-layout-regressions.py",
        "baselineRef": args.baseline_ref,
        "iconsDir": str(icons_dir),
        "restore": bool(args.restore),
        "allTracked": bool(args.all_tracked),
        "metricsLimit": int(args.metrics_limit),
        "counts": {
            "tracked": len(rel_paths),
            "changed": 0,
            "restored": 0,
            "missingCurrent": 0,
            "missingBaseline": 0,
            "decodeErrors": 0,
        },
        "changed": [],
        "decodeErrors": [],
    }

    metrics_written = 0
    baseline_blobs = baseline_tree(project_root, args.baseline_ref, icons_dir)
    object_ids = [
        baseline_blobs[rel_path]
        for rel_path in rel_paths
        if rel_path in baseline_blobs
    ]
    object_bytes = cat_file_batch(project_root, object_ids)

    for rel_path in rel_paths:
        current_path = project_root / rel_path
        if not current_path.exists():
            report["counts"]["missingCurrent"] += 1
            continue
        object_id = baseline_blobs.get(rel_path)
        if object_id is None:
            report["counts"]["missingBaseline"] += 1
            continue
        old_bytes = object_bytes[object_id]
        new_bytes = current_path.read_bytes()
        if old_bytes == new_bytes:
            continue
        report["counts"]["changed"] += 1
        metrics: dict[str, Any] = {}
        if args.metrics_limit <= 0 or metrics_written < args.metrics_limit:
            try:
                metrics = compare_png(old_bytes, current_path)
                metrics_written += 1
            except Exception as exc:
                report["counts"]["decodeErrors"] += 1
                report["decodeErrors"].append({"path": rel_path, "error": str(exc)})
        entry = {"path": rel_path, **metrics}
        report["changed"].append(entry)
        if args.restore:
            current_path.write_bytes(old_bytes)
            report["counts"]["restored"] += 1

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "[icon-layout-audit] tracked={tracked} changed={changed} restored={restored} "
        "missingCurrent={missingCurrent} missingBaseline={missingBaseline} report={report}".format(
            tracked=report["counts"]["tracked"],
            changed=report["counts"]["changed"],
            restored=report["counts"]["restored"],
            missingCurrent=report["counts"]["missingCurrent"],
            missingBaseline=report["counts"]["missingBaseline"],
            report=report_path,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
