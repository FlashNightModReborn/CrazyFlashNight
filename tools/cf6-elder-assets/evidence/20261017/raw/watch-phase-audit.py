from pathlib import Path
import time,json,datetime,hashlib
base=Path(__file__).resolve().parent
roots=[Path("C:/Users/fs/.codex/worktrees")/w/"CrazyFlashNight" for w in ["headbot-combat","headbot-combat2"]]
seen=set(); deadline=time.monotonic()+10800
with (base/"live-phase-audit.jsonl").open("x",encoding="utf-8") as output:
    while time.monotonic()<deadline and not (base/"stop-phase-audit.marker").exists():
        for root in roots:
            for name in ["launcher.log","launcher.log.1"]:
                p=root/"logs"/name
                if not p.is_file():continue
                try:lines=p.read_text(encoding="utf-8-sig",errors="replace").splitlines()
                except OSError:continue
                for line in lines:
                    if "[CF6_ELDER_PHASE_READY]" not in line:continue
                    key=(str(root),line)
                    if key in seen:continue
                    seen.add(key)
                    row={"observedAt":datetime.datetime.now(datetime.timezone.utc).isoformat(),"source":str(p),"line":line,"lineSha256":hashlib.sha256(line.encode()).hexdigest()}
                    output.write(json.dumps(row,ensure_ascii=False)+"\n");output.flush()
        time.sleep(1)
print("Phase audit observer finished; events="+str(len(seen)))
