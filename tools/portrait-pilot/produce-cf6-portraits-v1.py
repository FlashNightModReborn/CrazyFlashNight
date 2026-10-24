#!/usr/bin/env python3
"""Reproduce the approved CF6 session portraits and preserve the accepted base pack."""
from __future__ import annotations

import argparse
import copy
import datetime as dt
import hashlib
import importlib.util
import io
import json
import lzma
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from PIL import Image, __version__ as PILLOW_VERSION

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "tools/portrait-pilot/evidence/cf6-portraits-20261024"
OUTPUT = ROOT / "launcher/web/assets/enemy-portraits"
SESSION_ID = "4f96187d-7088-4480-8b59-a92889fb7bcf"
KEY = "cf6SupplementalPromotion"
JK_REF = "敌人-武装JK"
NEW_REFS = {
    "敌人-延寿克隆兽", "敌人-完全体克隆兽", "敌人-CF6普通男僵尸", "敌人-CF6女僵尸",
    "敌人-CF6蛮蛮", "敌人-CF6Wings", "敌人-CF6大刀机器人", "敌人-CF6特种兵",
    "敌人-CF6持盾特种兵", "敌人-CF6光头保安", "敌人-CF6变身光头保安",
    "敌人-CF6大头机器人", "敌人-CF6老头人形", "敌人-CF6老头机器人",
}
NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", NS)
ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")
ET.register_namespace("ffdec", "https://www.free-decompiler.com/flash")


