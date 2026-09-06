"""物品素材工作台内核。GUI 与 CLI 共用；只在显式请求时工作。"""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
STORE = ROOT / "tmp/asset-workbench"
JOBS = STORE / "jobs"
ICONS = "launcher/web/icons"
DRESS = "launcher/web/assets/dressup"
MAP = "data/items/asset_source_map.xml"
JOB_RE = re.compile(r"^[a-f0-9]{32}$")
KINDS = ("all", "icons", "dressup")
TERMINAL = ("ready", "failed", "cancelled", "applied", "reverted")
_modules: dict[str, Any] = {}


class WorkbenchError(Exception):
    pass


def read_json(path: Path, default=None):
    return json.loads(path.read_text(encoding="utf-8-sig")) if path.is_file() else default


def atomic_bytes(path: Path, data: bytes):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    try:
        with temporary.open("wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def json_bytes(value) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def write_json(path: Path, value):
    atomic_bytes(path, json_bytes(value))


def digest(path: Path):
    if not path.is_file():
        return None
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def safe_path(base: Path, relative: str) -> Path:
    if not isinstance(relative, str) or not relative or "\\" in relative or ":" in relative:
        raise WorkbenchError("资源路径不合法")
    path = base / relative
    if Path(relative).is_absolute() or ".." in Path(relative).parts:
        raise WorkbenchError("资源路径越界")
    resolved = path.resolve()
    if not resolved.is_relative_to(base.resolve()):
        raise WorkbenchError("资源路径越界")
    for parent in (path, *path.parents):
        if parent == base.parent:
            break
        if parent.is_symlink() or (hasattr(parent, "is_junction") and parent.is_junction()):
            raise WorkbenchError("素材任务路径不能经过链接目录")
    return path


def job_path(job_id: str) -> Path:
    if not isinstance(job_id, str) or not JOB_RE.fullmatch(job_id):
        raise WorkbenchError("任务编号不合法")
    return safe_path(ROOT, "tmp/asset-workbench/jobs/" + job_id)


def module(name: str):
    if name not in _modules:
        sys.path.insert(0, str(ROOT / "tools"))
        path = ROOT / "tools" / (name + ".py")
        spec = importlib.util.spec_from_file_location("asset_workbench_" + name.replace("-", "_"), path)
        loaded = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = loaded
        spec.loader.exec_module(loaded)
        _modules[name] = loaded
    return _modules[name]


def image_refs(value) -> set[str]:
    result: set[str] = set()
    if isinstance(value, dict):
        for key, item in value.items():
            if key in ("uri", "f1", "f2") and isinstance(item, str) and item.lower().endswith((".png", ".webp")):
                result.add(item)
            elif isinstance(item, (dict, list)):
                result.update(image_refs(item))
    elif isinstance(value, list):
        for item in value:
            result.update(image_refs(item))
    return result


def tool_environment():
    env = os.environ.copy()
    candidates = []
    if env.get("JAVA_HOME"):
        candidates.append(Path(env["JAVA_HOME"]) / "bin/java.exe")
    if shutil.which("java"):
        candidates.append(Path(shutil.which("java")))
    for prefix in (env.get("ProgramFiles", "C:/Program Files"), env.get("ProgramFiles(x86)", "C:/Program Files (x86)")):
        for pattern in ("Adobe/Adobe Animate */jre/bin/java.exe", "Eclipse Adoptium/*/bin/java.exe", "Java/*/bin/java.exe", "Common Files/Adobe/Adobe Flash CS6/jre/bin/java.exe"):
            candidates.extend(sorted(Path(prefix).glob(pattern), reverse=True))
    java = next((path for path in candidates if path.is_file()), None)
    if java:
        env["PATH"] = str(java.parent) + os.pathsep + env.get("PATH", "")
        # 64 位 Java 按需允许 2 GB 堆，避免大图标库转 XML 时在默认 1 GB 下耗尽。
        # 读取 PE machine，不启动额外 Java 进程；保留维护者显式指定的 FFDEC_MEMORY。
        try:
            with java.open("rb") as executable:
                executable.seek(0x3c)
                executable.seek(int.from_bytes(executable.read(4), "little"))
                header = executable.read(6)
            is_64bit = header[:4] == b"PE\x00\x00" and int.from_bytes(header[4:], "little") in (0x8664, 0xaa64)
            env.setdefault("FFDEC_MEMORY", "2048m" if is_64bit else "1024m")
        except OSError:
            pass
    env["PYTHONUTF8"] = "1"
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    ffdec = ROOT / "tools/ffdec/ffdec.bat"
    problems = []
    if java is None:
        problems.append("未找到 Java，请安装 Java 8 或更新版本，或设置 JAVA_HOME。")
    if not ffdec.is_file() or not (ffdec.parent / "ffdec.jar").is_file():
        problems.append("缺少 tools/ffdec 中的 FFDec 导出工具。")
    try:
        from PIL import features
        if not features.check("webp"):
            problems.append("当前 Pillow 不支持 WebP，请使用支持 WebP 的 Pillow。")
    except ImportError:
        problems.append("当前 Python 缺少 Pillow，请安装工具目录 requirements.txt 中的依赖。")
    return env, ffdec, {"ready": not problems, "problems": problems, "python": sys.executable, "java": str(java) if java else None}


def source_map_path():
    return STORE / "source-map.xml" if (STORE / "source-map.xml").is_file() else ROOT / MAP


def catalog():
    _, _, environment = tool_environment()
    if not environment["ready"]:
        return {"items": [], "environment": environment, "sourceMapPending": False, "jobs": recent_jobs()}
    icons = module("bake-icons-offline")
    dress = module("bake-dressup-offline")
    dress_items, _ = dress.load_items(ROOT, ("男", "女"))
    sources, conflicts = icons.parse_asset_map(source_map_path())
    icon_manifest = read_json(ROOT / ICONS / "manifest.json", {})
    dress_manifest = read_json(ROOT / DRESS / "manifest.json", {})
    rows = []
    listing = icons.xml_root(ROOT / "data/items/list.xml")
    tier_keys = icons.load_tier_keys(ROOT)
    for listed in listing.findall("items"):
        relative = (listed.text or "").strip()
        if not relative:
            continue
        item_file = safe_path(ROOT / "data/items", relative)
        for item in icons.xml_root(item_file).findall("item"):
            name = icons.child_text(item, "name")
            if not name:
                continue
            appearance = dress_items.get(name, {})
            icon_names = {icons.child_text(item, "icon")}
            for tier in tier_keys:
                if item.find(tier) is not None:
                    icon_names.add(icons.child_text(item.find(tier), "icon"))
            icon_names.discard("")
            icon_names.discard(None)
            skin_keys = sorted({value for fields in appearance.get("fieldsByGender", {}).values() for value in fields.values() if value})
            links = ["图标-" + key for key in sorted(icon_names)] + skin_keys
            missing_sources = [key for key in links if key not in sources and key not in conflicts]
            collision = [key for key in links if key in conflicts]
            missing_icons = [key for key in sorted(icon_names) if not image_refs(icon_manifest.get(key)) or any(not safe_path(ROOT / ICONS, uri).is_file() for uri in image_refs(icon_manifest.get(key))) ]
            missing_skins = [key for key in skin_keys if key in sources and (not dress_manifest.get("skinKeys", {}).get(key, {}).get("frames") or any(not safe_path(ROOT / DRESS, uri).is_file() for uri in image_refs(dress_manifest.get("skinKeys", {}).get(key, {}))))]
            libraries = sorted({sources[key].swf for key in links if key in sources}
                               | {source.swf for key in links for source in conflicts.get(key, [])})
            rows.append({"name": name, "displayName": icons.child_text(item, "displayname") or name,
                         "use": icons.child_text(item, "use"), "sourceFile": "data/items/" + relative,
                         "iconNames": sorted(icon_names), "skinKeys": skin_keys, "libraries": libraries,
                         "missingIcons": missing_icons, "missingSkins": missing_skins,
                         "missingSources": missing_sources, "conflicts": collision,
                         "appearance": appearance, "sample": any("3xd" in value.lower() for value in libraries)})
    return {"items": rows, "environment": environment, "manifestUrl": "assets/dressup/manifest.json",
            "sourceMapPending": digest(source_map_path()) != digest(ROOT / MAP), "jobs": recent_jobs()}


def select_item(name: str):
    for row in catalog()["items"]:
        if row["name"] == name:
            return row
    raise WorkbenchError("物品不在当前目录中，请刷新目录后重新选择。")


def recent_jobs():
    result = []
    if JOBS.is_dir():
        paths = sorted(JOBS.glob("*/job.json"), key=lambda path: path.stat().st_mtime, reverse=True)
        for path in paths[:20]:
            value = read_json(path, {})
            result.append({key: value.get(key) for key in ("jobId", "item", "state", "phase", "createdAt", "error")})
    return result


def status(job_id: str):
    value = read_json(job_path(job_id) / "job.json")
    if not value:
        raise WorkbenchError("任务不存在")
    return value


def refresh_status(job_id: str):
    """显式查询时识别已退出的 worker；没有常驻轮询或进程终止副作用。"""
    value = status(job_id)
    if value["state"] not in ("running", "queued"):
        return value
    age = time.time() - value.get("updatedAt", value.get("createdAt", time.time()))
    alive = None
    if os.name == "nt" and value.get("workerPid"):
        import ctypes
        from ctypes import wintypes
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        kernel.OpenProcess.restype = wintypes.HANDLE
        kernel.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        handle = kernel.OpenProcess(0x1000, False, value["workerPid"])
        if handle:
            code = wintypes.DWORD()
            if kernel.GetExitCodeProcess(handle, ctypes.byref(code)):
                alive = code.value == 259
            kernel.CloseHandle(handle)
        elif ctypes.get_last_error() == 87:
            alive = False
    if alive is False or (alive is None and age > 1200):
        return update(job_id, state="failed", phase="导出已中断，可重新生成", error="后台导出已退出或长时间未更新。现有项目图片未应用，请重新生成。")
    return value


def update(job_id: str, **values):
    job = status(job_id)
    job.update(values)
    job["updatedAt"] = time.time()
    write_json(job_path(job_id) / "job.json", job)
    return job


def cancelled(job_id: str):
    if (job_path(job_id) / "cancel").exists():
        raise WorkbenchError("任务已取消")


@contextmanager
def workspace_lock():
    safe_path(ROOT, "tmp/asset-workbench").mkdir(parents=True, exist_ok=True)
    lock_path = STORE / "writer.lock"
    with lock_path.open("a+b") as stream:
        if stream.tell() == 0:
            stream.write(b"0")
            stream.flush()
        stream.seek(0)
        try:
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise WorkbenchError("另一个素材任务正在写入，请稍后重试。")
        try:
            recover_transactions()
            yield
        finally:
            stream.seek(0)
            if os.name == "nt":
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(stream, fcntl.LOCK_UN)


def run_process(job_id: str, arguments: list[str], env):
    cancelled(job_id)
    folder = job_path(job_id)
    with (folder / "export.log").open("ab") as log:
        log.write(("\n" + subprocess.list2cmdline(arguments) + "\n").encode("utf-8"))
        log.flush()
        process = subprocess.Popen(arguments, cwd=ROOT, env=env, stdin=subprocess.DEVNULL,
                                   stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=(subprocess.CREATE_NO_WINDOW | subprocess.BELOW_NORMAL_PRIORITY_CLASS) if os.name == "nt" else 0)
        deadline = time.monotonic() + 900
        try:
            while process.poll() is None:
                cancelled(job_id)
                if time.monotonic() > deadline:
                    raise WorkbenchError("导出超过 15 分钟，请查看导出日志。")
                time.sleep(.2)
            if process.returncode:
                tail = (folder / "export.log").read_text(encoding="utf-8", errors="replace")[-2500:]
                raise WorkbenchError("导出失败，请查看诊断信息。\n" + tail)
        finally:
            if process.poll() is None:
                if os.name == "nt":
                    subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NO_WINDOW)
                else:
                    process.terminate()
                process.wait(timeout=10)


