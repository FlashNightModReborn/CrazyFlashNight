#!/usr/bin/env python3
"""Build deterministic black-to-alpha portrait candidates from a frozen human review row."""

from __future__ import annotations

import argparse
import datetime as dt
import gc
from pathlib import Path
import sys

import numpy as np
from PIL import Image, __version__ as PILLOW_VERSION

from prepare_pilot import (
    PILOT_ROOT,
    ROOT,
    PilotError,
    artifact,
    ensure_below,
    load_json,
    repo_rel,
    sha256_bytes,
    stable_bytes,
    verify_artifact_record,
    verify_digest_object,
    write_json,
)


DATA_SCHEMA = "cf7.enemy-portrait-black-matte-candidates.v1"
DECISION_SCHEMA = "cf7.enemy-portrait-black-matte-decisions.v1"
DATA_NAME = "black-matte-review-data.json"
REVIEW_KEY = "敌人-迷你黑洞::default"
ROLE_LABELS = {
    "proposal": "Luna A 构图",
    "independent_review": "Luna B 独立复核构图",
}
VARIANTS = (
    ("g050", 0.50, "柔和保留", "透明度较高，优先保留暗部烟雾与外圈层次。"),
    ("g075", 0.75, "平衡（推荐）", "在暗部层次与背景穿透之间取中间值。"),
    ("g100", 1.00, "强抠黑", "最大化去除黑底，发光结构更通透。"),
)
REVIEWER_FILES = (
    ROOT / "tools" / "portrait-pilot" / "prepare_black_matte_review_v1.py",
    ROOT / "tools" / "portrait-pilot" / "verify-black-matte-review.js",
    ROOT / "tools" / "portrait-pilot" / "open-black-matte-review.js",
    ROOT / "tools" / "portrait-pilot" / "test-black-matte-review.js",
    ROOT / "launcher" / "web" / "modules" / "portrait-pilot-review" / "dev" / "black-matte.html",
    ROOT / "launcher" / "web" / "modules" / "portrait-pilot-review" / "dev" / "black-matte.js",
    ROOT / "launcher" / "web" / "modules" / "portrait-pilot-review" / "dev" / "review.css",
)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def require_object(value: object, label: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise PilotError(f"{label} 必须是对象")
    return value


def require_list(value: object, label: str) -> list[object]:
    if not isinstance(value, list):
        raise PilotError(f"{label} 必须是数组")
    return value


def pilot_batch(value: str, label: str, must_exist: bool) -> Path:
    path = ensure_below(ROOT / value, PILOT_ROOT, label)
    if must_exist and not path.is_dir():
        raise PilotError(f"{label} 不存在：{repo_rel(path)}")
    if not must_exist and path.exists():
        raise PilotError(f"{label} 已存在，禁止覆盖：{repo_rel(path)}")
    return path


def verified_json(path: Path, digest_field: str, label: str) -> dict[str, object]:
    value = require_object(load_json(path), label)
    verify_digest_object(value, digest_field, label)
    return value


def verified_review_data(path: Path) -> dict[str, object]:
    value = require_object(load_json(path), "父 review data")
    envelope = {
        key: value.get(key)
        for key in (
            "schema",
            "sourceDigest",
            "manifestDigest",
            "modelReportDigest",
            "renderDigest",
            "decisionSchema",
            "reviewer",
            "statuses",
            "items",
        )
    }
    if value.get("schema") == "cf7.portrait-pilot-review-data.v2":
        envelope["decisionSemantics"] = value.get("decisionSemantics")
        envelope["counts"] = value.get("counts")
    if sha256_bytes(stable_bytes(envelope)) != value.get("reviewDigest"):
        raise PilotError("父 review data reviewDigest 不匹配")
    return value


def load_parent(root: Path, review_key: str) -> dict[str, object]:
    paths = {
        "candidateManifest": root / "candidate-manifest.json",
        "modelReport": root / "model-report.json",
        "renderReport": root / "render-report.json",
        "reviewData": root / "review-data.json",
        "decisions": root / "portrait-pilot-review-decisions.json",
        "humanReviewReceipt": root / "human-review-receipt.json",
    }
    manifest = verified_json(paths["candidateManifest"], "manifestDigest", "父 candidate manifest")
    model = verified_json(paths["modelReport"], "reportDigest", "父 model report")
    render = verified_json(paths["renderReport"], "renderDigest", "父 render report")
    review = verified_review_data(paths["reviewData"])
    receipt = verified_json(paths["humanReviewReceipt"], "receiptDigest", "父人审回执")
    decisions = require_object(load_json(paths["decisions"]), "父人审决定")

    if (
        model.get("manifestDigest") != manifest.get("manifestDigest")
        or render.get("manifestDigest") != manifest.get("manifestDigest")
        or render.get("modelReportDigest") != model.get("reportDigest")
        or review.get("sourceDigest") != manifest.get("sourceDigest")
        or receipt.get("sourceDigest") != manifest.get("sourceDigest")
        or receipt.get("reviewDigest") != review.get("reviewDigest")
        or receipt.get("productionReady") is not False
    ):
        raise PilotError("父 manifest/model/render/review/receipt 摘要链不闭合")
    for name, record in require_object(receipt.get("inputs"), "父人审 inputs").items():
        verified_path = verify_artifact_record(require_object(record, f"父人审 {name}"), f"父人审 {name}")
        expected = paths.get(str(name))
        if expected is None or verified_path != expected.resolve():
            raise PilotError(f"父人审 input 路径不匹配：{name}")

    decision_rows = [
        require_object(row, "父人审 row")
        for row in require_list(receipt.get("decisions"), "父人审 decisions")
        if isinstance(row, dict) and row.get("reviewKey") == review_key
    ]
    if len(decision_rows) != 1 or decision_rows[0].get("status") != "wrong_pose":
        raise PilotError("目标行不是唯一、已冻结的 wrong_pose 人审行")
    note = str(decision_rows[0].get("notes", ""))
    if not note.strip() or not any(token in note for token in ("透明", "alpha", "Alpha", "黑色", "黑底", "抠图")):
        raise PilotError("目标 wrong_pose 备注没有明确指向黑底/透明后处理")

    rows = [
        require_object(row, "父 render row")
        for row in require_list(render.get("rows"), "父 render rows")
        if isinstance(row, dict) and row.get("reviewKey") == review_key
    ]
    if {row.get("role") for row in rows} != set(ROLE_LABELS) or len(rows) != 2:
        raise PilotError("目标行缺 proposal/independent_review 两路 render")
    if len({(row.get("candidateId"), row.get("frame")) for row in rows}) != 1:
        raise PilotError("两路 render 未绑定同一冻结帧")
    for row in rows:
        for field in ("master", "sourceSupersample", "sourceHighResolution", "sourceGeometrySvg"):
            verify_artifact_record(require_object(row.get(field), f"render {field}"), f"render {field}")
        for size, record in require_object(row.get("previews"), "render previews").items():
            if size not in {"32", "48", "80"}:
                raise PilotError("父 preview 尺寸集合漂移")
            verify_artifact_record(require_object(record, f"render preview {size}"), f"render preview {size}")

    return {
        "paths": paths,
        "manifest": manifest,
        "model": model,
        "render": render,
        "review": review,
        "receipt": receipt,
        "decisions": decisions,
        "humanDecision": decision_rows[0],
        "rows": sorted(rows, key=lambda row: str(row["role"])),
    }


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=False, compress_level=9)