def sha(blob):
    return hashlib.sha256(blob).hexdigest().upper()


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def seal(value, field):
    result = copy.deepcopy(value)
    result.pop(field, None)
    result[field] = sha(json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8"))
    return result


def digest(value, field):
    if seal(value, field)[field] != value.get(field):
        raise ValueError(field + " drift")


def artifact(path):
    return {"path": path.relative_to(ROOT).as_posix(), "bytes": path.stat().st_size, "sha256": sha(path.read_bytes())}


def verify(record):
    path = (ROOT / record["path"]).resolve() if "path" in record else (ROOT / "launcher/web" / record["url"]).resolve()
    actual = artifact(path)
    if (not path.is_relative_to(ROOT) or actual["bytes"] != record.get("bytes")
            or actual["sha256"] != record.get("sha256")
            or ("path" in record and actual["path"] != record["path"])):
        raise ValueError("artifact drift: " + record.get("path", record.get("url", "unknown")))
    return path


def archive(record, expected_sha):
    blob = lzma.decompress(verify(record).read_bytes())
    if sha(blob) != expected_sha:
        raise ValueError("decompressed source drift")
    return blob


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


def png_bytes(image):
    stream = io.BytesIO()
    image.save(stream, format="PNG", optimize=True)
    return stream.getvalue()


def source():
    config = read(EVIDENCE / "source.json")
    approval = read(EVIDENCE / "authorization.json")
    if (config.get("schema") != "cf7.cf6-portrait-source.v1" or config.get("sessionId") != SESSION_ID
            or config.get("pillowVersion") != PILLOW_VERSION):
        raise ValueError("CF6 source schema or renderer environment drift")
    if (approval.get("schema") != "cf7.session-portrait-authorization.v1"
            or approval.get("sessionId") != SESSION_ID
            or approval.get("commitPushAuthorized") is not True
            or approval.get("formalRuntimeDeploymentAuthorized") is not False):
        raise ValueError("session authorization drift")
    rows = config.get("rows", [])
    if len(rows) != 16 or {row["portraitRef"] for row in rows if row["variantKey"] == "default"} != NEW_REFS:
        raise ValueError("CF6 identity set drift")
    if {row["variantKey"] for row in rows if row["portraitRef"] == JK_REF} != {"orange", "white"}:
        raise ValueError("JK variant set drift")
    if len(config["baseSubjectNames"]) != 468 or set(config["retiredSubjectNames"]) != {
        "60cf604a61ae0020eefe3b24.svg", "2cb06417f3ba1fb064c4f84d.svg", "01296094a01d3e054e8b6ff5.png"
    }:
        raise ValueError("base subject closure drift")
    for path in config["exporters"].values():
        verify(path)
    verify(config["reviewReport"])
    for row in rows:
        verify(row["sourceSwf"])
        if row["frame"] < 1 or row["zoom"] != 16:
            raise ValueError("native frame or zoom drift")
        if row["portraitRef"] == JK_REF:
            verify(row["previousSubjects"]["svg"])
            verify(row["previousSubjects"]["pngFallback"])
    return config


def crop_svg(blob, crop):
    root = ET.fromstring(blob)
    if root.findall(".//{" + NS + "}image"):
        raise ValueError("native SVG must not embed a bitmap")
    empty = []
    for node in root.iter():
        for key, value in node.attrib.items():
            if key.endswith("href") and not value.startswith("#"):
                raise ValueError("external SVG dependency")
        if node.tag == "{" + NS + "}filter" and not len(node):
            empty.append(node)
    for node in empty:
        ident = node.get("id")
        for owner in root.iter():
            if owner.get("filter") == "url(#" + ident + ")":
                owner.attrib.pop("filter")
            if node in list(owner):
                owner.remove(node)
    x, y, right, bottom = crop
    side = right - x
    root.set("width", "512")
    root.set("height", "512")
    root.set("viewBox", f"{x} {y} {side} {side}")
    root.set("overflow", "hidden")
    return ET.tostring(root, encoding="utf-8")


def derived(row):
    frame = Image.open(io.BytesIO(archive(row["pngArchive"], row["pngSha256"]))).convert("RGBA")
    crop = row["cropPixels"]
    x, y, right, bottom = crop
    side = right - x
    if (side != bottom - y or side <= 0 or side > 4096
            or x < 0 or y < 0 or right > frame.width or bottom > frame.height):
        raise ValueError("native crop bounds")
    image = frame.crop(crop).resize((512, 512), Image.Resampling.LANCZOS)
    if not image.getchannel("A").getbbox() or image.getchannel("A").getextrema() != (0, 255):
        raise ValueError("crop alpha")
    vector = crop_svg(archive(row["svgArchive"], row["svgSha256"]), crop)
    return image, vector


def vector_record(blob, crop):
    x, y, right, bottom = crop
    return {
        "url": "assets/enemy-portraits/subjects/" + sha(blob)[:24].lower() + ".svg",
        "bytes": len(blob), "sha256": sha(blob), "viewBox": [x, y, right - x, bottom - y],
        "flipX": False, "embeddedRasterCount": 0, "isRasterHeavy": False,
        "runtimeAllowed": True, "convolutionFilterCount": 0,
    }


def raster_record(blob, image):
    return {
        "url": "assets/enemy-portraits/subjects/" + sha(blob)[:24].lower() + ".png",
        "bytes": len(blob), "sha256": sha(blob), "size": [512, 512],
        "alphaExtrema": [0, 255], "visibleBounds": list(image.getchannel("A").getbbox()),
    }


def provenance(row, config):
    result = {
        "reviewKey": row["portraitRef"] + "::" + row["variantKey"],
        "resolution": "user_authorized_session_native_art_crop",
        "decisionStatus": "explicit_user_authorized_integration",
        "orientationAction": "keep", "orientationSource": "native_source_orientation_reviewed_in_session",
        "rasterOrientationTransform": "none", "sessionId": SESSION_ID,
        "authorization": artifact(EVIDENCE / "authorization.json"),
        "sourceEvidence": artifact(EVIDENCE / "source.json"),
        "sourceSwf": row["sourceSwf"], "spriteId": row["spriteId"], "frame": row["frame"],
        "zoom": row["zoom"], "cropPixels": row["cropPixels"],
        "formalRuntimeDeploymentAuthorized": False,
    }
    if row["portraitRef"] == JK_REF:
        result.update(resolution="user_authorized_session_variant_repair", repairNote=row["repairNote"],
                      previousProvenance=row["previousProvenance"])
    return result


def render_data(write_files=False):
    config = source()
    entries, jk_variants, files = {}, {}, {}
    subjects = EVIDENCE / "subjects"
    if write_files:
        subjects.mkdir(exist_ok=True)
    for row in config["rows"]:
        image, vector = derived(row)
        svg_blob = vector
        svg_record = vector_record(svg_blob, row["cropPixels"])
        if row.get("reusePng"):
            png_record = copy.deepcopy(row["reusePng"])
        else:
            raster = png_bytes(image)
            png_record = raster_record(raster, image)
            files[Path(png_record["url"]).name] = raster
        files[Path(svg_record["url"]).name] = svg_blob
        if write_files:
            for record in (svg_record, png_record):
                name = Path(record["url"]).name
                if name in files:
                    (subjects / name).write_bytes(files[name])
        subject = {"preferredFormat": row["preferredFormat"], "svg": svg_record, "pngFallback": png_record}
        variant = {"status": "human_accepted", "subject": subject, "provenance": provenance(row, config)}
        if row["portraitRef"] == JK_REF:
            if row.get("legacyUrl"):
                variant["legacyUrl"] = row["legacyUrl"]
            jk_variants[row["variantKey"]] = variant
        else:
            entries[row["portraitRef"]] = {
                "portraitRef": row["portraitRef"], "petIds": [], "enemyIds": [row["portraitRef"]],
                "status": "ready", "defaultVariant": "default",
                "variants": {"default": variant},
            }
    inputs = {name: artifact(path) for name, path in {
        "source": EVIDENCE / "source.json", "authorization": EVIDENCE / "authorization.json",
        "controller": Path(__file__), "previousVerifier": ROOT / "tools/portrait-pilot/promote-dog-portraits-v1.py",
        "sharedPublisher": ROOT / "tools/portrait-pilot/promote-enemy-portraits-v1.py",
    }.items()}
    data = seal({"schema": "cf7.cf6-portrait-render.v1", "pillowVersion": PILLOW_VERSION,
                 "inputs": inputs, "entries": entries, "jkVariants": jk_variants,
                 "newSubjectNames": sorted(files)}, "renderDigest")
    if write_files:
        write(EVIDENCE / "render-report.json", data)
    return data, files


def counts(base):
    result = copy.deepcopy(base["counts"])
    for key in ("identityCount", "variantCount", "humanAcceptedIdentityCount", "humanAcceptedVariantCount"):
        result[key] += 14
    result["cf6SupplementalIdentityCount"] = 14
    return result


def expected_closure(base):
    return seal({
        "schema": "cf7.cf6-portrait-supplement.v1", "status": "session_native_art_integrated",
        "sessionId": SESSION_ID, "baseManifest": artifact(EVIDENCE / "base-manifest.json"),
        "baseReceipt": artifact(EVIDENCE / "base-promotion-receipt.json"),
        "renderReport": artifact(EVIDENCE / "render-report.json"),
        "portraitRefs": sorted(NEW_REFS), "jkVariants": ["orange", "white"],
        "baseManifestDigest": base["manifestDigest"],
        "historicalCampaignEvidence": "preserved_without_recertification",
    }, "closureDigest")


def verify_prior(live_root):
    config = source()
    (ROOT / "tmp").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="cf6-portrait-prior-", dir=ROOT / "tmp") as temporary:
        temp = Path(temporary)
        (temp / "subjects").mkdir()
        retired = set(config["retiredSubjectNames"])
        for name in config["baseSubjectNames"]:
            if Path(name).name != name:
                raise ValueError("subject path escape")
            source_path = live_root / "subjects" / name
            if source_path.exists():
                os.link(source_path, temp / "subjects" / name)
            elif name in retired:
                shutil.copyfile(EVIDENCE / "retired-subjects" / name, temp / "subjects" / name)
            else:
                raise ValueError("base subject missing: " + name)
        for name in ("manifest.json", "promotion-receipt.json"):
            shutil.copyfile(EVIDENCE / ("base-" + name), temp / name)
        previous = module(ROOT / "tools/portrait-pilot/promote-dog-portraits-v1.py", "cf6_prior_dog_verifier")
        previous.check_manifest(temp / "manifest.json", logical_output=OUTPUT)


