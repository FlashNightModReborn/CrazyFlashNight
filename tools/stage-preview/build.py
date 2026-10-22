#!/usr/bin/env python3
"""Build a review candidate without changing production assets or the V6 baseline."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image
import refine
import render_v6_6_regions as regions
import prepare
import render_audit

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generator_digest():
    names=["build.py","refine.py","prepare.py","render_audit.py","render_v6_base_gate_all16.py",
           "render_v6_6_regions.py","render_boss_c2_ab_sheet.py",
           "NativeFrameExporter.java","BatchBgExporter.java","native-sources.json"]
    return hashlib.sha256("\n".join(name+":"+sha(HERE/name) for name in names).encode()).hexdigest()


def metadata_inputs():
    return {name:sha(ROOT/name) for name in [
        "data/environment/stage_environment.xml",
        "launcher/web/assets/enemy-portraits/manifest.json",
        "launcher/web/modules/stage-select-data.js",
        "data/units/units.json",
    ]}


def build(output, only=None):
    config = json.loads((HERE / "stages.json").read_text("utf-8"))
    prepare.check(regions.PILOT_DIR)
    regions._SKY_CACHE.clear()
    environment = regions.load_environment_map()
    output.mkdir(parents=True, exist_ok=True)
    images = output / "images"
    images.mkdir(exist_ok=True)
    results = []
    cache_files = set()
    for entry in config["stages"]:
        if only and entry["id"] not in only:
            continue
        previous = ROOT / entry["baseline"]
        render_audit.begin(entry)
        if sha(previous) != entry["baseline_sha256"]:
            raise ValueError(f"V6 baseline changed: {entry['id']}; review the new source before rebuilding")
        if entry["decision"] == "preserve_v6":
            image = Image.open(previous).convert("RGB")
        elif entry.get("renderer") == "imported":
            if sha(ROOT / entry["image_source"]) != entry["image_source_sha256"]:
                raise ValueError(f"Imported composition changed: {entry['id']}")
            image = Image.open(ROOT / entry["image_source"]).convert("RGB")
        else:
            opened = Image.open
            def audit_open(path, *args, **kwargs):
                if isinstance(path,(str,Path)):
                    try:
                        relative=Path(path).resolve().relative_to(regions.PILOT_DIR.resolve()).as_posix()
                        cache_files.add(relative)
                    except ValueError:
                        pass
                return opened(path,*args,**kwargs)
            try:
                Image.open=audit_open
                image = refine.render(entry, environment, entry.get("composition")).convert("RGB")
            finally:
                Image.open=opened
        if image.size != (644,276):
            raise ValueError(f"Wrong canvas: {entry['id']} {image.size}")
        hd = images / f"{entry['id']}.png"
        thumb = images / f"{entry['id']}-thumb.png"
        image.save(hd)
        image.resize((161,69), Image.Resampling.LANCZOS).save(thumb)
        result = {**entry, "file": hd.relative_to(output).as_posix(),
                  "thumb": thumb.relative_to(output).as_posix(),
                  "sha256":sha(hd), "thumb_sha256":sha(thumb),
                  "bytes":hd.stat().st_size}
        result["subjectAudit"]=render_audit.finish(image,output)
        results.append(result)
        print(f"{entry['id']}: {entry['decision']}", flush=True)
    report = {"schema":"cfn.stage-preview-review.v1", "status":"candidate_pending_human_review",
              "stageCount":len(results), "sourceConfigSha256":sha(HERE/"stages.json"),
              "generatorSha256":generator_digest(),
              "metadataInputs":metadata_inputs(),
              "imageBytes":sum(e["bytes"] for e in results), "cacheFiles":sorted(cache_files), "stages":results}
    (output/"manifest.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    return report


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--only",help="Comma-separated stage IDs for local iteration")
    args=parser.parse_args()
    build(args.output, set(args.only.split(",")) if args.only else None)