def start(item: str, kind: str = "all", job_id: str | None = None, detached=True):
    if kind not in KINDS:
        raise WorkbenchError("烘焙范围不合法")
    job_id = job_id or uuid.uuid4().hex
    folder = job_path(job_id)
    if (folder / "job.json").is_file():
        existing = status(job_id)
        if existing["item"] != item or existing["kind"] != kind:
            raise WorkbenchError("同一个任务编号不能用于不同的素材请求")
        return existing
    row = select_item(item)
    _, _, environment = tool_environment()
    if not environment["ready"]:
        raise WorkbenchError("\n".join(environment["problems"]))
    if row["conflicts"]:
        raise WorkbenchError("链接存在跨素材库冲突：" + "、".join(row["conflicts"]))
    if kind != "dressup" and any(key.startswith("图标-") for key in row["missingSources"]):
        raise WorkbenchError("缺少图标来源，请先重新扫描来源，并确认 Flash 导出链接及 SWF 已发布。")
    folder.mkdir(parents=True, exist_ok=False)
    job = {"schema": 1, "jobId": job_id, "item": item, "displayName": row["displayName"], "kind": kind,
           "createdAt": time.time(), "state": "queued", "phase": "等待导出", "selection": row}
    write_json(folder / "job.json", job)
    if detached:
        try:
            with (folder / "worker.log").open("ab") as log:
                process = subprocess.Popen([sys.executable, "-X", "utf8", "-B", str(Path(__file__).with_name("cli.py")), "run", "--job", job_id],
                    cwd=ROOT, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                    creationflags=(subprocess.CREATE_NO_WINDOW | subprocess.DETACHED_PROCESS | subprocess.BELOW_NORMAL_PRIORITY_CLASS) if os.name == "nt" else 0,
                    start_new_session=os.name != "nt")
        except Exception as error:
            update(job_id, state="failed", phase="无法启动导出", error=str(error))
            raise
    return status(job_id)


