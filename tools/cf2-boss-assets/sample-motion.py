"""Prepare/validate native Animate authoring samples; CS6 alone publishes the SWF."""
from pathlib import Path
import argparse
import copy
import json
import math
import os
import re
import shutil
import build

TEMPLATE = build.HERE/"sample-motion.jsfl.template"
SAMPLES = build.HERE/"motion-samples.json"
LABELS = ("常态","跑步走路","平a","技能","死亡")


def prepare(run_id):
    if not re.fullmatch("[0-9a-f]{32}",run_id):
        raise ValueError("Expected a fresh exact run identity")
    source,_,_=build.source()
    work=Path(os.environ["LOCALAPPDATA"])/"Temp/opencode"/("cf2-motion-"+run_id)
    if work.exists():
        raise ValueError("Preserve the existing native sampling run")
    work.mkdir(parents=True)
    target=work/"source"
    shutil.copytree(source,target)
    # Strip executable scripts and the exact editor-only missing-font note, but
    # keep every native parent, tween, frame, media cache and visual matrix.
    changed=[]
    for path in [target/"DOMDocument.xml",*sorted((target/"LIBRARY").rglob("*.xml"))]:
        tree=build.E.parse(str(path),build.PARSER)
        touched=False
        for node in list(tree.findall(".//x:Actionscript",build.NS)):
            node.getparent().remove(node);touched=True
        for node in list(tree.findall(".//x:DOMStaticText",build.NS)):
            text="".join(node.xpath(".//x:characters/text()",namespaces=build.NS))
            if text=="全弹发射还包含那十个榴弹炮":
                node.getparent().remove(node);touched=True
        if touched:
            path.write_bytes(build.native.xml_bytes(tree.getroot()))
            changed.append(path.relative_to(target).as_posix())
    origin=json.loads((build.ARCHIVE/"archive-origin.json").read_text("utf-8"))
    job={"schema":"cf2-tank-boss.motion-job.v1","runId":run_id,
         "archiveSha256":origin["sha256"],"samplerSha256":build.sha(TEMPLATE),
         "source":str(target/"大机器人完整版.xfl"),"report":str(work/"native-report.json"),
         "status":str(work/"status.txt"),"script":str(work/"sample-motion.jsfl"),
         "scratchOnlySanitization":changed}
    script=TEMPLATE.read_text("utf-8")
    values={"SOURCE_URI":Path(job["source"]).as_uri(),"OUTPUT_URI":Path(job["report"]).as_uri(),
            "STATUS_URI":Path(job["status"]).as_uri(),"RUN_ID":run_id,
            "ARCHIVE_SHA":job["archiveSha256"],"SAMPLER_SHA":job["samplerSha256"]}
    for key,value in values.items():
        script=script.replace("__"+key+"__",value)
    Path(job["script"]).write_text(script,encoding="utf-8-sig")
    (work/"job.json").write_text(json.dumps(job,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"job":str(work/"job.json")},ensure_ascii=False))


