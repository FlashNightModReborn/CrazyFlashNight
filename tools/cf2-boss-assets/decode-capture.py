"""Decode only complete, unique, lossless row streams from the native Flash probe."""
from pathlib import Path
import argparse
import hashlib
import json
import re
from PIL import Image


def decode(trace,output,probe=False):
    images={};done=set()
    for line in trace.read_text("utf-8-sig").splitlines():
        begin=re.fullmatch(r"\[CF2_TANK_IMAGE_BEGIN\] ([a-z0-9-]+) (\d+) (\d+)",line)
        if begin:
            name,w,h=begin.groups()
            if name in images:raise ValueError("Repeated native image")
            images[name]={"width":int(w),"height":int(h),"rows":{}}
        data=re.fullmatch(r"\[CF2_TANK_IMAGE_DATA\] ([a-z0-9-]+) (.*)",line)
        if data:
            name,payload=data.groups()
            if name in done or name not in images or not payload.endswith(";"):
                raise ValueError("Unowned or incomplete image chunk")
            item=images[name]
            for encoded in payload[:-1].split(";"):
                y,runs=encoded.split("=",1);y=int(y);row=[]
                if y in item["rows"] or not 0<=y<item["height"]:raise ValueError("Repeated image row")
                for run in runs.split(","):
                    color,count=run.split(":")
                    if not re.fullmatch("[0-9a-f]{8}",color) or not 0<int(count)<=item["width"]:
                        raise ValueError("Invalid native pixel run")
                    value=int(color,16)
                    row.extend([(value>>16&255,value>>8&255,value&255,value>>24&255)]*int(count))
                if len(row)!=item["width"]:raise ValueError("Image row width mismatch")
                item["rows"][y]=row
        end=re.fullmatch(r"\[CF2_TANK_IMAGE_END\] ([a-z0-9-]+)",line)
        if end:
            if end[1] in done:raise ValueError("Repeated image terminator")
            done.add(end[1])
    expected={"stand-right","walk-right","gatling-right","laser-right","barrage-right","mobile-right","death-start","death-fragments"}
    if not probe:expected.update(("melee-right","laser-left","death-late"))
    if set(images)!=expected or done!=expected:raise ValueError("Incomplete native capture set: "+str(done))
    output.mkdir(parents=True,exist_ok=True)
    for name,item in images.items():
        if set(item["rows"])!=set(range(item["height"])):raise ValueError("Missing native image rows")
        target=output/(name+".png")
        if target.exists():raise ValueError("Preserve previous native captures")
        image=Image.new("RGBA",(item["width"],item["height"]))
        image.putdata([pixel for y in range(item["height"]) for pixel in item["rows"][y]])
        image.save(target)
    (output/"provenance.json").write_text(json.dumps({
        "kind":"native Flash BitmapData row capture","probeOnly":probe,
        "trace":str(trace),"traceSha256":hashlib.sha256(trace.read_bytes()).hexdigest(),
        "images":sorted(images)},ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("Decoded native captures: "+", ".join(sorted(images)))


if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("trace",type=Path);p.add_argument("output",type=Path);p.add_argument("--probe",action="store_true")
    a=p.parse_args();decode(a.trace,a.output,a.probe)
