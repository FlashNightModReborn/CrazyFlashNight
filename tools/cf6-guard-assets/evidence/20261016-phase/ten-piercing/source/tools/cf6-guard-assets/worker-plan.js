"use strict";
// Two existing Arena Workers, one frozen body version, separate resources and saves.
const fs=require("fs"),path=require("path"),crypto=require("crypto"),cp=require("child_process");
const ROOT=path.resolve(__dirname,"../..");
const {normalizeManifest}=require("../arena-calibration/lib/arena-calibration-core");
const {resolveExpectedRuntimeIdentity}=require("../lib/runtime-process-identity");
const hash=p=>crypto.createHash("sha256").update(fs.readFileSync(path.toNamespacedPath(p))).digest("hex");
const write=(p,v)=>fs.writeFileSync(p,JSON.stringify(v,null,2)+"\n",{flag:"wx"});
const boundPaths=["flashswf/arts/new/Codex光头保安素材.swf","flashswf/arts/things-new.swf",
 "tools/cf6-guard-assets/GuardAI.as","tools/cf6-guard-assets/GuardTransform.as","tools/cf6-guard-assets/transform.py",
 "tools/cf6-guard-assets/native-manifest.json","tools/cf6-guard-assets/balance-inputs.json","flashswf/arts/new/Codex特种兵素材.swf","flashswf/arts/new/CodexWings素材.swf",
 "flashswf/arts/new/Codex专用素材.swf","tools/gamma-echo-assets/native-manifest.json","data/enemy_properties/γ-ECHO克隆兽.xml",
 "scripts/asLoader.swf","data/enemy_properties/CF6重制敌人.xml","data/units/units.json",
 "data/items/武器_长枪_突击步枪.xml","data/items/asset_source_map.xml",
 "scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as",
 "scripts/逻辑/单位函数/单位函数_lsy_主角技能.as","tools/cf6-soldier-assets/SoldierAI.as"];