def receipt_for(value, path, logical_output):
    receipt = read(EVIDENCE / "base-promotion-receipt.json")
    receipt.update(counts=value["counts"], generatedAt=value["generatedAt"],
                   manifestDigest=value["manifestDigest"],
                   cf6SupplementalClosureDigest=value[KEY]["closureDigest"],
                   manifest={"path": (logical_output / "manifest.json").relative_to(ROOT).as_posix(),
                             "bytes": path.stat().st_size, "sha256": sha(path.read_bytes())})
    return seal(receipt, "receiptDigest")


def check_manifest(path, *, logical_output=None):
    value = read(path)
    digest(value, "manifestDigest")
    base = read(EVIDENCE / "base-manifest.json")
    data, files = render_data()
    if read(EVIDENCE / "render-report.json") != data:
        raise ValueError("CF6 render inputs or pixels drift")
    closure = value.get(KEY, {})
    if closure != expected_closure(base):
        raise ValueError("CF6 supplement closure drift")
    if set(value) != set(base) | {KEY} or set(value["entries"]) != set(base["entries"]) | NEW_REFS:
        raise ValueError("bounded CF6 delta contract")
    for ref, entry in base["entries"].items():
        if ref != JK_REF and value["entries"][ref] != entry:
            raise ValueError("prior accepted identity changed: " + ref)
    for key, prior in base.items():
        if key not in {"entries", "counts", "generatedAt", "manifestDigest"} and value[key] != prior:
            raise ValueError("prior manifest contract changed: " + key)
    if value["counts"] != counts(base):
        raise ValueError("CF6 count drift")
    for ref in NEW_REFS:
        if value["entries"][ref] != data["entries"][ref]:
            raise ValueError("CF6 entry drift: " + ref)
    actual_jk = value["entries"][JK_REF]
    original_jk = base["entries"][JK_REF]
    if set(actual_jk) != set(original_jk) or actual_jk["defaultVariant"] != "orange":
        raise ValueError("JK entry contract drift")
    for key in ("portraitRef", "petIds", "enemyIds", "status"):
        if actual_jk[key] != original_jk[key]:
            raise ValueError("JK identity drift")
    if actual_jk["variants"] != data["jkVariants"]:
        raise ValueError("JK corrected variant drift")
    config = source()
    expected_files = (set(config["baseSubjectNames"]) - set(config["retiredSubjectNames"])) | set(files)
    if {path.name for path in (path.parent / "subjects").iterdir()} != expected_files:
        raise ValueError("live subject fileset drift")
    for name, blob in files.items():
        if (path.parent / "subjects" / name).read_bytes() != blob:
            raise ValueError("subject bytes drift: " + name)
        if (EVIDENCE / "subjects" / name).read_bytes() != blob:
            raise ValueError("immutable CF6 subject drift: " + name)
    verify_prior(path.parent)
    units = read(ROOT / "data/units/units.json")
    for row in config["rows"]:
        unit = next((item for item in units if item["id"] == row["unitId"]), None)
        if not unit or unit["spritename"] != row["portraitRef"]:
            raise ValueError("unit portrait identity drift: " + row["portraitRef"])
    receipt = read(path.parent / "promotion-receipt.json")
    expected_receipt = receipt_for(value, path, logical_output or path.parent)
    if receipt != expected_receipt:
        raise ValueError("manifest-last receipt drift")
    return value


