"""Replay a CS6-built authoring TestLoader in the installed Flash Player 20. Only the light XML changes."""
import argparse
import hashlib
import http.server
import threading
from functools import partial
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path("data/combat_visuals/light_profiles.xml")
ASSETS = ["flashswf/arts/原版素材库-子弹.swf", "flashswf/arts/new/lady.swf", "scripts/asLoader.swf",
          "flashswf/arts/new/3XD做的npc.swf", "flashswf/arts/new/偷吃屑鱼坟头贡品.swf", "flashswf/arts/new/军阀新人物合集.swf",
          "flashswf/arts/new/素材库-诺亚新敌人.swf", "flashswf/arts/things3.swf", "CRAZYFLASHER7MercenaryEmpire.swf"]
WEAPONS = "data/items/武器_长枪_发射器.xml"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def variants(source):
    doc=ET.fromstring(source)
    profiles={p.get("id"):p for p in doc.find("Profiles")}
    bindings=doc.find("Bindings")
    for binding in list(bindings):
        if binding.get("key")=="火箭弹":
            bindings.remove(binding)
    render=lambda: ET.tostring(doc, encoding="utf-8", xml_declaration=True)
    dark=render()
    ET.SubElement(bindings,"Binding",kind="projectile",key="火箭弹",profile="普通火箭弹")
    rocket_only=render()
    profiles["支援飞弹"].attrib.update(radius="125",energy=".7",offsetY="-20",color="#66AAFF")
    profiles["加强电球"].attrib.update(stageRadius="205",stageEnergy="1.1")
    profiles["量子爆弹"].attrib.update(stageRadius="235",stageEnergy="1.25")
    profiles["__huofeng_nirvana"].attrib.update(radius="180",energy="1.2",totalFrames="8")
    profiles["__pulse_cold"].attrib.update(radius="150",energy="1",color="#C8F8FF")
    next(b for b in bindings if b.get("key")=="area.ice-stream").attrib.update(nearFraction=".2",farFraction=".8")
    edited=render()
    profiles["支援飞弹"].set("energy","bad")
    return {"A":dark, "B-rocket":rocket_only, "C-four":edited, "D-invalid":render()}


def run_player(player, movie_url, receipt_name, previous):
    store=Path(os.environ["APPDATA"])/"Macromedia/Flash Player/#SharedObjects"
    info=subprocess.STARTUPINFO()
    info.dwFlags|=subprocess.STARTF_USESHOWWINDOW
    # The projector suspends timeline activity while its movie window is hidden.
    info.wShowWindow=4  # SW_SHOWNOACTIVATE
    process=subprocess.Popen([str(player),movie_url],cwd=player.parent,startupinfo=info)
    consumed=None
    try:
        deadline=time.monotonic()+80
        while time.monotonic()<deadline:
            for file in store.rglob(receipt_name):
                if file.stat().st_mtime_ns <= previous.get(file,0):
                    continue
                raw=file.read_bytes()
                start=raw.find(b"CF7-LIGHT-BEGIN\n")
                end=raw.find(b"\nCF7-LIGHT-END",start+1)
                if start>=0 and end>=0:
                    consumed=file
                    previous[file]=file.stat().st_mtime_ns
                    return raw[start+len(b"CF7-LIGHT-BEGIN\n"):end].decode("utf-8"),process.pid
            if process.poll() is not None:
                raise RuntimeError("Player exited before its fixture receipt")
            time.sleep(.35)
        raise RuntimeError("Player did not write its dedicated fixture receipt")
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
        # Identical failure reports do not dirty SharedObject a second time. Start each
        # restart with a clean copy of this just-consumed, run-specific fixture receipt.
        if consumed is not None and consumed.is_file() and consumed.stat().st_mtime_ns==previous[consumed]:
            consumed.unlink()


