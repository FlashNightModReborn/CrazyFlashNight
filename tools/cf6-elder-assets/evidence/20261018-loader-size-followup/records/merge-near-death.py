from pathlib import Path
import hashlib,json
D=Path.cwd()/'tmp/cf6-combat-calibration-20261017/loader-size-followup'
names=['beast-near-death-primary.json','beast-near-death-retry.json']
parts=[json.loads((D/n).read_text('utf8')) for n in names]
assert [len(p['rows']) for p in parts]==[10,2]
assert all(p['wholeExperimentFinal'] and not p['unattributedNotifications'] for p in parts)
assert parts[0]['sourceContract']==parts[1]['sourceContract']
rows=sum([p['rows'] for p in parts],[])
assert len({(r['rival'],r['level'],r['side'],r['runId']) for r in rows})==12
out={'wholeExperimentFinal':True,'combinedEvidence':True,'rows':rows,
    'observedBeastRageNotifications':sum(p['observedBeastRageNotifications'] for p in parts),
    'unattributedNotifications':[],'sourceContract':parts[0]['sourceContract'],
    'sourceReports':[{'file':n,'sha256':hashlib.sha256((D/n).read_bytes()).hexdigest()} for n in names],
    'boundary':'Union of unchanged primary ten completed rows and fresh retry two completed rows. The failed no-result primary shard remains in its original unqualified execution report.'}
with (D/'beast-near-death.json').open('x',encoding='utf8') as f:json.dump(out,f,ensure_ascii=False,indent=2)
print(json.dumps({'rows':12,'observedBeastRageNotifications':out['observedBeastRageNotifications']}))
