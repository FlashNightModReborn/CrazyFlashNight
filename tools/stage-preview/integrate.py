#!/usr/bin/env python3
"""Integrate the exact human-accepted pixels through the existing bannerUrl field."""
import argparse
import copy
import hashlib
import io
import json
import re
from pathlib import Path
from PIL import Image
from build import ROOT, HERE, sha, generator_digest
import prepare
import render_v6_6_regions as regions

WEB=ROOT/"launcher/web"
REGISTRY=WEB/"modules/stage-select-data.js"
DESTINATION=WEB/"assets/stage-select/previews/hd"
URL_PREFIX="assets/stage-select/previews/hd/"
HEADER="// 高清预览 bannerUrl 由 tools/stage-preview/integrate.py 接入；选图与验收身份见该目录 README。"


def load_registry(text):
    marker="var manifest = "
    offset=text.index(marker)+len(marker)
    return json.JSONDecoder().raw_decode(text[offset:])[0]


def bind_banners(source, entries):
    """Patch only the selected bannerUrl values; retain hand-authored registry bytes."""
    text=source.decode("utf-8-sig")
    before=load_registry(text)
    buttons={button["id"]:button for frame in before["frames"] for button in frame.get("stageButtons",[])}
    patches=[]
    eol="\r\n" if "\r\n" in text else "\n"
    for entry in entries:
        sid=entry["id"]
        if sid not in buttons or buttons[sid]["stageName"]!=entry["stageName"]:
            raise ValueError("Stage registry identity changed: "+sid)
        matches=list(re.finditer(r'(?m)^([ \t]*)"id": "'+re.escape(sid)+r'",\r?$',text))
        if len(matches)!=1:raise ValueError("Expected one registry entry: "+sid)
        match=matches[0]
        start=text.rfind("{",0,match.start())
        button,length=json.JSONDecoder().raw_decode(text[start:])
        if button.get("id")!=sid:raise ValueError("Unexpected registry object: "+sid)
        old=text[start:start+length]
        value=json.dumps(entry["url"],ensure_ascii=False)
        if "bannerUrl" in button:
            new,count=re.subn(r'("bannerUrl"\s*:\s*)"[^"\r\n]*"',lambda m:m[1]+value,old)
        else:
            new,count=re.subn(r'("previewUrl"\s*:\s*"[^"\r\n]*",\r?\n)',
                lambda m:m[1]+match[1]+'"bannerUrl": '+value+','+eol,old)
        if count!=1:raise ValueError("Cannot patch exactly one banner URL: "+sid)
        patches.append((start,start+length,new))
    for start,end,new in sorted(patches,reverse=True):text=text[:start]+new+text[end:]
    if HEADER not in text:text=HEADER+eol+text
    after=load_registry(text)
    restored=copy.deepcopy(after)
    selected={entry["id"] for entry in entries}
    for frame in restored["frames"]:
        for button in frame.get("stageButtons",[]):
            if button["id"] in selected:
                previous=buttons[button["id"]]
                if "bannerUrl" in previous:button["bannerUrl"]=previous["bannerUrl"]
                else:button.pop("bannerUrl",None)
    if restored!=before:raise ValueError("Registry patch changed unrelated fields")
    return (b"\xef\xbb\xbf" if source.startswith(b"\xef\xbb\xbf") else b"")+text.encode("utf-8")