def matte_image(source: Image.Image, gamma: float) -> tuple[Image.Image, dict[str, object]]:
    source_array = np.asarray(source.convert("RGBA"), dtype=np.uint8)
    height, width, _ = source_array.shape
    output = np.zeros_like(source_array)
    total_error = 0
    maximum_error = 0
    transparent = 0
    nonzero_alpha = 0
    alpha_sum = 0
    for top in range(0, height, 256):
        block = source_array[top : top + 256]
        rgb = block[..., :3].astype(np.float32) / 255.0
        old_alpha = block[..., 3].astype(np.float32) / 255.0
        value = np.max(rgb, axis=2)
        matte = np.power(value, gamma, dtype=np.float32)
        safe = np.where(matte > 0.0, matte, 1.0)
        new_rgb = np.where(matte[..., None] > 0.0, rgb / safe[..., None], 0.0)
        new_alpha = old_alpha * matte
        out_rgb = np.clip(np.rint(new_rgb * 255.0), 0, 255).astype(np.uint8)
        out_alpha = np.clip(np.rint(new_alpha * 255.0), 0, 255).astype(np.uint8)
        output[top : top + block.shape[0], ..., :3] = out_rgb
        output[top : top + block.shape[0], ..., 3] = out_alpha

        original_black = np.rint(block[..., :3].astype(np.float32) * old_alpha[..., None]).astype(np.int16)
        result_black = np.rint(out_rgb.astype(np.float32) * (out_alpha.astype(np.float32) / 255.0)[..., None]).astype(np.int16)
        error = np.abs(original_black - result_black)
        total_error += int(error.sum())
        maximum_error = max(maximum_error, int(error.max(initial=0)))
        transparent += int(np.count_nonzero(out_alpha == 0))
        nonzero_alpha += int(np.count_nonzero(out_alpha > 0))
        alpha_sum += int(out_alpha.astype(np.uint64).sum())

    pixel_count = width * height
    metrics = {
        "blackCompositeMeanAbsoluteError": round(total_error / (pixel_count * 3), 6),
        "blackCompositeMaximumAbsoluteError": maximum_error,
        "transparentPixelFraction": round(transparent / pixel_count, 6),
        "nonzeroAlphaPixelFraction": round(nonzero_alpha / pixel_count, 6),
        "meanAlpha": round(alpha_sum / pixel_count, 6),
    }
    return Image.fromarray(output), metrics


