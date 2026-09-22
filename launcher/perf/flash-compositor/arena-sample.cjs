// Bounded rendering experiment using the existing arena task and its canonical
// manifest normalizer. No balance apply, save seeding, or process lifecycle writes.
const fs=require('fs');
const path=require('path');
const crypto=require('crypto');
const cp=require('child_process');
const root=path.resolve(__dirname,'../../..');
const {normalizeManifest}=require(path.join(root,'tools/arena-calibration/lib/arena-calibration-core'));
const api=require(path.join(root,'tools/lib/legacy-http-client'));
const label=process.argv[2];
if(!/^[a-z0-9-]{1,36}$/.test(label||'')) throw Error('Usage: node launcher/perf/flash-compositor/arena-sample.cjs <run-label> [repeat=2]');
const repeat=Number(process.argv[3]||2);
if(!Number.isInteger(repeat)||repeat<1||repeat>3)throw Error('repeat must be 1..3');
const read=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const ctx=api.readExactLauncherHttpContext(root);
const pair=read(path.join(root,'tmp/flash-compositor/game/development-pair.json'));
for(const file of pair.files) if(sha(file.path)!==file.sha256.toLowerCase())throw Error('Development pair changed: '+file.path);
const exe=pair.files.find(f=>f.path.endsWith('.Core.exe')).path;
// Bind this localhost session to the verified developer apphost, not another Core.
const processPath=cp.execFileSync('powershell.exe',['-NoProfile','-Command',`(Get-Process -Id ${ctx.pid}).Path`],{encoding:'utf8',windowsHide:true}).trim();
if(processPath.toLowerCase()!==exe.toLowerCase())throw Error('API PID does not belong to the paired development apphost');
const batchId='render-'+label+'-'+Date.now();
const out=path.join(root,'tmp/flash-compositor',batchId);
fs.mkdirSync(out,{recursive:true});
const settings=read(path.join(root,'launcher/data/world-lighting/render-schedule.json'));
const roster=(ids,count)=>Array.from({length:count},(_,i)=>({type:'兵种'+ids[i%ids.length],level:30}));
const workload=[['melee',[45,48],12],['ranged',[44],12],['mixed',[44,45,48,49],20]];
const manifest=normalizeManifest({batchId,repeat,timeoutFrames:450,arenaMode:'calibration',
 planner:{name:'render-schedule-v1',version:1,reason:'Rendering samples only; short frame budget is intentional, not a balance qualification'},
 cases:workload.map(([caseId,ids,count])=>({caseId,blueRoster:roster(ids,count),redRoster:roster(ids,count),repeat,timeoutFrames:450,
  spawnDistance:500,blueFormation:'grid',redFormation:'grid',formationSpacing:45,tags:['render-performance'],plannerReason:'Fixed roster repeated; battle RNG is not fully seeded'}))});
const relative='tmp/arena-calibration/'+batchId+'.json';
fs.mkdirSync(path.join(root,'tmp/arena-calibration'),{recursive:true});
fs.writeFileSync(path.join(root,relative),JSON.stringify(manifest,null,2));
const logPath=path.join(root,'logs/launcher.log');
const beforeSamples=fs.readFileSync(logPath,'utf8').split(/\r?\n/).filter(l=>l.includes('event=render_sample'));
const initialScene=Number(beforeSamples.at(-1)?.match(/scene=(\d+)/)?.[1]??-1);
fs.writeFileSync(path.join(out,'context.json'),JSON.stringify({pid:ctx.pid,pair,settings,scriptSha256:sha(__filename),initialScene,manifestPath:relative,startedUtc:new Date().toISOString()},null,2));
const watermark=fs.statSync(logPath).size;
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function task(action,extra={}) {
 const route='/task';
 const response=await fetch(`http://localhost:${ctx.httpPort}${route}`,{method:'POST',headers:{'Content-Type':'application/json',...api.authorizationHeadersFor(ctx,route)},
  body:JSON.stringify({task:'arena_calibration',action,...extra}),signal:AbortSignal.timeout(20000)});
 const result=await response.json();
 if(!response.ok||result.success===false)throw Error(JSON.stringify(result));
 return result;
}
function summary(log) {
 const samples=[];
 for(const line of log.split(/\r?\n/)) {
  if(!line.includes('event=render_sample'))continue;
  const fields=Object.fromEntries([...line.matchAll(/(\w+)=([^ ]+)/g)].map(m=>[m[1],m[2]]));
  samples.push({at:line.slice(0,12),...fields});
 }
 const admitted=samples.filter(s=>s.admitted==='True' && Number(s.scene)!==initialScene);
 const total=(key,list)=>list.reduce((sum,s)=>sum+Number(s[key]),0);
 return {samples:samples.length,admittedSamples:admitted.length,gameFps:admitted.length?1000*total('frames',admitted)/total('ms',admitted):null,
  longFrames:total('longFrames',admitted),maxFrameMs:admitted.length?Math.max(...admitted.map(s=>Number(s.maxMs))):null,
  qualityCounts:Object.fromEntries([...new Set(admitted.map(s=>s.quality))].map(q=>[q,admitted.filter(s=>s.quality===q).length])),
  requests:log.split(/\r?\n/).filter(l=>l.includes('event=render_schedule_request')),
  resizes:log.split(/\r?\n/).filter(l=>l.includes('event=world_render_resize'))};
}
(async()=>{
 const before=await task('status');
 if(before.state==='running')throw Error('An arena batch is already running');
 // Unknown start outcome is not retried. Inspect the current task status on failure.
 const start=await task('startBatch',{manifestPath:relative});
 fs.writeFileSync(path.join(out,'start.json'),JSON.stringify(start,null,2));
 let status=start, delivered=-1;
 const deadline=Date.now()+15*60*1000;
 while(!['completed','failed','aborted'].includes(status.state)) {
  if(Date.now()>deadline){await task('abort',{batchId});throw Error('Bounded rendering sample deadline reached');}
  await sleep(2000); status=await task('status');
  if(status.batchId!==batchId)throw Error('Arena batch ownership changed');
  if(status.completedRuns!==delivered){console.log(JSON.stringify({batchId,state:status.state,completed:status.completedRuns,total:status.totalRuns,current:status.currentCaseId}));delivered=status.completedRuns;}
 }
 const data=fs.readFileSync(logPath); if(data.length<watermark)throw Error('Launcher log rotated during run');
 const log=data.subarray(watermark).toString('utf8');
 fs.writeFileSync(path.join(out,'launcher.log'),log);
 if(status.resultPath)fs.copyFileSync(path.resolve(root,status.resultPath),path.join(out,'arena-results.jsonl'));
 const metrics=summary(log);
 const renderFailures=log.split(/\r?\n/).filter(line=>line.includes('event=world_compositor_failed'));
 const validRenderingSamples=metrics.admittedSamples>=20 && renderFailures.length===0;
 const report={scope:'local-rendering-experiment',notBalanceQualification:true,validRenderingSamples,renderFailures,status,metrics,finishedUtc:new Date().toISOString()};
 fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));
 console.log(JSON.stringify({report:path.join(out,'report.json'),state:status.state,metrics:report.metrics}));
 if(status.state!=='completed'||!validRenderingSamples)process.exitCode=1;
})().catch(error=>{console.error(error.message);process.exitCode=1;});
