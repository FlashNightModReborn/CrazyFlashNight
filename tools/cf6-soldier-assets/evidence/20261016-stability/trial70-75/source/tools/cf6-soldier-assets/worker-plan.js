"use strict";
// Two existing Arena Workers, one frozen body version, separate resources and saves.
const fs=require("fs"),path=require("path"),crypto=require("crypto"),cp=require("child_process");
const ROOT=path.resolve(__dirname,"../..");
const {normalizeManifest}=require("../arena-calibration/lib/arena-calibration-core");
const {resolveExpectedRuntimeIdentity}=require("../lib/runtime-process-identity");
const hash=p=>crypto.createHash("sha256").update(fs.readFileSync(path.toNamespacedPath(p))).digest("hex");
const write=(p,v)=>fs.writeFileSync(p,JSON.stringify(v,null,2)+"\n",{flag:"wx"});
const boundPaths=["flashswf/arts/new/Codex特种兵素材.swf","flashswf/arts/new/CodexWings素材.swf",
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
 const tuningSource=fs.readFileSync(path.join(ROOT,"tools/cf6-soldier-assets/SoldierAI.as"),"utf8"),fireControl={};
 for(const name of ["maximumFireFrames","shootRestFrames","shieldDamageReductionPercent"]){
  const matches=[...tuningSource.matchAll(new RegExp("\\b"+name+"\\s*:\\s*(\\d+)","g"))];
  if(matches.length!==1||!Number.isSafeInteger(Number(matches[0][1]))||Number(matches[0][1])<=0)
   throw Error("One explicit positive AS2 fire-control value required: "+name);
  fireControl[name]=Number(matches[0][1]);
 }
 const workers=config.workers.map((w,i)=>{
  for(const key of ["projectRoot","candidateRoot","seedPath"])if(!path.isAbsolute(w[key]||""))throw Error("Explicit Worker "+key+" required");
  if(!path.resolve(w.candidateRoot).startsWith(path.join(path.resolve(w.projectRoot),"tmp/runtime-candidates/v2")+path.sep))throw Error("Owned candidate required");
  for(const r of sourceBindings)if(hash(path.join(w.projectRoot,r.path))!==r.sha256)throw Error("Worker input differs: "+r.path);
  return {...w,workerId:"soldier-w0"+(i+1),resourcePaths};
 });
 if(path.resolve(workers[0].projectRoot).toLowerCase()===path.resolve(workers[1].projectRoot).toLowerCase())throw Error("Independent resource roots required");
 const identities=workers.map(w=>resolveExpectedRuntimeIdentity(w.projectRoot,w.candidateRoot));
 // Paths differ, but both processes must execute the same immutable binary payload.
 for(const field of ["coreSha256","buildIdentity","payloadClosure"])
  if(identities[0][field]!==identities[1][field])throw Error("Worker payloads differ: "+field);
 const profiles=config.profiles||[
  [30,60,99].map(level=>({level,side:"red",weapon:"M4A1战术版"})).concat([{level:60,side:"blue",weapon:"M4A1战术版"}]),
  ["M4A1改","AK74战术版","DD MK18战术版","M4A1战术版"].map(weapon=>({level:60,side:"red",weapon}))
 ];
 const repeats=config.repeat===undefined?3:config.repeat;
 if(!Number.isSafeInteger(repeats)||repeats<1||repeats>3||profiles.length!==2
  ||profiles.some(p=>!Array.isArray(p)||p.length<1||p.length>8))throw Error("Bounded explicit profiles required");
 let expectedRows=0,enemyRows=0,friendlyRows=0;
 const output=path.resolve(config.outputDirectory);fs.mkdirSync(output,{recursive:true});
 const jobs=[];
 for(let wi=0;wi<workers.length;wi++){
  const worker=workers[wi],batchId=config.experimentId+"-w"+(wi+1);
  const cases=profiles[wi].map(({level,side,weapon,unitId=466,initialPhase,shieldReductionPercent},index)=>{
   if(![466,467].includes(unitId)||![30,60,99].includes(level)||!["red","blue"].includes(side)
    ||typeof weapon!=="string"||!weapon||initialPhase!==undefined&&![1,2].includes(initialPhase)
    ||shieldReductionPercent!==undefined&&(!Number.isFinite(shieldReductionPercent)||shieldReductionPercent<0||shieldReductionPercent>99))throw Error("Invalid soldier profile");
   expectedRows+=repeats;if(side==="red")enemyRows+=repeats;else friendlyRows+=repeats;
   const effectivePhase=initialPhase===undefined?(unitId===467?1:2):initialPhase;
   const parameters={长枪:weapon};if(initialPhase!==undefined)parameters.特种兵初始阶段=initialPhase;
   if(shieldReductionPercent!==undefined)parameters.特种兵持盾减伤率=shieldReductionPercent;
   const soldier={type:"兵种"+unitId,level,sourceId:"soldier-"+level,parameters};
   const wings={type:"兵种464",level,sourceId:"wings-"+level};
   return {caseId:"w"+(wi+1)+"-"+index+"-"+level+"-"+side,repeat:repeats,timeoutFrames:1800,
    blueRoster:[side==="blue"?soldier:wings],redRoster:[side==="red"?soldier:wings],
    spawnDistance:650,blueFormation:"line",redFormation:"line",formationSpacing:54,
    tags:["cf6-soldier","bounded-fire","wings-threat",side],
    plannerReason:side==="red"?(effectivePhase===1?"完整持盾两阶段预设略强于Wings；固定长枪同级对照，实际结果单独核验。":"普通二阶段仍以低于Wings且能造成明显威胁为目标；固定长枪同级对照。"):
     "友方人形三倍生命加成单列观察，不参与敌方本体定位判定。",
    authorityContext:{revision:config.revision,...fireControl,candidateSide:side,unitId,
     initialPhase:effectivePhase,shieldDamageReductionPercent:effectivePhase===1?(shieldReductionPercent===undefined?fireControl.shieldDamageReductionPercent:shieldReductionPercent):0,
     targetPosition:effectivePhase===1?"slightly_above_wings":"below_wings",
     ordinaryEnemyBalanceBasis:side==="red"&&effectivePhase===2,stage:7,tier:5,rivalStage:7,rivalTier:8,weapon,sourceBindings}};
  });
  const manifest=normalizeManifest({batchId,buildCommit:cp.execFileSync("git",["rev-parse","HEAD"],{cwd:worker.projectRoot,encoding:"utf8",windowsHide:true}).trim(),
   planner:{name:"cf6-soldier-two-worker-threat",version:2},repeat:repeats,timeoutFrames:1800,cases});
  const manifestPath=path.join(output,"worker-"+(wi+1)+"-manifest.json");write(manifestPath,manifest);
  jobs.push({jobId:"soldier-w"+(wi+1),workerId:worker.workerId,manifestPath,batchTimeoutMs:900000});
 }
 const plan={schema:"arena-worker.experiment-plan.v1",experimentId:config.experimentId,workers,
  saveRoots:[path.join(ROOT,"saves"),...workers.map(w=>path.join(w.projectRoot,"saves"))],
  sharedObjectsRoot:path.join(process.env.APPDATA,"Macromedia/Flash Player/#SharedObjects"),
  groups:[{groupId:"threat",mode:"parallel",condition:config.revision,visibility:"background-visible",
   performance:{preset:"performance",mode:"fixed",maxRenderHeight:180},jobs}],comparisons:[]};
 write(path.join(output,"experiment-plan.json"),plan);
 write(path.join(output,"input-identity.json"),{schema:"cf6-soldier.worker-inputs.v1",sourceBindings,
  runtimeIdentities:identities,fireControl,roles:["enemy body calibration","friendly HP multiplier reported separately"],
  expectedRows,enemyRows,friendlyRows,claimsNoSpeedBenchmark:true});
 return {planPath:path.join(output,"experiment-plan.json"),rows:expectedRows,workers:2};
}
if(require.main===module){if(process.argv.length!==3)throw Error("Usage: node worker-plan.js <explicit-config.json>");
 console.log(JSON.stringify(createPlan(JSON.parse(fs.readFileSync(process.argv[2],"utf8")))));}
module.exports={createPlan};