def snapshot(paths: set[str]):
    return {relative: digest(safe_path(ROOT, relative)) for relative in sorted(paths)}


def check_snapshot(expected, message):
    changed = [relative for relative, value in expected.items() if digest(safe_path(ROOT, relative)) != value]
    if changed:
        raise WorkbenchError(message + "：" + "、".join(changed[:6]))


def copy_refs(entry, source: Path, target: Path):
    for uri in image_refs(entry):
        path = safe_path(source, uri)
        if path.is_file():
            destination = safe_path(target, uri)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination)


def validate_images(entry, source: Path, require_origin=False):
    from PIL import Image
    refs = image_refs(entry)
    if not refs:
        raise WorkbenchError("所选素材没有生成图片")
    visible = False
    for uri in refs:
        with Image.open(safe_path(source, uri)) as image:
            image.verify()
        with Image.open(safe_path(source, uri)) as image:
            if image.width < 1 or image.height < 1 or image.width * image.height > 16777216:
                raise WorkbenchError("导出图片尺寸超出限制：" + uri)
            visible = visible or image.convert("RGBA").getbbox() is not None
    if not visible:
        raise WorkbenchError("所选素材导出的图片全部透明")
    if require_origin:
        def visit(value, parent_key=""):
            if isinstance(value, dict):
                # export 是文件摘要；实际配准点属于 frames / layers 中的帧。
                if "uri" in value and parent_key != "export" and not all(type(value.get(key)) in (int, float) and math.isfinite(value[key]) for key in ("width", "height", "originX", "originY")):
                    raise WorkbenchError("装扮帧缺少尺寸或注册点")
                for key, child in value.items():
                    visit(child, key)
            elif isinstance(value, list):
                for child in value:
                    visit(child, parent_key)
        visit(entry)