class FixtureFiles(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.endswith("/"+SOURCE.as_posix()) and self.server.hold_config is not None:
            gate=self.server.hold_config
            self.log_request("withheld")
            gate.wait(timeout=20)
            return
        super().do_GET()

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_request(self, code="-", size="-"):
        from urllib.parse import unquote
        entry = (self.command, unquote(self.path), str(code))
        self.server.requests_seen.append(entry)
        with self.server.audit_file.open("a", encoding="utf-8") as audit:
            audit.write(" ".join(entry) + "\n")

    def log_message(self, format, *args):
        pass

def decode(text):
    values={}; gameplay={}
    for line in text.splitlines():
        if line.startswith("LightAuthorSample "):
            _,label,wire=line.split(" ",2)
            values[label]=[list(map(float,row.split(",")[1:])) for row in wire.split(";") if row]
        elif line.startswith("LightGameplay "):
            name,data=line.removeprefix("LightGameplay ").split(" 火箭弹|",1)
            gameplay[name]=data
    return values,gameplay


def verify(reports):
    for name,text in reports.items():
        assert text.startswith("WIN 20,") and "DynamicLightProfilesTest Tests Failed: 0" in text,name
    a,gameplay=decode(reports["A"]); b,g2=decode(reports["B-rocket"]); c,g3=decode(reports["C-four"]); d,g4=decode(reports["D-invalid"])
    assert gameplay==g2==g3==g4 and set(gameplay)=={"RPG","M3 Rocket Launcher"}
    for key in ("rpg","m3"):
        assert a[key]==d[key]==[] and len(b[key])==len(c[key])==1,key
        assert b[key][0][6:9]==[155,0,1.2] and b[key]==c[key],key
    # IDs reflect admission order, not authored brightness or position.
    visual=lambda lights: sorted(row[1:] for row in lights)
    for key in a.keys()-{"rpg","m3"}:
        assert visual(a[key])==visual(b[key]),key
    for key,xy in {"lady-right":[140,320],"lady-left":[140,320]}.items():
        assert len(c[key])==2 and sorted(r[2] for r in c[key])==xy,key
        assert all(row[6]==150 for row in c[key]) and visual(a[key])!=visual(c[key]),key
    near=lambda lights: max(lights,key=lambda r:r[8])
    assert near(c["lady-right"])[2]==140 and near(c["lady-left"])[2]==320
    for k,rad,energy in [("ordinary",125,.7),("stage0-at",205,1.1),("stage1-at",235,1.25)]:
        assert len(c[k])==1 and c[k][0][6]==rad and math.isclose(c[k][0][8],energy),k
    for k in ["stage0-before","stage1-before"]:
        assert visual(a[k])==visual(c[k]),k
    assert math.isclose(c["huofeng"][0][6]/a["huofeng"][0][6],180/270,rel_tol=.00001)
    assert math.isclose(c["huofeng"][0][8]/a["huofeng"][0][8],1.2/1.85,rel_tol=.0002)
    assert "LightLease duration=4" in reports["A"] and "LightLease duration=8" in reports["C-four"]
    assert "LightAuthorDegraded empty" in reports["D-invalid"]
    for label in ("A","B-rocket","C-four"):
        for frame,count in ((269,1),(287,2)):
            detail=next(line for line in reports[label].splitlines() if line.startswith(f"LightTimeline ice frame={frame} "))
            assert detail.count(";l,")==count and "slot=0 facing=-1" in detail
        assert "LightTimeline blades frame=615 slots=1228,1229" in reports[label]


def main():
    args=argparse.ArgumentParser(description=__doc__)
    mode=args.add_mutually_exclusive_group()
    mode.add_argument("--benchmark",action="store_true",help="replay the fixed old/new workload comparison")
    mode.add_argument("--flight",action="store_true",help="replay actual projectile creation, movement, collision and cleanup")
    args.add_argument("--test-swf",required=True,type=Path)
    args.add_argument("--compile-trace",required=True,type=Path)
    args.add_argument("--output",required=True,type=Path)
    options=args.parse_args()
    trace=options.compile_trace.read_text(encoding="utf-8-sig")
    domain="dynamic-light-profiles"
    prefix="cf7-light-author-"
    if options.benchmark:
        domain="projectile-light-comparison"
        prefix="cf7-light-bench-"
    if options.flight:
        domain="weapon-projectile-flight"
        prefix="cf7-light-flight-"
    token=re.search(r"^FocusedTestRunId "+domain+r" Complete: ([0-9a-f]{32})",trace,re.M).group(1)
    player=ROOT/"Adobe Flash Player 20.exe"
    output=options.output.resolve();output.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="cf7-author-") as tmp:
        root=Path(tmp)/"light-author-proof/resources"
        for rel in ASSETS+[WEAPONS]:
            dest=root/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/rel,dest)
        movie=root/"scripts/TestLoader.swf";shutil.copy2(options.test_swf,movie)
        config=root/SOURCE;config.parent.mkdir(parents=True,exist_ok=True)
        fixed=lambda:{p.relative_to(root).as_posix():sha(p) for p in sorted(root.rglob("*")) if p.is_file() and p!=config}
        before=fixed()
        name=prefix+token+".sol"
        store=Path(os.environ["APPDATA"])/"Macromedia/Flash Player/#SharedObjects"
        previous={p:p.stat().st_mtime_ns for p in store.rglob(name)}
        handler=partial(FixtureFiles,directory=tmp)
        server=http.server.ThreadingHTTPServer(("127.0.0.1",0),handler)
        server.requests_seen=[]
        server.hold_config=None
        server.audit_file=output/"requests.txt"
        server.audit_file.write_text("",encoding="utf-8")
        url=f"http://127.0.0.1:{server.server_port}/light-author-proof/resources/scripts/TestLoader.swf"
        worker=threading.Thread(target=server.serve_forever,daemon=True)
        worker.start()
        try:
            capture_variants(options,output,config,fixed,before,token,player,url,name,previous,server)
        finally:
            server.shutdown()
            server.server_close()
            worker.join()