def build_manifest(live):
    data, files = render_data()
    if read(EVIDENCE / "render-report.json") != data:
        raise ValueError("run render before promote")
    base = read(EVIDENCE / "base-manifest.json")
    value = copy.deepcopy(base)
    value["entries"].update(data["entries"])
    value["entries"][JK_REF]["variants"].update(data["jkVariants"])
    value["counts"] = counts(base)
    value[KEY] = expected_closure(base)
    value["generatedAt"] = live.get("generatedAt") if KEY in live else dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
    return seal(value, "manifestDigest"), files


def promote():
    live = read(OUTPUT / "manifest.json")
    if KEY not in live and ((OUTPUT / "manifest.json").read_bytes() != (EVIDENCE / "base-manifest.json").read_bytes()
            or (OUTPUT / "promotion-receipt.json").read_bytes() != (EVIDENCE / "base-promotion-receipt.json").read_bytes()):
        raise ValueError("unknown live base; refuse overwrite")
    value, files = build_manifest(live)
    if value == live:
        check_manifest(OUTPUT / "manifest.json")
        print("Already integrated")
        return
    verify_prior(OUTPUT)
    work = ROOT / "tmp/cf6-portraits"
    work.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix="staging-", dir=work))
    shutil.copytree(OUTPUT, stage, dirs_exist_ok=True)
    for name in source()["retiredSubjectNames"]:
        (stage / "subjects" / name).unlink(missing_ok=True)
    for name, blob in files.items():
        (stage / "subjects" / name).write_bytes(blob)
    write(stage / "manifest.json", value)
    write(stage / "promotion-receipt.json", receipt_for(value, stage / "manifest.json", OUTPUT))
    check_manifest(stage / "manifest.json", logical_output=OUTPUT)
    publisher = module(ROOT / "tools/portrait-pilot/promote-enemy-portraits-v1.py", "cf6_shared_publisher")
    publisher.check_manifest = check_manifest
    backup = Path(tempfile.mkdtemp(prefix="backup-", dir=work))
    shutil.copytree(OUTPUT, backup, dirs_exist_ok=True)
    publisher.publish_staged_pack(stage, OUTPUT, backup)
    print(json.dumps({"status": "cf6_session_portraits_integrated", "counts": value["counts"]}, ensure_ascii=False))