def rebase_preview(value, local: Path, base: str, fallback: str):
    result = copy.deepcopy(value)
    def visit(node):
        if isinstance(node, dict):
            for key, child in node.items():
                if key in ("uri", "f1", "f2") and isinstance(child, str) and child.lower().endswith((".png", ".webp")):
                    node[key] = (base if safe_path(local, child).is_file() else fallback) + child
                elif isinstance(child, (dict, list)):
                    visit(child)
        elif isinstance(node, list):
            for child in node:
                visit(child)
    visit(result)
    return result


def run(job_id: str):
    folder = job_path(job_id)
    job = status(job_id)
    if job["state"] != "queued":
        return job
    try:
        with workspace_lock():
            row = job["selection"]
            update(job_id, state="running", phase="检查来源与现有产物", workerPid=os.getpid())
            env, ffdec, _ = tool_environment()
            old_icons = read_json(ROOT / ICONS / "manifest.json", {})
            old_dress = read_json(ROOT / DRESS / "manifest.json", {})
            sources, _ = module("bake-icons-offline").parse_asset_map(source_map_path())
            names = row["iconNames"] if job["kind"] != "dressup" else []
            skins = [key for key in row["skinKeys"] if key in sources] if job["kind"] != "icons" else []
            if not names and not skins:
                raise WorkbenchError("所选范围没有可导出的素材")
            input_paths = {MAP, row["sourceFile"], "data/items/list.xml", "tools/asset_timeline_export.py",
                           "tools/bake-icons-offline.py", "tools/bake-dressup-offline.py", "tools/asset-workbench/core.py",
                           "tools/ffdec/ffdec.jar", "tools/ffdec/ffdec.bat"} | set(row["libraries"])
            baseline = snapshot({ICONS + "/manifest.json", DRESS + "/manifest.json", DRESS + "/report.json", MAP})
            inputs = snapshot(input_paths)
            if source_map_path() != ROOT / MAP:
                inputs.update(snapshot({source_map_path().relative_to(ROOT).as_posix()}))
            initial_assets = snapshot({path.relative_to(ROOT).as_posix()
                for base in (ROOT / ICONS, ROOT / DRESS / "skins")
                for path in base.rglob("*") if path.suffix.lower() in (".png", ".webp") and path.is_file()})
            shutil.copyfile(source_map_path(), folder / "source-map.xml")
            write_json(folder / "baseline.json", {"files": baseline, "inputs": inputs})
            raw_icons, raw_dress = folder / "preview/after/icons", folder / "preview/after/dressup"
            before_icons, before_dress = folder / "preview/before/icons", folder / "preview/before/dressup"
            write_json(raw_icons / "manifest.json", old_icons)
            write_json(raw_dress / "manifest.json", old_dress)
            for name in names:
                copy_refs(old_icons.get(name, {}), ROOT / ICONS, before_icons)
            for key in skins:
                copy_refs(old_dress.get("skinKeys", {}).get(key, {}), ROOT / DRESS, before_dress)
            if names:
                update(job_id, phase="烘焙图标与完整展示")
                args = [sys.executable, "-X", "utf8", "-B", str(ROOT / "tools/bake-icons-offline.py"), "--scope", "items",
                        "--output-dir", str(raw_icons), "--tmp-dir", str(folder / "scratch-icons"), "--report", str(folder / "icons-report.json"),
                        "--asset-map", str(folder / "source-map.xml"), "--ffdec", str(ffdec), "--force-overwrite-existing", "--export-animated-frames", "--strict"]
                for name in names:
                    args.extend(["--name", name])
                run_process(job_id, args, env)
            if skins:
                update(job_id, phase="烘焙人物装扮")
                args = [sys.executable, "-X", "utf8", "-B", str(ROOT / "tools/bake-dressup-offline.py"), "--export-assets", "--skip-basic-assets",
                        "--output-dir", str(raw_dress), "--tmp-dir", str(folder / "scratch-dressup"), "--asset-map", str(folder / "source-map.xml"), "--ffdec", str(ffdec)]
                for key in skins:
                    args.extend(["--name", key])
                run_process(job_id, args, env)
                report = read_json(raw_dress / "report.json", {}).get("assetExport", {})
                errors = {key: report.get(key) for key in ("missingSymbol", "symbolErrors", "exportErrors", "metadataErrors", "missingFrame", "timelineScriptErrors", "spriteGraphErrors", "missingNestedLayerFrame", "nestedLayerUnsupportedDescendants") if report.get(key)}
                if errors:
                    raise WorkbenchError("装扮导出没有完成：" + json.dumps(errors, ensure_ascii=False))
            update(job_id, phase="校验图片、帧和注册点")
            after_icons = read_json(raw_icons / "manifest.json", {})
            after_dress = read_json(raw_dress / "manifest.json", {})
            selected_icons = {name: after_icons[name] for name in names if name in after_icons}
            selected_skins = {key: after_dress.get("skinKeys", {}).get(key, {}) for key in skins}
            if len(selected_icons) != len(names):
                raise WorkbenchError("部分图标未生成")
            for entry in selected_icons.values():
                validate_images(entry, raw_icons)
            for entry in selected_skins.values():
                if not entry.get("export") or not entry.get("frames"):
                    raise WorkbenchError("装扮索引存在，但没有生成可用帧")
                validate_images(entry, raw_dress, True)
            check_snapshot(inputs, "导出期间来源发生变化，请重新生成")
            check_snapshot(baseline, "导出期间项目图片清单发生变化，请重新生成")
            result = {"icons": selected_icons, "skins": selected_skins, "item": after_dress.get("items", {}).get(row["name"], row["appearance"])}
            write_json(folder / "result.json", result)
            merged_dress = copy.deepcopy(old_dress)
            merged_dress.setdefault("skinKeys", {}).update(selected_skins)
            merged_dress.setdefault("items", {})[row["name"]] = result["item"]
            for label, icon_data, dress_data, local_icons, local_dress in (
                ("before", {name: old_icons.get(name, {}) for name in row["iconNames"]}, old_dress, before_icons, before_dress),
                ("after", {name: selected_icons.get(name, old_icons.get(name, {})) for name in row["iconNames"]}, merged_dress, raw_icons, raw_dress)):
                base = "https://asset-workbench.local/" + job_id + "/preview/" + label + "/"
                write_json(folder / ("preview/" + label + "/view.json"), {
                    "icons": rebase_preview(icon_data, local_icons, base + "icons/", "https://overlay.local/icons/"),
                    "dressup": rebase_preview(dress_data, local_dress, base + "dressup/", "https://overlay.local/assets/dressup/")})
            output_paths = {ICONS + "/" + uri for entry in selected_icons.values() for uri in image_refs(entry)}
            output_paths.update(DRESS + "/" + uri for entry in selected_skins.values() for uri in image_refs(entry))
            old_paths = {ICONS + "/" + uri for name in names for uri in image_refs(old_icons.get(name, {}))}
            old_paths.update(DRESS + "/" + uri for key in skins for uri in image_refs(old_dress.get("skinKeys", {}).get(key, {})))
            baseline.update({path: initial_assets.get(path) for path in output_paths | old_paths})
            check_snapshot(baseline, "导出期间项目产物发生变化，请重新生成")
            candidate_paths = {"result.json", "source-map.xml"}
            candidate_paths.update("preview/after/icons/" + uri for entry in selected_icons.values() for uri in image_refs(entry))
            candidate_paths.update("preview/after/dressup/" + uri for entry in selected_skins.values() for uri in image_refs(entry))
            candidates = {path: digest(safe_path(folder, path)) for path in candidate_paths}
            write_json(folder / "baseline.json", {"files": baseline, "inputs": inputs, "candidates": candidates})
            return update(job_id, state="ready", phase="预览已就绪", iconCount=len(names), skinCount=len(skins),
                          previewRoot="https://asset-workbench.local/" + job_id + "/preview/",
                          warnings=["无对应来源的装扮将沿用现有基本款：" + "、".join(row["missingSources"])] if row["missingSources"] else [])
    except Exception as error:
        return update(job_id, state="cancelled" if (folder / "cancel").exists() else "failed", phase="已取消" if (folder / "cancel").exists() else "生成失败", error=str(error))


