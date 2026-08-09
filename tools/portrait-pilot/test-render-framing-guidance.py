#!/usr/bin/env python3
"""End-to-end self-test for human framing export, receipt, and direct high-resolution rendering."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import subprocess
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = ROOT / "tmp" / "portrait-pilot"


def run(command: list[str]) -> dict[str, object]:
    completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", timeout=180)
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or completed.stdout.strip())
    return json.loads(completed.stdout.strip().splitlines()[-1])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-batch", required=True)
    args = parser.parse_args()
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    guidance_name = f"framing-guidance-selftest-{stamp}"
    render_name = f"framing-render-selftest-{stamp}"
    guidance_root = PILOT_ROOT / guidance_name
    render_root = PILOT_ROOT / render_name
    built = run(
        [
            "node",
            "tools/portrait-pilot/build-framing-guidance.js",
            "--source-batch",
            args.source_batch,
            "--output",
            guidance_root.relative_to(ROOT).as_posix(),
            "--batch-id",
            guidance_name,
        ]
    )
    dataset = json.loads((guidance_root / "framing-guidance-data.json").read_text(encoding="utf-8"))
    guidance_map: dict[str, object] = {}
    now = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
    for item in dataset["items"]:
        role = item.get("preferredRoleHint") or "proposal"
        choice = next(entry for entry in item["choices"] if entry["sourceRole"] == role)
        x0, y0, x1, y1 = (float(value) for value in choice["initialCropBox"])
        width = float(choice["candidateWidth"])
        height = float(choice["candidateHeight"])
        side = ((x1 - x0) * width + (y1 - y0) * height) / 2 / 1.1
        center_x = (x0 + x1) / 2 * width
        center_y = (y0 + y1) / 2 * height
        crop_box = [
            (center_x - side / 2) / width,
            (center_y - side / 2) / height,
            (center_x + side / 2) / width,
            (center_y + side / 2) / height,
        ]
        guidance_map[item["reviewKey"]] = {
            "sourceRole": role,
            "candidateId": choice["candidateId"],
            "sourceCandidateSha256": choice["sourceCandidate"]["sha256"],
            "cropBox": [round(value, 9) for value in crop_box],
            "updatedAt": now,
        }
    guidance = {
        "schema": dataset["guidanceSchema"],
        "batchId": dataset["batchId"],
        "guidanceDigest": dataset["guidanceDigest"],
        "parentReceiptDigest": dataset["parent"]["receiptDigest"],
        "complete": True,
        "exportedAt": now,
        "guidance": guidance_map,
    }
    (guidance_root / "portrait-pilot-framing-guidance.json").write_text(
        json.dumps(guidance, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    receipt = run(["node", "tools/portrait-pilot/verify-framing-guidance.js", "--batch", guidance_root.relative_to(ROOT).as_posix()])
    rendered = run(
        [
            "python",
            "tools/portrait-pilot/render-framing-guidance.py",
            "render",
            "--guidance-batch",
            guidance_root.relative_to(ROOT).as_posix(),
            "--output",
            render_root.relative_to(ROOT).as_posix(),
            "--batch-id",
            render_name,
        ]
    )
    checked = run(["python", "tools/portrait-pilot/render-framing-guidance.py", "check", "--output", render_root.relative_to(ROOT).as_posix()])
    report = json.loads((render_root / "human-framing-render-report.json").read_text(encoding="utf-8"))
    if len(report["rows"]) != len(dataset["items"]):
        raise RuntimeError("self-test render row count mismatch")
    for row in report["rows"]:
        master = ROOT / row["master"]["path"]
        preview = ROOT / row["previews"]["80"]["path"]
        with Image.open(master) as image:
            if image.size != (512, 512) or image.convert("RGBA").getchannel("A").getbbox() is None:
                raise RuntimeError("self-test master dimensions or alpha invalid")
        with Image.open(preview) as image:
            if image.size != (80, 80):
                raise RuntimeError("self-test preview dimensions invalid")
    print(
        json.dumps(
            {
                "status": "human_framing_direct_render_e2e_verified",
                "guidanceDigest": built["guidanceDigest"],
                "guidanceReceiptDigest": receipt["receiptDigest"],
                "renderReportDigest": rendered["reportDigest"],
                "rows": rendered["rows"],
                "artifactCount": checked["artifactCount"],
                "modelRerun": False,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
