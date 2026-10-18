"use strict";
// Same-level repeated matchups with explicit frozen resources and isolated saves.
const fs=require("fs"),path=require("path"),cp=require("child_process"),crypto=require("crypto");
const {normalizeManifest}=require("../arena-calibration/lib/arena-calibration-core");
const {resolveExpectedRuntimeIdentity}=require("../lib/runtime-process-identity");
const ROOT=path.resolve(__dirname,"../..");
const hash=p=>crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex");
const write=(p,v)=>fs.writeFileSync(p,JSON.stringify(v,null,2)+"\n",{flag:"wx"});
function createPlan(config){
 if(!/^[a-z0-9][a-z0-9-]{0,47}$/.test(config.experimentId||""))throw Error("Fresh experimentId required");
 if(!path.isAbsolute(config.outputDirectory||"")||!path.resolve(config.outputDirectory).startsWith(path.join(ROOT,"tmp")+path.sep))throw Error("Owned output directory required");
 if(!["physical","wave"].includes(config.variant))throw Error("Explicit physical / wave variant required");
 const levels=config.levels||[30,60,99],repeat=config.repeat===undefined?3:config.repeat;
 if(!Array.isArray(levels)||!levels.length||levels.length>3||new Set(levels).size!==levels.length||levels.some(n=>!Number.isInteger(n)||n<1||n>99))throw Error("Invalid levels");
 if(!Number.isInteger(repeat)||repeat<1||repeat>3)throw Error("repeat must be 1..3");
 const rival=config.rival||"arkclaw";
 if(!["arkclaw","bladebot"].includes(rival))throw Error("Unsupported reference opponent");
 const rivalId=rival==="arkclaw"?286:465;
 const boundPaths=["flashswf/arts/new/Codex大头机器人素材.swf","flashswf/arts/things-new.swf",
  rival==="arkclaw"?"flashswf/arts/new/素材库-诺亚新敌人.swf":"flashswf/arts/new/Codex大刀机器人素材.swf",
  "scripts/asLoader.swf","data/enemy_properties/CF6重制敌人.xml","data/enemy_properties/诺亚新敌人.xml",
  "data/units/units.json","data/items/asset_source_map.xml","launcher/web/modules/arena-unit-catalog.js",
  "tools/cf6-headbot-assets/HeadbotAI.as","tools/cf6-headbot-assets/build.py",
  "tools/cf6-headbot-assets/native-manifest.json","tools/cf6-headbot-assets/balance-inputs.json"];
 const sourceBindings=boundPaths.map(p=>({path:p,sha256:hash(path.join(ROOT,p))}));
 const specifications=config.workers||[{projectRoot:config.projectRoot,candidateRoot:config.candidateRoot,seedPath:config.seedPath}];
 if(!Array.isArray(specifications)||specifications.length<1||specifications.length>2)throw Error("One or two owned Workers required");
 const workers=specifications.map((w,index)=>{
  for(const key of ["projectRoot","candidateRoot","seedPath"])if(!path.isAbsolute(w[key]||""))throw Error("Explicit Worker "+key+" required");
  const projectRoot=path.resolve(w.projectRoot);
  if(!path.resolve(w.candidateRoot).startsWith(path.join(projectRoot,"tmp/runtime-candidates/v2")+path.sep))throw Error("Owned candidate required");
  for(const row of sourceBindings)if(hash(path.join(projectRoot,row.path))!==row.sha256)throw Error("Worker input differs: "+row.path);
  const paths=cp.execFileSync("git",["ls-files","-z","--cached","--others","--exclude-standard","--","flashswf","sound","sounds","music","font","fonts"],{cwd:projectRoot,maxBuffer:32*1024*1024,windowsHide:true}).toString("utf8").split("\0");
  const resourcePaths=[...new Set(paths.filter(p=>/^flashswf\//.test(p)&&/\.(swf|png|jpg|jpeg|webp|mp3|wav|ogg|mp4|flv|f4v)$/i.test(p)||/^(sounds?|music|fonts?)\//.test(p)))];
  return {...w,projectRoot,workerId:"headbot-w"+(index+1),resourcePaths};
 });
 if(new Set(workers.map(w=>w.projectRoot.toLowerCase())).size!==workers.length)throw Error("Independent resource roots required");
 const identities=workers.map(w=>resolveExpectedRuntimeIdentity(w.projectRoot,w.candidateRoot));
 for(const identity of identities){
  if(identity.runtimeMode!=="isolated_candidate")throw Error("Isolated candidate required");
  for(const key of ["coreSha256","buildIdentity","payloadClosure"])if(identity[key]!==identities[0][key])throw Error("Worker binary payloads differ");
 }
 const output=path.resolve(config.outputDirectory);fs.mkdirSync(output,{recursive:true});const groups=[];
 for(const level of levels){
  const jobs=workers.map((worker,wi)=>{
   const sides=workers.length===2?[wi===0?"blue":"red"]:["blue","red"];
   const cases=sides.map(side=>{
    const headbot={type:"兵种472",level,sourceId:"headbot-"+level};
    const reference={type:"兵种"+rivalId,level,sourceId:rival+"-"+level};
    return {caseId:"level"+level+"-"+side,repeat,timeoutFrames:3600,spawnDistance:650,
     blueRoster:[side==="blue"?headbot:reference],redRoster:[side==="red"?headbot:reference],
     tags:["cf6-headbot",rival,config.variant,side],
     plannerReason:rival==="arkclaw"?"同等级、交换阵营检验大头机器人稳定击败方舟爪豪的定位；保留全部重复、败局与超时。":"保留初版接入对照。",
     authorityContext:{candidateUnitId:472,candidateSide:side,stage:7,tier:16,rivalUnitId:rivalId,level,
      variant:config.variant,sourceBindings,targetPosition:rival==="arkclaw"?"stable_wins_over_arkclaw":"integration_only"}};
   });
   const buildCommit=cp.execFileSync("git",["rev-parse","HEAD"],{cwd:worker.projectRoot,encoding:"utf8",windowsHide:true}).trim();
   const batchId=config.experimentId+"-l"+level+"-w"+(wi+1);
   const manifest=normalizeManifest({batchId,buildCommit,planner:{name:"cf6-headbot-"+rival,version:2},repeat:1,timeoutFrames:3600,cases});
   const manifestPath=path.join(output,"level"+level+"-w"+(wi+1)+"-manifest.json");write(manifestPath,manifest);
   return {jobId:"level"+level+"-w"+(wi+1),workerId:worker.workerId,manifestPath,batchTimeoutMs:900000};
  });
  groups.push({groupId:"level"+level,mode:workers.length===2?"parallel":"serial",condition:config.variant,
   visibility:"background-visible",performance:{preset:"performance",mode:"fixed",maxRenderHeight:180},jobs});
 }
 const plan={schema:"arena-worker.experiment-plan.v1",experimentId:config.experimentId,workers,
  saveRoots:[path.join(ROOT,"saves"),...workers.map(w=>path.join(w.projectRoot,"saves"))],
  sharedObjectsRoot:path.join(process.env.APPDATA,"Macromedia","Flash Player","#SharedObjects"),groups,comparisons:[]};
 const planPath=path.join(output,"experiment-plan.json");write(planPath,plan);
 write(path.join(output,"input-identity.json"),{sourceBindings,runtimeIdentities:identities,levels,repeat,variant:config.variant,rivalId,expectedRows:levels.length*2*repeat,performanceQualification:false});
 return {planPath,rows:levels.length*2*repeat,workers:workers.length};
}
if(require.main===module){if(process.argv.length!==3)throw Error("Usage: node arena-plan.js <explicit-config.json>");console.log(JSON.stringify(createPlan(JSON.parse(fs.readFileSync(process.argv[2],"utf8")))));}
module.exports={createPlan};