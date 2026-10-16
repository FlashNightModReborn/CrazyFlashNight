"use strict";
// Bounded ordinary-window cases; inputs and save targets must be explicit.
const fs=require("fs"),path=require("path"),cp=require("child_process"),crypto=require("crypto");
const {normalizeManifest}=require("../arena-calibration/lib/arena-calibration-core");
const ROOT=path.resolve(__dirname,"../..");
const hash=file=>crypto.createHash("sha256").update(fs.readFileSync(path.toNamespacedPath(file))).digest("hex");
const write=(file,data)=>fs.writeFileSync(file,JSON.stringify(data,null,2)+"\n",{flag:"wx"});

function createPlans(config) {
  for(const key of ["resourceRoot","candidateRoot","outputDirectory"])
    if(!path.isAbsolute(config[key]||""))throw Error("Explicit absolute "+key+" required");
  const output=path.resolve(config.outputDirectory),temporary=path.join(ROOT,"tmp")+path.sep;
  if(!output.startsWith(temporary))throw Error("Plans belong to this checkout's tmp directory");
  if(!/^[a-z0-9][a-z0-9-]{0,35}$/.test(config.experimentId||""))throw Error("Fresh bounded experimentId required");
  const resourceRoot=path.resolve(config.resourceRoot),candidateRoot=path.resolve(config.candidateRoot);
  if(!candidateRoot.startsWith(path.join(resourceRoot,"tmp/runtime-candidates/v2")+path.sep))
    throw Error("Only an explicit isolated candidate is accepted");
  const buildCommit=cp.execFileSync("git",["rev-parse","HEAD"],{cwd:resourceRoot,encoding:"utf8",windowsHide:true}).trim();
  const sourceSwf="flashswf/arts/new/Codex特种兵素材.swf";
  const identity={sourceSwf,sourceSwfSha256:hash(path.join(resourceRoot,sourceSwf)),
    aiSourceSha256:hash(path.join(resourceRoot,"tools/cf6-soldier-assets/SoldierAI.as")),stage:7,tier:5,
    dataPath:"data/enemy_properties/CF6重制敌人.xml",dataSha256:hash(path.join(resourceRoot,"data/enemy_properties/CF6重制敌人.xml")),
    rivalDataPath:"data/enemy_properties/大学.xml",rivalDataSha256:hash(path.join(resourceRoot,"data/enemy_properties/大学.xml")),
    rivalSwfSha256:hash(path.join(resourceRoot,"flashswf/arts/new/大学人员.swf")),
    asLoaderSha256:hash(path.join(resourceRoot,"scripts/asLoader.swf")),
    rifleDataSha256:hash(path.join(resourceRoot,"data/items/武器_长枪_突击步枪.xml")),
    weaponSource:"shared cadet long-gun pool; explicit unit parameters take priority",
    sharedSwfSha256:hash(path.join(resourceRoot,"flashswf/arts/things-new.swf")),
    evidenceLane:"interactive_candidate"};
  const actor=(id,level,sourceId,weapon)=>({type:"兵种"+id,level,sourceId,
    ...(weapon?{parameters:{"长枪":weapon}}:{})});
  const casesFor=(level,count=1,mirror=false)=>["blue","red"].map(side=>{
    const candidates=Array.from({length:count},(_,i)=>actor(466,level,"soldier-"+level+"-"+i));
    const rivals=Array.from({length:count},(_,i)=>actor(mirror?466:449,level,(mirror?"mirror":"cadet")+"-"+level+"-"+i));
    const kind=mirror?"mirror":count>1?"squad":"cadet";
    return {caseId:kind+"-"+level+"-"+side,blueRoster:side==="blue"?candidates:rivals,
      redRoster:side==="red"?candidates:rivals,repeat:1,timeoutFrames:3600,spawnDistance:650,
      blueFormation:"line",redFormation:"line",formationSpacing:54,
      tags:["cf6-soldier",kind,side],
      plannerReason:mirror?"同配置同等级交换位置，观察动作与自然结算。":"同等级交换红蓝，对照军校生的持枪实战；不改军校生配置。",
      authorityContext:{...identity,comparison:kind,candidateSide:side,unitsPerSide:count}};
  });
  const configured=(side,squad)=>{
    const candidates=squad?[actor(466,60,"soldier-m16","M4A1改"),actor(466,60,"soldier-ak74","AK74战术版")]
      :[actor(466,60,"soldier-external","AK47#4")];
    const rivals=squad?[actor(449,60,"cadet-m4","M4A1战术版"),actor(449,60,"cadet-mk18","DD MK18战术版")]
      :[actor(449,60,"cadet-reference")];
    return {caseId:(squad?"configured-squad":"external-ak47")+"-"+side,
      blueRoster:side==="blue"?candidates:rivals,redRoster:side==="red"?candidates:rivals,
      repeat:1,timeoutFrames:3600,spawnDistance:650,blueFormation:"line",redFormation:"line",formationSpacing:54,
      tags:["cf6-soldier","standard-weapons",side],
      plannerReason:"验证外部指定长枪、真实枪口和标准耗弹装填；双方维持既有友军属性规则。",
      authorityContext:{...identity,candidateSide:side,unitsPerSide:squad?2:1,explicitLoadout:true}};
  };
  const batches=[{key:"weapons",cases:[...casesFor(30),configured("blue",false),configured("red",false),
    configured("blue",true),configured("red",true)]}];
  fs.mkdirSync(output,{recursive:true});const plans=[];
  for(const batch of batches) {
    const batchId=config.experimentId+"-"+batch.key;
    const manifest=normalizeManifest({batchId,buildCommit,planner:{name:"cf6-soldier-development",version:1},
      repeat:1,timeoutFrames:3600,cases:batch.cases});
    const worst=manifest.cases.reduce((sum,row)=>sum+row.repeat*row.timeoutFrames/30*1000,0);
    if(worst>780000||manifest.cases.reduce((sum,row)=>sum+row.repeat,0)>25)throw Error("Split the bounded batch");
    const manifestPath=path.join(output,batch.key+"-manifest.json");write(manifestPath,manifest);
    const slot="cf7_agent_"+batchId.replace(/-/g,"_");
    const evidenceConfigPath=path.join(output,batch.key+"-evidence-config.json");
    write(evidenceConfigPath,{resourceRoot,candidateRoot,manifestPath,slot});
    plans.push({batchId,manifestPath,evidenceConfigPath,slot,cases:manifest.cases.length,worstCaseCombatMs:worst});
  }
  const plan={schema:"cf6-soldier.foreground-plan.v1",source:identity,plans,
    boundaries:["Ordinary visible-window candidate; no background performance qualification.",
      "Fresh dedicated slots and frozen resources required; no automatic retries or result relabeling.",
      "Uses standard long-gun equipment and the cadet default pool. NPC reload does not consume player inventory."]};
  write(path.join(output,"plan.json"),plan);return plan;
}
if(require.main===module) {
  if(process.argv.length!==3)throw Error("Usage: node arena-plan.js <explicit-config.json>");
  console.log(JSON.stringify(createPlans(JSON.parse(fs.readFileSync(process.argv[2],"utf8"))),null,2));
}
module.exports={createPlans};