def candidate_digest(candidate: dict[str, object]) -> str:
    return sha256_bytes(stable_bytes(candidate))


def build_candidate(output_root: Path, row: dict[str, object], code: str, gamma: float, label: str, description: str) -> dict[str, object]:
    role = str(row["role"])
    candidate_id = f"{role}-{code}"
    candidate_root = output_root / "black-matte-candidates-v1" / role / code
    source_record = require_object(row["sourceSupersample"], "source supersample")
    source_path = verify_artifact_record(source_record, "source supersample")
    with Image.open(source_path) as opened:
        source = opened.convert("RGBA")
    if source.size != (4096, 4096):
        raise PilotError(f"黑底转 alpha 输入必须是 4096×4096：{candidate_id}={source.size}")
    processed, metrics = matte_image(source, gamma)
    supersample_path = candidate_root / "master-4096.png"
    save_png(processed, supersample_path)
    outputs: dict[str, object] = {"supersample4096": artifact(supersample_path)}
    for size in (512, 80, 48, 32):
        target = processed.resize((size, size), Image.Resampling.LANCZOS)
        name = "master-512.png" if size == 512 else f"preview-{size}.png"
        target_path = candidate_root / name
        save_png(target, target_path)
        outputs["master512" if size == 512 else f"preview{size}"] = artifact(target_path)
    candidate: dict[str, object] = {
        "candidateId": candidate_id,
        "role": role,
        "roleLabel": ROLE_LABELS[role],
        "framingMode": row.get("framingMode"),
        "candidateSourceId": row.get("candidateId"),
        "frame": row.get("frame"),
        "gamma": gamma,
        "label": label,
        "description": description,
        "recommended": gamma == 0.75,
        "sourceSupersample": source_record,
        "sourceGeometrySvg": row.get("sourceGeometrySvg"),
        "outputs": outputs,
        "metrics": metrics,
    }
    candidate["candidateDigest"] = candidate_digest(candidate)
    del processed
    del source
    gc.collect()
    return candidate