def restore_transaction(folder: Path, transaction, final_state="rolled_back"):
    for record in transaction["files"]:
        current = digest(safe_path(ROOT, record["path"]))
        if current not in (record["before"], record["after"]):
            raise WorkbenchError("项目在写入中断后被其他工具修改，保留现场：" + record["path"])
    for record in reversed(transaction["files"]):
        path = safe_path(ROOT, record["path"])
        if record["before"] is None:
            path.unlink(missing_ok=True)
        else:
            atomic_bytes(path, safe_path(folder / "backup", record["path"]).read_bytes())
    transaction["state"] = final_state
    write_json(folder / "transaction.json", transaction)


def recover_transactions():
    if not JOBS.is_dir():
        return
    for path in JOBS.glob("*/transaction.json"):
        transaction = read_json(path)
        if transaction.get("state") == "applying":
            restore_transaction(path.parent, transaction)
            update(path.parent.name, state="ready", phase="上次写入已恢复，可重新应用")
        elif transaction.get("state") == "undoing":
            restore_transaction(path.parent, transaction, "reverted")
            update(path.parent.name, state="reverted", phase="已恢复中断的撤回")
        elif transaction.get("state") == "applied" and status(path.parent.name)["state"] == "ready":
            update(path.parent.name, state="applied", phase="已应用到项目", changedFiles=[record["path"] for record in transaction["files"]])
        elif transaction.get("state") == "reverted" and status(path.parent.name)["state"] == "applied":
            update(path.parent.name, state="reverted", phase="已撤回本次应用")