def capture_variants(options,output,config,fixed,before,token,player,url,name,previous,server):
    reports={};runs={}
    if options.flight:
        config.write_bytes((ROOT/SOURCE).read_bytes())
        report,pid=run_player(player,url,name,previous)
        (output/"player20-flight.txt").write_text(report,encoding="utf-8")
        assert report.startswith("WIN 20,") and before==fixed()
        passed=re.search(r"Tests Passed: ([0-9]+)",report)
        assert passed and int(passed.group(1))>=141 and "Tests Failed: 0" in report,report
        evidence={"player":str(player),"playerSha256":sha(player),"pid":pid,"version":report.splitlines()[0],
                  "testRunId":token,"fixedInputs":before,"reportSha256":sha(output/"player20-flight.txt"),"passed":int(passed.group(1)),"failed":0}
        (output/"verified.json").write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        print("Flash Player 20 projectile flight and collision checks:",passed.group(1),"passed")
        return
    if options.benchmark:
        config.write_bytes((ROOT/SOURCE).read_bytes())
        report,pid=run_player(player,url,name,previous)
        (output/"player20-benchmark.txt").write_text(report,encoding="utf-8")
        assert report.startswith("WIN 20,") and before==fixed()
        costs={}
        for row in report.splitlines()[1:]:
            mode,_,columns=row.split(" ",2)
            metrics={key:int(value) for key,value in re.findall(r"(\w+)=(\d+)",columns)}
            assert metrics["samples"]==30 and metrics["admitted"]<=16
            assert metrics["lookupBatch"]==256 and metrics["lookupHits"]==128
            assert metrics["totalMsP95"]>=metrics["totalMsP50"]
            costs[mode+"-"+str(metrics["case"])]=metrics
        assert len(costs)==10 and costs["baseline-2"]["registered"]==2 and costs["candidate-2"]["registered"]==16
        assert costs["candidate-4"]["allocations"]==48 and costs["baseline-4"]["allocations"]==60
        assert all(costs[x+"-0"]["admitted"]==0 for x in ("baseline","candidate"))
        evidence={"player":str(player),"playerSha256":sha(player),"pid":pid,"version":report.splitlines()[0],
                  "testRunId":token,"inputSha256":sha(config),"reportSha256":sha(output/"player20-benchmark.txt"),"fixedInputs":before,"costs":costs}
        (output/"verified.json").write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        print("Flash Player 20: five paired workloads on the same AVM1 player, 30 timed samples per side.")
        return
    for label,xml in variants((ROOT/SOURCE).read_bytes()).items():
        server.requests_seen.clear()
        config.write_bytes(xml)
        (output/(label+".xml")).write_bytes(xml)
        reports[label],pid=run_player(player,url,name,previous)
        (output/(label+".txt")).write_text(reports[label],encoding="utf-8")
        assert before==fixed(),"A fixed input changed"
        required={SOURCE.as_posix(),WEAPONS,ASSETS[0],ASSETS[1],"scripts/TestLoader.swf"}
        requested={p.removeprefix("/light-author-proof/resources/") for method,p,code in server.requests_seen if method=="GET" and code=="200"}
        assert required<=requested,"The player did not load all five authoring inputs"
        runs[label]={"pid":pid,"xmlSha256":sha(config),"reportSha256":sha(output/(label+".txt")),
                     "requested":list(server.requests_seen)}
    for label in ("E-missing","F-timeout"):
        server.requests_seen.clear()
        if label=="E-missing":
            config.unlink()
        else:
            config.write_bytes((output/"B-rocket.xml").read_bytes())
            server.hold_config=threading.Event()
        began=time.monotonic()
        try:
            report,pid=run_player(player,url,name,previous)
        finally:
            if server.hold_config is not None:
                server.hold_config.set()
                server.hold_config=None
        reports[label]=report
        (output/(label+".txt")).write_text(report,encoding="utf-8")
        values,gameplay=decode(report)
        assert before==fixed() and values=={"rpg":[],"m3":[]} and gameplay==decode(reports["A"])[1]
        assert "LightAuthorDegraded empty" in report and "Tests Failed: 0" in report
        status="404" if label=="E-missing" else "withheld"
        assert any(path.endswith("/"+SOURCE.as_posix()) and code==status for _,path,code in server.requests_seen)
        elapsed=time.monotonic()-began
        if label=="F-timeout":
            assert elapsed>=5
        runs[label]={"pid":pid,"xmlSha256":sha(config) if config.is_file() else None,
                     "reportSha256":sha(output/(label+".txt")),"elapsedSeconds":round(elapsed,3),
                     "requested":list(server.requests_seen)}
    verify(reports)
    evidence={"player":str(player),"playerSha256":sha(player),"version":reports["A"].splitlines()[0],
              "testRunId":token,"fixedInputs":before,"runs":runs}
    (output/"verified.json").write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("Flash Player 20: 6 isolated restarts, 4 authoring examples, actual RPG/M3 shots, invalid, missing and timed-out XML recovery.")


if __name__=="__main__":
    main()
