from pathlib import Path
import datetime, importlib.util, json
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';P=R/'tools/cf6-elder-assets/evidence/20261017-calibration'
spec=importlib.util.spec_from_file_location('evidence',R/'tmp/cf6-elder-20261016/evidence_utils.py');u=importlib.util.module_from_spec(spec);spec.loader.exec_module(u)
state=u.js(O/'evidence-history-assembly.json');package=u.Package(P);package.mapping=state['mapping']
analysis=u.js(P/'history/r20-pilot-awake/phase-aware-summary.json')
draws=[r for r in analysis['rows'] if r['status']=='finished' and not r['won'] and not r['lost']]
assert len(draws)==1 and draws[0]['level']==99 and draws[0]['rival']==361 and draws[0]['side']=='red'
assert sum(r['won'] for r in analysis['rows'])==4 and sum(r['lost'] for r in analysis['rows'])==7
assert not (P/'integrity.json').exists()
readme=R/'tools/cf6-elder-assets/README.md';package.copy(readme,'progress-snapshots/README-before-r20-draw-clarification.md.txt')
text=readme.read_text('utf8');old='十二场独立试跑已完成，为 7 负、4 胜、0 超时；';new='十二场独立试跑已完成，为 7 负、4 胜、1 平、0 超时；'
assert text.count(old)==1;readme.write_text(text.replace(old,new),'utf8',newline='\n')
path=P/'range-support-r20/summary.json';package.copy(path,'progress-snapshots/r20-before-draw-clarification.json');value=u.js(path);value['pilotDraws']=1;path.write_text(json.dumps(value,ensure_ascii=False,indent=2),'utf8')
package.copy(P/'summary.json','progress-snapshots/20261018-before-r20-draw-clarification.json')
summary=u.js(P/'summary.json');summary['elder'].update(latestWins=4,latestLosses=7,latestDraws=1,latestTimeouts=0)
summary['updatedAtUtc']=datetime.datetime.now(datetime.timezone.utc).isoformat();(P/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),'utf8')
u.jput(P/'history/r20-pilot-awake/draw-clarification.json',{'wins':4,'losses':7,'draws':1,'timeouts':0,'drawRows':draws,'boundary':'The original phase-aware rows already had won=false and lost=false for the simultaneous-death result. The temporary progress output omitted draws and the first commentary misclassified the non-win total as losses. Original results are unchanged; the completed collector had counted seven losses correctly but did not print a draw field. Full strength acceptance already requires every row to be a finished loss.'})
package.copy(O/'clarify-r20-draw.py','history/r20-pilot-awake/support/clarify-r20-draw.py')
u.jput(P/'history/r20-pilot-awake/support/full-matrix-not-started.json',{'fullMatrixGenerated':False,'fullMatrixExecuted':False,'reason':'Four wins and one draw; low and middle Beast groups below the target and EXUSIAI groups too strong. Preserve all twelve observations and select another authorized shield tuning step.'})
state['mapping']=package.mapping;(O/'evidence-history-assembly.json').write_text(json.dumps(state,ensure_ascii=False,indent=2),'utf8')
print(json.dumps({'wins':4,'losses':7,'draws':1,'timeouts':0,'originalRowsUnchanged':True}))