def apply(job_id: str, undo=False):
    folder = job_path(job_id)
    with workspace_lock():
        job = status(job_id)
        if undo:
            if job["state"] == "reverted":
                return job
            transaction = read_json(folder / "transaction.json")
            if job["state"] != "applied" or not transaction:
                raise WorkbenchError("这个任务没有可撤回的应用结果")
            for record in transaction["files"]:
                if digest(safe_path(ROOT, record["path"])) != record["after"]:
                    raise WorkbenchError("应用后素材已再次变化，不能覆盖后续修改：" + record["path"])
            transaction["state"] = "undoing"
            write_json(folder / "transaction.json", transaction)
            restore_transaction(folder, transaction, "reverted")
            return update(job_id, state="reverted", phase="已撤回本次应用")
        if job["state"] == "applied":
            return job
        if job["state"] != "ready":
            raise WorkbenchError("只有通过检查的候选才能应用")
        baseline = read_json(folder / "baseline.json")
        check_snapshot(baseline["inputs"], "来源已变化，请重新生成")
        check_snapshot(baseline["files"], "项目产物已变化，请重新生成")
        if any(digest(safe_path(folder, path)) != value for path, value in baseline["candidates"].items()):
            raise WorkbenchError("候选文件已变化，请重新生成")
        result = read_json(folder / "result.json")
        icon_manifest = read_json(ROOT / ICONS / "manifest.json", {})
        dress_manifest = read_json(ROOT / DRESS / "manifest.json", {})
        files: dict[str, bytes | None] = {}
        previous_refs = set()
        for name, entry in result["icons"].items():
            previous_refs.update(ICONS + "/" + uri for uri in image_refs(icon_manifest.get(name, {})))
            validate_images(entry, folder / "preview/after/icons")
            icon_manifest[name] = entry
            for uri in image_refs(entry):
                files[ICONS + "/" + uri] = safe_path(folder / "preview/after/icons", uri).read_bytes()
        for key, entry in result["skins"].items():
            previous_refs.update(DRESS + "/" + uri for uri in image_refs(dress_manifest.get("skinKeys", {}).get(key, {})))
            validate_images(entry, folder / "preview/after/dressup", True)
            dress_manifest.setdefault("skinKeys", {})[key] = entry
            for uri in image_refs(entry):
                files[DRESS + "/" + uri] = safe_path(folder / "preview/after/dressup", uri).read_bytes()
        if result["skins"]:
            dress_manifest.setdefault("items", {})[job["item"]] = result["item"]
        live_refs = {ICONS + "/" + uri for uri in image_refs(icon_manifest)} | {DRESS + "/" + uri for uri in image_refs(dress_manifest)}
        for relative in previous_refs - live_refs:
            files[relative] = None
        if result["icons"]:
            files[ICONS + "/manifest.json"] = json_bytes(icon_manifest)
        if result["skins"]:
            files[DRESS + "/manifest.json"] = json_bytes(dress_manifest)
            report = read_json(ROOT / DRESS / "report.json", {})
            module("bake-dressup-offline").attach_animation_summary(dress_manifest, report)
            report["workbenchUpdate"] = {"jobId": job_id, "item": job["item"], "skinKeys": list(result["skins"]), "validation": "selected_images_frames_origins"}
            files[DRESS + "/report.json"] = json_bytes(report)
        files[MAP] = (folder / "source-map.xml").read_bytes()
        records = []
        for relative, content in files.items():
            path = safe_path(ROOT, relative)
            before = digest(path)
            after = hashlib.sha256(content).hexdigest() if content is not None else None
            if before == after:
                continue
            if before is not None:
                backup = safe_path(folder / "backup", relative)
                backup.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, backup)
            records.append({"path": relative, "before": before, "after": after})
        transaction = {"state": "applying", "files": records}
        write_json(folder / "transaction.json", transaction)
        try:
            for record in records:
                path = safe_path(ROOT, record["path"])
                content = files[record["path"]]
                if content is None:
                    path.unlink(missing_ok=True)
                else:
                    atomic_bytes(path, content)
            transaction["state"] = "applied"
            write_json(folder / "transaction.json", transaction)
        except Exception:
            restore_transaction(folder, transaction)
            raise
        return update(job_id, state="applied", phase="已应用到项目", changedFiles=[record["path"] for record in records])