def verify_native():
    config = source()
    pilot = module(ROOT / "tools/portrait-pilot/prepare_pilot.py", "cf6_native_tools")
    java, javac = pilot.find_java_tool("java"), pilot.find_java_tool("javac")
    work = ROOT / "tmp/cf6-portraits"
    work.mkdir(exist_ok=True)
    out = Path(tempfile.mkdtemp(prefix="native-replay-", dir=work))
    classes = out / "classes"
    classes.mkdir()
    cp = os.pathsep.join([str(ROOT / "tools/ffdec/lib/*"), str(ROOT / "tools/ffdec/ffdec.jar")])
    for record in {row["sourceSwf"]["path"]: row["sourceSwf"] for row in config["rows"]}.values():
        if not record.get("gitBlob"):
            raise ValueError("source Git identity missing")
        result = subprocess.run(["git", "cat-file", "blob", record["gitBlob"]], cwd=ROOT,
                                capture_output=True, timeout=60)
        blob = result.stdout
        if result.returncode or sha(blob) != record["sha256"] or len(blob) != record["bytes"]:
            raise ValueError("source SWF replay identity drift: " + record["path"])
        source_path = out / record["path"]
        source_path.parent.mkdir(parents=True, exist_ok=True)
        source_path.write_bytes(blob)
    def run(args, name):
        result = subprocess.run([str(item) for item in args], cwd=ROOT, capture_output=True, timeout=240)
        (out / (name + ".stdout.bin")).write_bytes(result.stdout)
        (out / (name + ".stderr.bin")).write_bytes(result.stderr)
        if result.returncode:
            raise ValueError("native replay failed: " + name + " " + result.stderr.decode("utf-8", errors="replace")[-700:])
    run([javac, "-encoding", "UTF-8", "-cp", cp, "-d", classes,
         verify(config["exporters"]["batch"]), verify(config["exporters"]["clean"])], "compile")
    run([java, "-Xmx2048m", "-Dfile.encoding=UTF-8", "-cp", str(classes) + os.pathsep + cp,
         "BatchPreviewExporter", out, out / "batch"], "batch")
    run([java, "-Xmx2048m", "-Dfile.encoding=UTF-8", "-cp", str(classes) + os.pathsep + cp,
         "CleanPortraitExporter", out, out / "clean"], "clean")
    for row in config["rows"]:
        relative = Path(row["rawRelative"])
        for hash_key, kind in (("pngSha256", "png"), ("svgSha256", "svg")):
            suffix = ".png" if hash_key == "pngSha256" else ".svg"
            generated = out / row["exporter"] / relative.parent.parent / kind / relative.parent.name / (relative.stem + suffix)
            if sha(generated.read_bytes()) != row[hash_key]:
                raise ValueError("native replay bytes drift: " + row["key"] + suffix)
    result = {"status": "exact_native_png_and_svg_replay", "frames": 16, "representations": 32,
              "sourceSwfCount": len({row["sourceSwf"]["path"] for row in config["rows"]}), "sessionId": SESSION_ID}
    write(out / "result.json", result)
    print(json.dumps({**result, "evidence": str(out)}, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["render", "promote", "check", "verify-native"])
    args = parser.parse_args()
    if args.command == "render":
        data, _ = render_data(True)
        print("Rendered " + data["renderDigest"])
    elif args.command == "promote":
        promote()
    elif args.command == "verify-native":
        verify_native()
    else:
        value = check_manifest(OUTPUT / "manifest.json")
        print(json.dumps({"status": "cf6_delta_and_prior_pack_verified", "counts": value["counts"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
