#!/usr/bin/env python3
"""Prove the checker rejects delivery regressions in disposable copies."""
import argparse
import contextlib
import io
import json
import shutil
import uuid
from pathlib import Path
from PIL import Image
from build import ROOT, sha
from check import check


def verify(candidate):
    output=ROOT/"tmp/stage-preview-negative"/uuid.uuid4().hex
    output.mkdir(parents=True)
    cases=[]
    for name in ["missing-stage", "selected-metadata", "frozen-pixels", "near-duplicate"]:
        folder=output/name
        shutil.copytree(candidate,folder,ignore=shutil.ignore_patterns("consumer", "browser-report*", "review-gallery.png"))
        manifest=json.loads((folder/"manifest.json").read_text("utf-8"))
        entries={entry["id"]:entry for entry in manifest["stages"]}
        if name=="missing-stage":
            manifest["stages"].pop()
            expected="Delivery does not exactly cover the selected stage list"
        elif name=="selected-metadata":
            entries["stage_0_1"]["subjects"]=[]
            expected="stage_0_1: selected metadata differs from authoritative configuration"
        else:
            entry=entries["stage_0_0" if name=="frozen-pixels" else "stage_59_12"]
            image=Image.open(folder/(entry["file"] if name=="frozen-pixels" else entries["stage_59_4"]["file"])).convert("RGB")
            if name=="frozen-pixels":
                pixel=image.getpixel((0,0));image.putpixel((0,0),((pixel[0]+1)%256,pixel[1],pixel[2]))
                expected="stage_0_0: frozen V6 pixels changed"
            else:expected="stage_59_4/stage_59_12 near-duplicate"
            image.save(folder/entry["file"])
            image.resize((161,69),Image.Resampling.LANCZOS).save(folder/entry["thumb"])
            entry["sha256"]=sha(folder/entry["file"])
            entry["thumb_sha256"]=sha(folder/entry["thumb"])
        (folder/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        with contextlib.redirect_stdout(io.StringIO()):
            status=check(folder)
        result=json.loads((folder/"check-report.json").read_text("utf-8"))
        passed=status==1 and any(expected in failure for failure in result["failures"])
        cases.append({"name":name,"expected":expected,"pass":passed,"failures":result["failures"]})
        print(name+": "+("rejected as expected" if passed else "FAILED"),flush=True)
    report={"candidateManifestSha256":sha(candidate/"manifest.json"),"pass":all(case["pass"] for case in cases),"cases":cases}
    (output/"negative-report.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(output/"negative-report.json")
    return 0 if report["pass"] else 1


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("candidate",type=Path)
    raise SystemExit(verify(parser.parse_args().candidate))
