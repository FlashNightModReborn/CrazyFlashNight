from pathlib import Path
import time,json,datetime,hashlib
base=Path(__file__).resolve().parent
roots=[Path('C:/Users/fs/.codex/worktrees')/w/'CrazyFlashNight' for w in ['headbot-combat','headbot-combat2']]
seen=set()
for file in base.glob('live-elder-audit-r*.jsonl'):
    for line in file.read_text(encoding='utf8').splitlines():
        if not line:continue
        row=json.loads(line)
        seen.add((str(Path(row['source']).parents[1]),row['line']))
seeded=len(seen);deadline=time.monotonic()+10800
with (base/'live-elder-audit-r12.jsonl').open('x',encoding='utf8') as output:
    while time.monotonic()<deadline and not (base/'stop-elder-audit-r12.marker').exists():
        for root in roots:
            for name in ['launcher.log','launcher.log.1']:
                p=root/'logs'/name
                if not p.is_file():continue
                try:lines=p.read_text(encoding='utf-8-sig',errors='replace').splitlines()
                except OSError:continue
                for line in lines:
                    if not any(tag in line for tag in ['[CF6_ELDER_PHASE_READY]','[CF6_ELDER_COMBAT_END]']):continue
                    key=(str(root),line)
                    if key in seen:continue
                    seen.add(key)
                    output.write(json.dumps({'observedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),
                        'source':str(p),'line':line,'lineSha256':hashlib.sha256(line.encode()).hexdigest()},ensure_ascii=False)+'\n')
                    output.flush()
        time.sleep(1)
print('R12 observer finished; prior unique events='+str(seeded)+'; new='+str(len(seen)-seeded))