def rescan():
    with workspace_lock():
        scanner = module("linkage_scanner/scan_linkage")
        scanner.results.clear()
        scanner.source_counts.clear()
        temporary = STORE / ("source-map-" + uuid.uuid4().hex + ".xml")
        scanner.OUTPUT_XML = str(temporary)
        scanner.XML_ONLY = True
        from contextlib import redirect_stdout
        with (STORE / "scan.log").open("w", encoding="utf-8") as log, redirect_stdout(log):
            scanner.main()
        os.replace(temporary, STORE / "source-map.xml")
    return catalog()


def api(request):
    if not isinstance(request, dict) or set(request) - {"op", "item", "kind", "jobId"}:
        raise WorkbenchError("请求格式不合法")
    op = request.get("op")
    fields = {"catalog": set(), "rescan": set(), "start": {"item", "kind", "jobId"},
              "status": {"jobId"}, "apply": {"jobId"}, "undo": {"jobId"}, "cancel": {"jobId"}}
    if op not in fields or set(request) - {"op"} - fields[op]:
        raise WorkbenchError("请求包含不支持的操作或参数")
    if op == "catalog":
        return catalog()
    if op == "rescan":
        return rescan()
    if op == "start":
        return start(request.get("item"), request.get("kind", "all"), request.get("jobId"))
    if op == "status":
        return refresh_status(request.get("jobId"))
    if op == "apply":
        return apply(request.get("jobId"))
    if op == "undo":
        return apply(request.get("jobId"), True)
    if op == "cancel":
        job = refresh_status(request.get("jobId"))
        if job["state"] in TERMINAL:
            return job
        atomic_bytes(job_path(request["jobId"]) / "cancel", b"cancel")
        return status(request["jobId"])
    raise WorkbenchError("未知的素材操作")
