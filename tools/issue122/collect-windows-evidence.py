"""Curate an immutable, hashed evidence directory from completed local probe runs."""
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    root = Path(__file__).resolve().parents[2]
    destination = Path(sys.argv[1]).resolve()
    runs = [Path(value).resolve() for value in sys.argv[2:]]
    if destination.exists():
        raise ValueError("Refusing to replace existing curated evidence")
    # Read and validate every run before creating the destination.
    reports = [json.loads((run / "result.json").read_text(encoding="utf-8")) for run in runs]
    analyses = [json.loads((run / "pixel-analysis.json").read_text(encoding="utf-8")) for run in runs]
    if any(report["status"] != "completed" or len(report["cells"]) != 10 or
           not report["backendVerified"] or any(not row["pixelsStable"] for row in report["cells"])
           for report in reports):
        raise ValueError("Expected ten completed, stable cells per verified backend matrix")
    if any((run / "failure.txt").exists() for run in runs):
        raise ValueError("Failure logs require review before collection")
    destination.mkdir(parents=True)
    source_identity = root / "tmp/issue122-local/source-identity.json"
    shutil.copy2(source_identity, destination / "first-build-identity.json")
    shutil.copy2(root / "tmp/issue122-local/classification-tests-second.json", destination / "classification-tests.json")
    shutil.copy2(root / "tmp/issue122-linux/geometry.json", destination / "geometry.json")
    summary = {"schema": 1, "baseCommit": subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip(),
        "status": "matrix_completed_original_symptom_not_observed",
        "classification": "mixed_result_manual_review_required", "runs": [],
        "boundary": "Independent WebView2 evidence; no production Host/Flash journey or historical driver reproduction."}
    for index, (run, report, analysis) in enumerate(zip(runs, reports, analyses), start=1):
        prefix = f"run{index}"
        shutil.copy2(run / "result.json", destination / (prefix + "-result.json"))
        shutil.copy2(run / "pixel-analysis.json", destination / (prefix + "-pixels.json"))
        shutil.copy2(run / "progress.log", destination / (prefix + "-progress.log"))
        if (run / "execution.json").exists():
            shutil.copy2(run / "execution.json", destination / (prefix + "-execution.json"))
        summary["runs"].append({"run": prefix, "rawDirectory": str(run),
            "cells": len(report["cells"]), "classification": report["classification"],
            "gpu": report["cells"][0]["gl"]["unmaskedRenderer"],
            "comparisons": analysis["comparisons"]})
    # Representative direct captures and one numeric difference visualization.
    representatives = [(runs[0], "gpu-issue-time-raw.png", "intel-original-raw.png"),
        (runs[-1], "gpu-diagnostic-low-side-raw.png", "nvidia-low-side-raw.png"),
        (runs[-1], "gpu-diagnostic-low-side-chunked.png", "nvidia-low-side-chunked.png"),
        (runs[1], "gpu-current-raw-vs-nonindexed-difference-x8.png", "nvidia-current-difference-x8.png")]
    for run, filename, name in representatives:
        shutil.copy2(run / filename, destination / name)
    summary["totalCells"] = sum(len(report["cells"]) for report in reports)
    all_comparisons = [row for analysis in analyses for row in analysis["comparisons"]]
    summary["comparisonCount"] = len(all_comparisons)
    summary["maxChangedPixels"] = max(row["changedPixels"] for row in all_comparisons)
    summary["maxChangedPercent"] = max(row["changedPercent"] for row in all_comparisons)
    summary["maxChannelDifference"] = max(row["maximumChannelDifference"] for row in all_comparisons)
    (destination / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    inputs = ["tools/issue122/windows-webview2/Program.cs", "tools/issue122/windows-webview2/ProbeRules.cs",
        "tools/issue122/windows-webview2/Issue122.WebView2.csproj", "tools/issue122/windows-webview2/run-local.ps1",
        "tools/issue122/analyze-windows-pixels.py", "tools/issue122/collect-windows-evidence.py", "launcher/web/modules/stage-select/dev/issue122-index-fixture.html",
        "launcher/web/modules/stage-select/stage-select-fallen-scene.js", "launcher/web/modules/stage-select/stage-select-fallen-data.js",
        "launcher/web/modules/stage-select/stage-select-geometry-chunks.js"]
    (destination / "final-source-inputs.json").write_text(json.dumps({"baseCommit": summary["baseCommit"],
        "inputs": [{"path": value, "sha256": digest(root / value)} for value in inputs]}, indent=2) + "\n", encoding="utf-8")
    inventory = [{"path": path.name, "bytes": path.stat().st_size, "sha256": digest(path)}
                 for path in sorted(destination.iterdir()) if path.is_file()]
    manifest = {"schema": 1, "algorithm": "SHA-256", "fileCount": len(inventory),
                "totalBytes": sum(row["bytes"] for row in inventory), "files": inventory,
                "excluded": ["browser profiles", "binary build outputs", "redundant repeat captures", "full original logs kept in tmp"]}
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: summary[key] for key in ("totalCells", "comparisonCount", "maxChangedPixels", "maxChangedPercent", "maxChannelDifference")}))
    print(json.dumps({"files": len(inventory), "bytes": manifest["totalBytes"], "destination": str(destination)}))


if __name__ == "__main__":
    main()