def validate_report(work):
    job=json.loads((work/"job.json").read_text("utf-8"))
    if Path(job["report"]).parent!=work or Path(job["status"]).parent!=work:
        raise ValueError("Sampling output escaped the exact job")
    if Path(job["status"]).read_text("utf-8-sig")!="complete "+job["runId"]:
        raise ValueError("The native authoring sampler did not complete")
    report=json.loads(Path(job["report"]).read_text("utf-8-sig"))
    origin=json.loads((build.ARCHIVE/"archive-origin.json").read_text("utf-8"))
    if (report.get("schema")!="cf2-tank-boss.native-motion.v1"
            or report.get("runId")!=job["runId"]
            or report.get("samplerSha256")!=job["samplerSha256"]
            or job["samplerSha256"]!=build.sha(TEMPLATE)
            or report.get("archiveSha256")!=origin["sha256"]
            or not report.get("version","").startswith("WIN 24,")):
        raise ValueError("Native sampling identity mismatch")
    _,_,original=build.source()
    if set(report["actions"])!=set(LABELS):
        raise ValueError("Native sampling action closure mismatch")
    controls=0
    normalization=[]
    for label in LABELS:
        art=original["坦克大机器人/"+label]
        layers=build.layers(art);sample=report["actions"][label]
        if (sample["frameCount"]!=build.total(art) or len(sample["poses"])!=build.total(art)
                or sample["layers"]!=[l.get("name") for l in layers]):
            raise ValueError("Native timeline/layer identity mismatch: "+label)
        for fi,pose in enumerate(sample["poses"]):
            by_layer={}
            for row in pose:
                li=row["layer"]
                if type(li) is not int or not 0<=li<len(layers):
                    raise ValueError("Invalid native layer index")
                by_layer.setdefault(li,[]).append(row)
                matrix=row["matrix"]
                if len(matrix)!=6 or any(type(v) not in (int,float) or not math.isfinite(v) or abs(v)>1e7 for v in matrix):
                    raise ValueError("Invalid native matrix")
            for li,layer in enumerate(layers):
                frame=build.active(layer,fi)
                elements=[] if frame is None else frame.findall("x:elements/x:DOMSymbolInstance",build.NS)
                rows=by_layer.get(li,[])
                if [r["part"] for r in rows]!=[e.get("libraryItemName") for e in elements]:
                    authored=build.frames(layer)
                    end=max(int(f.get("index","0"))+int(f.get("duration","1")) for f in authored)
                    last=authored[-1].findall("x:elements/x:DOMSymbolInstance",build.NS)
                    # convertToKeyframes extends a short layer's held final
                    # symbol. These are never parented/baked runtime layers;
                    # keep the source's actual end rather than inventing art.
                    if (frame is None and fi>=end
                            and not any(f.get("parentLayerIndex") is not None for f in authored)
                            and [r["part"] for r in rows]==[e.get("libraryItemName") for e in last]):
                        pose[:]=[r for r in pose if r["layer"]!=li]
                        normalization.append({"action":label,"frame":fi+1,"layer":li,
                                              "reason":"discard native conversion extension beyond original unparented span"})
                    else:
                        raise ValueError("Native visual part closure mismatch: "+label+"/"+str(fi+1)+"/"+str(li))
                # Independent controls: unparented original key matrices must
                # survive native sampling, within one CS6/Animate twip.
                if frame is not None and int(frame.get("index","0"))==fi and not frame.get("parentLayerIndex"):
                    for row,element in zip(rows,elements):
                        if max(abs(a-b) for a,b in zip(row["matrix"],build.matrix(element)))>0.051:
                            raise ValueError("Native unparented key changed: "+label+"/"+str(fi+1)+"/"+str(li))
                        controls+=1
    if controls<10:
        raise ValueError("Insufficient independent author key controls")
    report["normalization"]=normalization
    return report,controls


def main():
    p=argparse.ArgumentParser()
    group=p.add_mutually_exclusive_group(required=True)
    group.add_argument("--prepare",metavar="RUN_ID")
    group.add_argument("--check-report",type=Path)
    group.add_argument("--import-report",type=Path)
    args=p.parse_args()
    if args.prepare:
        prepare(args.prepare);return
    work=(args.check_report or args.import_report).resolve()
    report,controls=validate_report(work)
    if args.import_report:
        canonical=copy.deepcopy(report)
        canonical.pop("runId")
        SAMPLES.write_text(json.dumps(canonical,ensure_ascii=False,separators=(",",":"))+"\n",encoding="utf-8")
    print(json.dumps({"ok":True,"nativeVersion":report["version"],"unparentedKeyControls":controls,
                      "frames":sum(a["frameCount"] for a in report["actions"].values()),
                      "imported":bool(args.import_report)},ensure_ascii=False))


if __name__=="__main__":
    main()
