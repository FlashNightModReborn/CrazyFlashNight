"""Sample the two editable instructor melee timelines with the Animate authoring engine."""
from pathlib import Path
from tempfile import TemporaryDirectory, NamedTemporaryFile
import argparse
import hashlib
import json
import math
import os
import shutil
import subprocess
import time

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parents[1] / "flashswf/arts/new/Codex素材源稿/CF6教官-近战250"
PROJECT = SOURCE / "编辑工程"
CACHE = SOURCE / "native-poses.json"
SAMPLER = HERE / "sample_instructor_melee.jsfl"
ACTION_NAMES = ("匕首刺击", "持盾匕首刺击")
FORMAT = 1


def project_files(project):
    return [project / "教官近战.xfl", project / "DOMDocument.xml",
            *sorted((project / "LIBRARY").rglob("*.xml"))]


def input_paths():
    return [Path(__file__), SAMPLER, SOURCE / "origin.json", CACHE, *project_files(PROJECT)]


def signature(project):
    """Bind authoring files and the JSFL that evaluates them, independent of checkout path."""
    digest = hashlib.sha256()
    for path in [*project_files(project), SAMPLER]:
        key = ("@sampler" if path == SAMPLER else path.relative_to(project).as_posix())
        digest.update(key.encode("utf-8") + b"\0")
        digest.update(hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).digest())
    return digest.hexdigest()


def read_cache(project=PROJECT, cache=CACHE):
    report = json.loads(cache.read_text(encoding="utf-8"))
    if report.get("format") != FORMAT or report.get("sourceSignature") != signature(project):
        raise ValueError("教官近战取样已过期，请保存美术 XFL 后运行 instructor_melee_source.py --bake")
    validate(report)
    return report


def layer_names():
    return {key: action["layers"] for key, action in read_cache()["actions"].items()}


def load_poses():
    result = {}
    for name, action in read_cache()["actions"].items():
        poses = []
        for frame in action["poses"]:
            pose = {}
            for depth, part, matrix, percentages, offsets in frame:
                pose[str(depth)] = {"id":part, "matrix":matrix,
                                    "colorMult":[value * 2.56 for value in percentages],
                                    "colorAdd":offsets}
            poses.append(pose)
        result[name] = poses
    return result


def validate(report):
    if report.get("error"):
        raise ValueError(f'Animate JSFL 第 {report.get("line")} 行：{report["error"]}')
    if report.get("frameRate") != 30 or set(report.get("actions", {})) != set(ACTION_NAMES):
        raise ValueError("Expected both 30 fps authoring timelines")
    for name in ACTION_NAMES:
        action = report["actions"][name]
        if not action["poses"] or not action["layers"]:
            raise ValueError(f"{name}: empty timeline")
        if not any(action["poses"]):
            raise ValueError(f"{name}: no artwork")
        for i, rows in enumerate(action["poses"], 1):
            seen = set()
            for depth, part, matrix, colors, offsets in rows:
                if (depth in seen or str(depth) not in action["layers"] or not isinstance(part, int)
                        or len(matrix) != 6 or len(colors) != 4 or len(offsets) != 4
                        or not all(math.isfinite(x) for x in matrix + colors + offsets)):
                    raise ValueError(f"{name} frame {i}: invalid native pose at depth {depth}")
                seen.add(depth)


def bake(project, cache, animate_path):
    project = project.resolve()
    original = signature(project)
    if not animate_path.is_file():
        raise FileNotFoundError(f"找不到 Animate，请用 --animate 指定 Animate.exe：{animate_path}")
    with TemporaryDirectory(prefix="cf6-instructor-") as temp:
        scratch = Path(temp)
        copy = scratch / "source"
        for source in project_files(project):
            target = copy / source.relative_to(project)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        if signature(copy) != original:
            raise ValueError("Source changed while preparing the scratch copy")
        result = scratch / "native.json"
        script = scratch / "sample.jsfl"
        code = SAMPLER.read_text(encoding="utf-8")
        for key, path in (("__PROJECT_URI__", copy / "教官近战.xfl"), ("__RESULT_URI__", result)):
            code = code.replace(key, json.dumps(path.as_uri()))
        script.write_text(code, encoding="utf-8-sig")
        subprocess.Popen([str(animate_path), str(script)], creationflags=subprocess.CREATE_NO_WINDOW)
        end = time.monotonic() + 300
        while time.monotonic() < end:
            if result.exists():
                try:
                    report = json.loads(result.read_text(encoding="utf-8-sig"))
                    break
                except json.JSONDecodeError:
                    pass
            time.sleep(0.25)
        else:
            raise TimeoutError("Adobe Animate 未在 300 秒内返回取样，请检查其窗口与 JSFL 执行权限")
    validate(report)
    if signature(project) != original:
        raise ValueError("源稿在取样期间发生变化，请重新取样")
    report.update(format=FORMAT, sourceSignature=original)
    cache.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile("w", encoding="utf-8", newline="\n", dir=cache.parent, delete=False) as out:
        tmp = Path(out.name)
        json.dump(report, out, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
        out.write("\n")
    try:
        tmp.replace(cache)
    finally:
        tmp.unlink(missing_ok=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bake", action="store_true", help="调用 Animate 重采样；省略则只校验现有取样")
    parser.add_argument("--project", type=Path, default=PROJECT)
    parser.add_argument("--cache", type=Path, default=CACHE)
    parser.add_argument("--animate", type=Path, default=Path(os.environ.get("ProgramFiles", "C:/Program Files"))
                        / "Adobe/Adobe Animate 2024/Animate.exe")
    args = parser.parse_args()
    if args.bake:
        bake(args.project, args.cache, args.animate)
    report = read_cache(args.project, args.cache)
    for action, info in report["actions"].items():
        print(f"{action}：{len(info['poses'])} 帧，判定标记 {[m['frame'] for m in info['hitMarkers']]}")
