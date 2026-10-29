"use strict";
const fs=require("fs"),path=require("path"),crypto=require("crypto");
const {normalizeManifest}=require("../arena-calibration/lib/arena-calibration-core");
const {resolveExpectedRuntimeIdentity}=require("../lib/runtime-process-identity");
const ROOT=path.resolve(__dirname,"../..");
const hash=p=>crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex");
function make(config){
  if(!/^[a-z0-9-]{1,48}$/.test(config.experimentId||""))throw Error("Fresh bounded experiment id required");
  if(!Array.isArray(config.conditions)||config.conditions.length<1||config.conditions.length>12)throw Error("1..12 bounded conditions required");
  const frozen=JSON.parse(fs.readFileSync(config.baselinePlan,"utf8"));
  const sync=JSON.parse(fs.readFileSync(config.resourceSync,"utf8"));
  const workers=frozen.workers.map(w=>({workerId:w.workerId,projectRoot:w.projectRoot,candidateRoot:w.candidateRoot,seedPath:w.seedPath,resourcePaths:sync.resourcePaths}));
  if(workers.length!==2)throw Error("Exactly two independent workers required");
  const identities=workers.map(w=>resolveExpectedRuntimeIdentity(w.projectRoot,w.candidateRoot));
  for(const key of ["coreSha256","payloadClosure","buildIdentity"])
    if(identities[0][key]!==identities[1][key])throw Error("Mismatched candidate "+key);
  for(const row of sync.files)for(const w of workers)
    if(hash(path.join(w.projectRoot,row.path))!==row.after)throw Error("Resource drift "+row.path);
  const out=path.join(ROOT,"tmp","cf6-r9",config.experimentId);
  fs.mkdirSync(path.dirname(out),{recursive:true});fs.mkdirSync(out);
  const write=(name,value)=>{const p=path.join(out,name);fs.writeFileSync(p,JSON.stringify(value,null,2)+"\n",{flag:"wx"});return p;};
  const batches=[[],[]];let ordinal=0;
  for(const condition of config.conditions){
    if(!/^[a-z0-9-]+$/.test(condition.id))throw Error("Condition id required");
    const hp=condition.hp||24000,phase=condition.phase||2;
    for(const flip of condition.mirror===false?[false]:[false,true]){
      function unit(spec,side,id){
        if(!Number.isSafeInteger(spec.unitId)||spec.unitId<1)throw Error("Explicit unit id required");
        const parameters={长枪:"M4A1战术版",手枪:"FR506",手枪2:"FR506",
          hp_min:side==="blue"?hp/3:hp,hp_max:side==="blue"?hp/3:hp,
          速度_min:65,速度_max:65,空手攻击力_min:753,空手攻击力_max:753,
          基本防御力_min:705,基本防御力_max:705,装备防御力:0,躲闪率_min:10,躲闪率_max:10,
          韧性系数:50,基础韧性系数:50,重量:75,身高:175,
          特种兵初始阶段:phase,特种兵战术诊断:true,特种兵精英诊断:true,
          ...(spec.policy?{特种兵策略:spec.policy}:{}),...(spec.parameters||{})};
        return {type:`兵种${spec.unitId}`,level:60,sourceId:id,parameters};
      }
      const aSide=flip?"blue":"red",bSide=flip?"red":"blue";
      const a=unit(condition.a,aSide,"candidate"),b=unit(condition.b,bSide,"reference");
      batches[ordinal++%2].push({caseId:condition.id+(flip?"-a-blue":"-a-red"),repeat:1,
        timeoutFrames:condition.timeoutFrames||1800,spawnDistance:condition.spawnDistance||650,
        blueFormation:"line",redFormation:"line",formationSpacing:54,
        blueRoster:[flip?a:b],redRoster:[flip?b:a],tags:["cf6-r9","tactical-screen",condition.id],
        plannerReason:"同基础面板与装备；蓝方 hp_min/hp_max 除以 3 抵消标准佣兵生命加成，必须按实际出生面板诊断复核。策略消融使用相同教官身体与动作。",
        authorityContext:{condition:condition.id,candidateSide:aSide,a:condition.a,b:condition.b,
          initialPhase:phase,requestedHp:hp,blueHpCompensation:3,fullEffectivePanelEquality:"requires-live-panel-audit",
          noPairwiseRngClaim:true,attributeBoost:false,resourceBindings:sync.files.map(x=>({path:x.path,sha256:x.after}))}});
    }
  }
  if(batches.some(rows=>rows.length<1||rows.length>12))throw Error("Each worker must contain 1..12 runs");
  const jobs=batches.map((cases,index)=>({jobId:`tactics-w${index+1}`,workerId:workers[index].workerId,
    manifestPath:write(`worker-${index+1}.json`,normalizeManifest({batchId:`${config.experimentId}-w${index+1}`,
      planner:{name:"cf6-r9-tactical-screen",version:1},repeat:1,timeoutFrames:1800,cases})),batchTimeoutMs:900000}));
  const plan={schema:"arena-worker.experiment-plan.v1",experimentId:config.experimentId,workers,
    saveRoots:frozen.saveRoots,sharedObjectsRoot:frozen.sharedObjectsRoot,
    groups:[{groupId:"tactical-screen",mode:"parallel",condition:config.experimentId,
      visibility:"background-visible",performance:{preset:"performance",mode:"fixed",maxRenderHeight:180},jobs}],comparisons:[]};
  const planPath=write("experiment-plan.json",plan);write("declared-config.json",config);
  console.log(JSON.stringify({planPath,runs:ordinal,candidateIdentity:identities[0].buildIdentity}));
}
if(require.main===module){if(process.argv.length!==3)throw Error("Provide one explicit configuration JSON");make(JSON.parse(fs.readFileSync(process.argv[2],"utf8")));}
module.exports={make};
