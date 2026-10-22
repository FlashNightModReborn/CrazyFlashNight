#!/usr/bin/env python3
"""Reconstruct the small native input cache from versioned game assets."""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import uuid
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
DEFAULT_CACHE=ROOT/"tmp/stage-preview-cache"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def matches(file,item):
    if not file.is_file():return False
    with Image.open(file) as im:
        im=im.convert("RGBA")
        return list(im.size)==item["size"] and hashlib.sha256(im.tobytes()).hexdigest()==item["pixelSha256"]


def load():
    return json.loads((HERE/"native-sources.json").read_text("utf-8"))


def validate_sources(config):
    if digest(ROOT/"tools/ffdec/ffdec.jar") != config["ffdecSha256"]:
        raise ValueError("FFDec differs from the reviewed raster recipe")
    catalog=json.loads((ROOT/"launcher/web/assets/enemy-portraits/manifest.json").read_text("utf-8"))["entries"]
    for item in config["inputs"]:
        source=ROOT/item["source"]
        if not source.is_file() or digest(source)!=item["sourceSha256"]:
            raise ValueError(f"Native input changed; refresh its visual review before updating the recipe: {item['source']}")
        if item.get("portraitRef"):
            entry=catalog[item["portraitRef"]]
            current=entry["variants"][entry.get("defaultVariant","default")]["subject"]["pngFallback"]["url"]
            if "launcher/web/"+current!=item["source"]:
                raise ValueError(f"Production portrait mapping changed: {item['portraitRef']}")


def check(cache,config=None):
    config=config or load();validate_sources(config)
    for item in config["inputs"]:
        file=cache/item["output"]
        if not file.is_file():raise ValueError(f"Missing native cache input: {file}; run prepare.py first")
        if not matches(file,item):raise ValueError(f"Native raster pixels differ: {item['output']}")
    return len(config["inputs"])


def find_jdk():
    candidates=[Path(os.environ["JAVA_HOME"])/"bin"] if os.environ.get("JAVA_HOME") else []
    candidates.append(Path(r"C:\Program Files\Adobe\Adobe Animate 2024\jre\bin"))
    if shutil.which("javac"):candidates.append(Path(shutil.which("javac")).parent)
    for folder in candidates:
        if (folder/"javac.exe").exists() and (folder/"java.exe").exists():return folder
    raise RuntimeError("A local JDK with java and javac is required; no software is installed automatically")


def prepare(cache):
    config=load();validate_sources(config);cache.mkdir(parents=True,exist_ok=True)
    jdk=find_jdk();classes=cache/".java";classes.mkdir(exist_ok=True)
    run_dir=cache/".runs"/uuid.uuid4().hex;run_dir.mkdir(parents=True)
    jar=ROOT/"tools/ffdec/ffdec.jar"
    subprocess.run([str(jdk/"javac.exe"),"-encoding","UTF-8","-cp",str(jar),"-d",str(classes),str(HERE/"BatchBgExporter.java"),str(HERE/"NativeFrameExporter.java")],check=True)
    sprite_jobs=[];background_jobs=[]
    for item in config["inputs"]:
        destination=cache/item["output"];destination.parent.mkdir(parents=True,exist_ok=True)
        source=ROOT/item["source"]
        if matches(destination,item):continue
        if item["kind"]=="copy":shutil.copyfile(source,destination)
        elif item["kind"]=="background":background_jobs.append(f"{source}|{destination.parent}")
        elif item["kind"]=="sprite":
            parts=[str(source),str(destination.parent.parent),str(item["sprite"]),str(item["frame"]),str(item["zoom"])]
            if item.get("keepDepths"):parts.append(",".join(map(str,item["keepDepths"])))
            sprite_jobs.append("|".join(parts))
        else:raise ValueError("Unknown extraction mode "+item["kind"])
    for tool,jobs in [("BatchBgExporter",background_jobs),("NativeFrameExporter",sprite_jobs)]:
        if not jobs:continue
        job_file=run_dir/(tool+".txt");job_file.write_text("\n".join(jobs)+"\n",encoding="utf-8")
        run=subprocess.run([str(jdk/"java.exe"),"-Djava.awt.headless=true","-cp",os.pathsep.join([str(classes),str(jar)]),tool,str(job_file)],capture_output=True)
        (run_dir/(tool+".log")).write_bytes(run.stdout+b"\n"+run.stderr)
        if run.returncode:raise RuntimeError(f"{tool} failed; see {run_dir/(tool+'.log')}")
    count=check(cache,config)
    print(f"Native cache verified: {count} sources; source and pixel hashes match")


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--cache",type=Path,default=DEFAULT_CACHE);parser.add_argument("--check",action="store_true");args=parser.parse_args()
    if args.check:print(f"Native cache verified: {check(args.cache)} sources")
    else:prepare(args.cache)