def verify_dataset(dataset: dict[str, object]) -> int:
    if (
        dataset.get("schema") != DATA_SCHEMA
        or dataset.get("phase") != "BLACK_MATTE_HUMAN_REVIEW"
        or dataset.get("status") != "black_matte_candidates_ready"
        or dataset.get("productionReady") is not False
        or dataset.get("decisionSchema") != DECISION_SCHEMA
    ):
        raise PilotError("black matte dataset schema 或状态非法")
    verify_digest_object(dataset, "datasetDigest", "black matte dataset")
    gates = require_object(dataset.get("gates"), "black matte gates")
    expected_gates = {
        "onlyFrozenHumanPostprocessRow": True,
        "currentFrameRetained": True,
        "noModelCall": True,
        "exactFormulaRecorded": True,
        "highResolution4096Retained": True,
        "blackCompositeMaximumErrorLte2": True,
        "humanCandidateSelectionRequired": True,
        "productionWrites": False,
    }
    if gates != expected_gates:
        raise PilotError("black matte gates 漂移")
    artifact_count = 0
    parent = require_object(dataset.get("parent"), "black matte parent")
    for name, record in require_object(parent.get("files"), "black matte parent files").items():
        verify_artifact_record(require_object(record, str(name)), f"parent {name}")
        artifact_count += 1
    reviewer = require_object(dataset.get("reviewer"), "black matte reviewer")
    reviewer_files = require_list(reviewer.get("files"), "black matte reviewer files")
    for record in reviewer_files:
        verify_artifact_record(require_object(record, "reviewer file"), "reviewer file")
        artifact_count += 1
    if sha256_bytes(stable_bytes(reviewer_files)) != reviewer.get("sourceClosureDigest"):
        raise PilotError("black matte reviewer source closure 漂移")

    items = require_list(dataset.get("items"), "black matte items")
    if len(items) != 1:
        raise PilotError("black matte 当前批次必须恰有一个人审行")
    item = require_object(items[0], "black matte item")
    originals = require_list(item.get("originals"), "black matte originals")
    candidates = require_list(item.get("candidates"), "black matte candidates")
    if len(originals) != 2 or len(candidates) != 6:
        raise PilotError("black matte 必须提供 2 个原始构图和 6 个候选")
    for original in originals:
        original_object = require_object(original, "black matte original")
        for field in ("master", "sourceSupersample"):
            verify_artifact_record(require_object(original_object.get(field), f"original {field}"), f"original {field}")
            artifact_count += 1
        for record in require_object(original_object.get("previews"), "original previews").values():
            verify_artifact_record(require_object(record, "original preview"), "original preview")
            artifact_count += 1
    ids: set[str] = set()
    role_gamma: set[tuple[str, float]] = set()
    for raw_candidate in candidates:
        candidate = require_object(raw_candidate, "black matte candidate")
        digest = candidate.get("candidateDigest")
        envelope = dict(candidate)
        envelope.pop("candidateDigest", None)
        if not isinstance(digest, str) or sha256_bytes(stable_bytes(envelope)) != digest:
            raise PilotError("black matte candidateDigest 不匹配")
        candidate_id = str(candidate.get("candidateId", ""))
        role = str(candidate.get("role", ""))
        gamma = float(candidate.get("gamma", -1))
        if candidate_id in ids or role not in ROLE_LABELS or gamma not in {0.5, 0.75, 1.0} or (role, gamma) in role_gamma:
            raise PilotError("black matte candidate id/role/gamma 非法")
        ids.add(candidate_id)
        role_gamma.add((role, gamma))
        verify_artifact_record(require_object(candidate.get("sourceSupersample"), "candidate source"), "candidate source")
        verify_artifact_record(require_object(candidate.get("sourceGeometrySvg"), "candidate SVG"), "candidate SVG")
        artifact_count += 2
        outputs = require_object(candidate.get("outputs"), "candidate outputs")
        if set(outputs) != {"supersample4096", "master512", "preview80", "preview48", "preview32"}:
            raise PilotError("black matte candidate 输出金字塔漂移")
        for record in outputs.values():
            verify_artifact_record(require_object(record, "candidate output"), "candidate output")
            artifact_count += 1
        metrics = require_object(candidate.get("metrics"), "candidate metrics")
        if float(metrics.get("blackCompositeMaximumAbsoluteError", 999)) > 2:
            raise PilotError("black matte 黑底合成误差超限")
    counts = require_object(dataset.get("counts"), "black matte counts")
    if counts != {"identityCount": 1, "originalCount": 2, "candidateCount": 6, "roleCount": 2, "recommendedCandidateCount": 2}:
        raise PilotError("black matte counts 不闭合")
    return artifact_count