function createPlan(config){
 if(!/^[a-z0-9][a-z0-9-]{0,47}$/.test(config.experimentId||""))throw Error("Fresh experimentId required");
 if(!path.isAbsolute(config.outputDirectory||"")||!path.resolve(config.outputDirectory).startsWith(path.join(ROOT,"tmp")+path.sep))
  throw Error("New absolute output directory in this checkout's tmp required");
 if(!Array.isArray(config.workers)||config.workers.length!==2)throw Error("Exactly two explicit Workers required");
 if(!path.isAbsolute(config.resourceListPath||""))throw Error("Explicit frozen resource list required");
 const resourceList=JSON.parse(fs.readFileSync(config.resourceListPath,"utf8"));
 const resourcePaths=resourceList.resourcePaths;
 if(!Array.isArray(resourcePaths)||!resourcePaths.length
  ||resourcePaths.some(p=>typeof p!=="string"||path.isAbsolute(p)||p.split(/[\\/]/).includes("..")))
  throw Error("Existing relative resource observation list required");
 for(const p of boundPaths.filter(p=>p.startsWith("flashswf/")))
  if(!resourcePaths.includes(p))throw Error("Missing observed combat resource: "+p);
 const sourceBindings=boundPaths.map(p=>({path:p,sha256:hash(path.join(ROOT,p))}));
 const workers=config.workers.map((w,i)=>{
  for(const key of ["projectRoot","candidateRoot","seedPath"])if(!path.isAbsolute(w[key]||""))throw Error("Explicit Worker "+key+" required");
  if(!path.resolve(w.candidateRoot).startsWith(path.join(path.resolve(w.projectRoot),"tmp/runtime-candidates/v2")+path.sep))throw Error("Owned candidate required");
  for(const r of sourceBindings)if(hash(path.join(w.projectRoot,r.path))!==r.sha256)throw Error("Worker input differs: "+r.path);
  return {...w,workerId:"guard-w0"+(i+1),resourcePaths};
 });
 if(path.resolve(workers[0].projectRoot).toLowerCase()===path.resolve(workers[1].projectRoot).toLowerCase())throw Error("Independent resource roots required");
 const identities=workers.map(w=>resolveExpectedRuntimeIdentity(w.projectRoot,w.candidateRoot));
 // Paths differ, but both processes must execute the same immutable binary payload.
 for(const field of ["coreSha256","buildIdentity","payloadClosure"])
  if(identities[0][field]!==identities[1][field])throw Error("Worker payloads differ: "+field);
 const profiles=config.profiles||[
  [30,60,99].map(level=>({level,side:"blue",weapon:"M4A1战术版"})),
  [30,60,99].map(level=>({level,side:"red",weapon:"M4A1战术版"}))
 ];
 const repeats=config.repeat===undefined?3:config.repeat;
 if(!Number.isSafeInteger(repeats)||repeats<1||repeats>3||profiles.length!==2
  ||profiles.some(p=>!Array.isArray(p)||p.length<1||p.length>8))throw Error("Bounded explicit profiles required");
 let expectedRows=0,enemyRows=0,friendlyRows=0;
 const output=path.resolve(config.outputDirectory);fs.mkdirSync(output,{recursive:true});
 const jobs=[];
 for(let wi=0;wi<workers.length;wi++){
  const worker=workers[wi],batchId=config.experimentId+"-w"+(wi+1);
  const cases=profiles[wi].map(({level,side,weapon,transform=false},index)=>{
   if(![30,60,99].includes(level)||!["red","blue"].includes(side)||typeof weapon!=="string"||!weapon)
    throw Error("Invalid guard comparison profile");
   expectedRows+=repeats;if(side==="red")enemyRows+=repeats;else friendlyRows+=repeats;
   if(typeof transform!=="boolean")throw Error("Explicit transformation switch must be boolean");
   const guard={type:"兵种468",level,sourceId:"guard-"+level,parameters:{光头保安变身:transform}};
   const soldier={type:"兵种466",level,sourceId:"soldier-"+level,parameters:{长枪:weapon,特种兵初始阶段:2}};
   return {caseId:"w"+(wi+1)+"-"+index+"-"+level+"-"+side,repeat:repeats,timeoutFrames:1800,
    blueRoster:[side==="blue"?guard:soldier],redRoster:[side==="red"?guard:soldier],
    spawnDistance:650,blueFormation:"line",redFormation:"line",formationSpacing:54,
    tags:["cf6-guard","piercing-shotgun","ordinary-soldier",side,transform?"tyrant-second-life":"humanoid-only"],
    plannerReason:side==="blue"?"双方均按普通敌人生命基线出战；保安明显较弱但应换走至少20%生命。":
     "反向阵营观察：友方特种兵受既有三倍生命补正，此组单独报告，不冒充同生命基线。",
    authorityContext:{revision:config.revision,candidateSide:side,unitId:468,stage:6,tier:3,transform,successorUnitId:transform?460:null,
     rivalUnitId:466,rivalStage:7,rivalTier:5,rivalPhase:2,weapon,
     guardHpMultiplier:1,soldierHpMultiplier:side==="red"?3:1,
     targetPosition:"clearly_below_ordinary_soldier_with_twenty_percent_exchange",sourceBindings}};
  });
  const manifest=normalizeManifest({batchId,buildCommit:cp.execFileSync("git",["rev-parse","HEAD"],{cwd:worker.projectRoot,encoding:"utf8",windowsHide:true}).trim(),
   planner:{name:"cf6-guard-two-worker-comparison",version:1},repeat:repeats,timeoutFrames:1800,cases});
  const manifestPath=path.join(output,"worker-"+(wi+1)+"-manifest.json");write(manifestPath,manifest);
  jobs.push({jobId:"guard-w"+(wi+1),workerId:worker.workerId,manifestPath,batchTimeoutMs:900000});
 }
 const plan={schema:"arena-worker.experiment-plan.v1",experimentId:config.experimentId,workers,
  saveRoots:[path.join(ROOT,"saves"),...workers.map(w=>path.join(w.projectRoot,"saves"))],
  sharedObjectsRoot:path.join(process.env.APPDATA,"Macromedia/Flash Player/#SharedObjects"),
  groups:[{groupId:"threat",mode:"parallel",condition:config.revision,visibility:"background-visible",
   performance:{preset:"performance",mode:"fixed",maxRenderHeight:180},jobs}],comparisons:[]};
 write(path.join(output,"experiment-plan.json"),plan);
 write(path.join(output,"input-identity.json"),{schema:"cf6-guard.worker-inputs.v1",sourceBindings,
  runtimeIdentities:identities,roles:["guard blue versus ordinary enemy soldier","guard red versus friendly soldier with triple HP, separate context"],
  expectedRows,enemyRows,friendlyRows,claimsNoSpeedBenchmark:true});
 return {planPath:path.join(output,"experiment-plan.json"),rows:expectedRows,workers:2};
}
if(require.main===module){if(process.argv.length!==3)throw Error("Usage: node worker-plan.js <explicit-config.json>");
 console.log(JSON.stringify(createPlan(JSON.parse(fs.readFileSync(process.argv[2],"utf8")))));}
module.exports={createPlan};