def integrate(candidate, check_only=False):
    accepted=json.loads((HERE/"accepted.json").read_text("utf-8"))
    manifest=json.loads((candidate/"manifest.json").read_text("utf-8"))
    config=json.loads((HERE/"stages.json").read_text("utf-8"))
    if accepted["status"]!="human_accepted":raise ValueError("The selected set has no recorded human acceptance")
    for key,value in [("sourceConfigSha256",sha(HERE/"stages.json")),("generatorSha256",generator_digest())]:
        if accepted[key]!=value or manifest[key]!=value:raise ValueError("Accepted source or generator changed: "+key)
    ids=[entry["id"] for entry in config["stages"]]
    if [entry["id"] for entry in manifest["stages"]]!=ids or [entry["id"] for entry in accepted["stages"]]!=ids:
        raise ValueError("Candidate, approval and current selection must cover exactly the same stages")
    prepare.check(regions.PILOT_DIR)
    outputs={};entries=[]
    for current,approved,selection in zip(manifest["stages"],accepted["stages"],config["stages"]):
        sid=current["id"]
        if any(current.get(key)!=value for key,value in selection.items()):raise ValueError("Candidate selection changed: "+sid)
        if current["file"]!=f"images/{sid}.png":raise ValueError("Noncanonical candidate image: "+sid)
        file=candidate/current["file"]
        if sha(file)!=approved["pngSha256"]:raise ValueError("PNG differs from human-accepted candidate: "+sid)
        with Image.open(file) as image:
            image=image.convert("RGB")
            pixels=image.tobytes()
            if image.size!=(644,276) or hashlib.sha256(pixels).hexdigest()!=approved["rgbSha256"]:
                raise ValueError("Candidate pixels differ from acceptance: "+sid)
            buffer=io.BytesIO();image.save(buffer,format="WEBP",lossless=True,quality=100,method=6,exact=True)
            payload=buffer.getvalue()
        with Image.open(io.BytesIO(payload)) as decoded:
            if decoded.convert("RGB").tobytes()!=pixels:raise ValueError("WebP transcode changed pixels: "+sid)
        digest=hashlib.sha256(payload).hexdigest()
        name=f"{sid}-{digest[:12]}.webp"
        outputs[name]=payload
        entries.append({"id":sid,"stageName":selection["stageName"],"url":URL_PREFIX+name,
                        "sha256":digest,"rgbSha256":approved["rgbSha256"],"bytes":len(payload)})
    runtime={"schema":"cfn.stage-preview-runtime.v1","source":"tools/stage-preview/stages.json",
             "acceptance":"tools/stage-preview/accepted.json","acceptanceSha256":sha(HERE/"accepted.json"),
             "sourceConfigSha256":accepted["sourceConfigSha256"],"generatorSha256":accepted["generatorSha256"],
             "integratorSha256":sha(Path(__file__)),"encoding":"webp-lossless-pixel-verified","width":644,"height":276,
             "imageBytes":sum(entry["bytes"] for entry in entries),"stages":entries}
    outputs["manifest.json"]=(json.dumps(runtime,ensure_ascii=False,indent=2)+"\n").encode("utf-8")
    outputs[".gitattributes"]=b".gitattributes text eol=lf\nmanifest.json text eol=lf\n*.webp -text\n"
    original=REGISTRY.read_bytes();patched=bind_banners(original,entries)
    unexpected={p.name for p in DESTINATION.iterdir()}-set(outputs) if DESTINATION.exists() else set()
    if unexpected:raise ValueError("Unmanaged files in the HD delivery directory: "+", ".join(sorted(unexpected)))
    stale=[name for name,payload in outputs.items() if not (DESTINATION/name).is_file() or (DESTINATION/name).read_bytes()!=payload]
    if check_only:
        if stale or patched!=original:raise ValueError("Stale HD delivery: "+", ".join(stale+(["stage-select-data.js"] if patched!=original else [])))
    else:
        DESTINATION.mkdir(parents=True,exist_ok=True)
        for name in stale:(DESTINATION/name).write_bytes(outputs[name])
        if original!=patched:REGISTRY.write_bytes(patched)
    print(json.dumps({"mode":"check" if check_only else "write","stages":len(entries),"bytes":runtime["imageBytes"],
                      "acceptedPixelsUnchanged":True,"registryFields":"selected bannerUrl only","pass":True},ensure_ascii=False,indent=2))
    return runtime


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate",type=Path)
    parser.add_argument("--check",action="store_true")
    args=parser.parse_args()
    integrate(args.candidate,args.check)