def build(options: argparse.Namespace) -> dict[str, object]:
    source_root = pilot_batch(options.source_batch, "源批次", True)
    output_root = pilot_batch(options.output, "输出批次", False)
    parent = load_parent(source_root, options.review_key)
    output_root.mkdir(parents=False, exist_ok=False)
    candidates: list[dict[str, object]] = []
    try:
        for row in parent["rows"]:
            for code, gamma, label, description in VARIANTS:
                candidates.append(build_candidate(output_root, row, code, gamma, label, description))
        originals = []
        for row in parent["rows"]:
            originals.append({
                "role": row["role"],
                "roleLabel": ROLE_LABELS[str(row["role"])],
                "framingMode": row.get("framingMode"),
                "candidateSourceId": row.get("candidateId"),
                "frame": row.get("frame"),
                "master": row.get("master"),
                "previews": row.get("previews"),
                "sourceSupersample": row.get("sourceSupersample"),
            })
        reviewer_files = [artifact(path) for path in REVIEWER_FILES]
        parent_files = {name: artifact(path) for name, path in parent["paths"].items()}
        dataset: dict[str, object] = {
            "schema": DATA_SCHEMA,
            "phase": "BLACK_MATTE_HUMAN_REVIEW",
            "status": "black_matte_candidates_ready",
            "productionReady": False,
            "batchId": options.batch_id,
            "createdAt": utc_now(),
            "decisionSchema": DECISION_SCHEMA,
            "sourceDigest": parent["manifest"]["sourceDigest"],
            "parent": {
                "batchId": parent["manifest"]["batchId"],
                "manifestDigest": parent["manifest"]["manifestDigest"],
                "modelReportDigest": parent["model"]["reportDigest"],
                "renderDigest": parent["render"]["renderDigest"],
                "reviewDigest": parent["review"]["reviewDigest"],
                "receiptDigest": parent["receipt"]["receiptDigest"],
                "files": parent_files,
            },
            "policy": {
                "inputInterpretation": "straight RGBA whose visible effect was authored over black",
                "formula": "v=max(R,G,B)/255; m=v^gamma; A'=A*m; RGB'=RGB/m when m>0 else 0",
                "invariant": "premultiplied RGB over black remains equal within integer quantization",
                "applicationStage": "4096px retained supersample before 512/80/48/32 output pyramid",
                "resampling": "Pillow LANCZOS",
                "pillowVersion": PILLOW_VERSION,
                "numpyVersion": np.__version__,
                "variants": [
                    {"code": code, "gamma": gamma, "label": label, "description": description, "recommended": gamma == 0.75}
                    for code, gamma, label, description in VARIANTS
                ],
            },
            "reviewer": {
                "files": reviewer_files,
                "sourceClosureDigest": sha256_bytes(stable_bytes(reviewer_files)),
            },
            "counts": {
                "identityCount": 1,
                "originalCount": 2,
                "candidateCount": len(candidates),
                "roleCount": 2,
                "recommendedCandidateCount": sum(bool(candidate["recommended"]) for candidate in candidates),
            },
            "items": [{
                "reviewCode": "R14A",
                "reviewKey": options.review_key,
                "portraitRef": options.review_key.split("::", 1)[0],
                "variantKey": options.review_key.split("::", 1)[1],
                "category": "postprocess_black_matte",
                "humanDecision": parent["humanDecision"],
                "originals": originals,
                "candidates": candidates,
            }],
            "gates": {
                "onlyFrozenHumanPostprocessRow": True,
                "currentFrameRetained": True,
                "noModelCall": True,
                "exactFormulaRecorded": True,
                "highResolution4096Retained": True,
                "blackCompositeMaximumErrorLte2": True,
                "humanCandidateSelectionRequired": True,
                "productionWrites": False,
            },
        }
        dataset["datasetDigest"] = sha256_bytes(stable_bytes(dataset))
        write_json(output_root / DATA_NAME, dataset)
        artifact_count = verify_dataset(dataset)
    except Exception:
        # The fresh batch is retained as failure evidence; callers never overwrite it.
        raise
    return {
        "status": "black_matte_candidates_ready",
        "path": repo_rel(output_root / DATA_NAME),
        "datasetDigest": dataset["datasetDigest"],
        "candidates": len(candidates),
        "artifactCount": artifact_count,
    }


def check(options: argparse.Namespace) -> dict[str, object]:
    output_root = pilot_batch(options.output, "输出批次", True)
    dataset = require_object(load_json(output_root / DATA_NAME), "black matte dataset")
    artifact_count = verify_dataset(dataset)
    return {
        "status": "black_matte_candidates_verified",
        "datasetDigest": dataset["datasetDigest"],
        "candidates": dataset["counts"]["candidateCount"],
        "artifactCount": artifact_count,
    }


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("command", choices=["build", "check"])
    result.add_argument("--source-batch")
    result.add_argument("--output", required=True)
    result.add_argument("--batch-id")
    result.add_argument("--review-key", default=REVIEW_KEY)
    return result


def main() -> None:
    options = parser().parse_args()
    if options.command == "build":
        if not options.source_batch or not options.batch_id:
            raise PilotError("build 必须提供 --source-batch 与 --batch-id")
        if not options.batch_id.replace("-", "").replace("_", "").replace(".", "").isalnum() or len(options.batch_id) > 128:
            raise PilotError("batch id 非法")
        result = build(options)
    else:
        result = check(options)
    print(__import__("json").dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, PilotError, KeyError, ValueError, TypeError) as error:
        print(__import__("json").dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1) from error
