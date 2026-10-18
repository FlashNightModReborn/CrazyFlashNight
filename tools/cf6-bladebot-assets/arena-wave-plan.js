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
 if(config.variant!=="wave-combo")throw Error("Explicit wave-combo variant required");
 const levels=config.levels||[30,60,99],repeat=config.repeat===undefined?3:config.repeat;
 if(!Array.isArray(levels)||!levels.length||levels.length>3||new Set(levels).size!==levels.length||levels.some(n=>!Number.isInteger(n)||n<1||n>99))throw Error("Invalid levels");
 if(!Number.isInteger(repeat)||repeat<1||repeat>3)throw Error("repeat must be 1..3");
 const timeoutFrames=config.timeoutFrames===undefined?5400:config.timeoutFrames;
 if(!Number.isInteger(timeoutFrames)||timeoutFrames<1800||timeoutFrames>7200)throw Error("Invalid timeoutFrames");
 const rivals=config.rivals||["blackiron","arkclaw"];
 if(!Array.isArray(rivals)||!rivals.length||rivals.some(r=>!["blackiron","arkclaw"].includes(r))||new Set(rivals).size!==rivals.length)throw Error("Unsupported or repeated opponent");
 const boundPaths=["flashswf/arts/new/Codex大刀机器人素材.swf","flashswf/arts/things-new.swf",
  "flashswf/arts/new/素材库-诺亚新敌人.swf","scripts/asLoader.swf",
  "data/enemy_properties/CF6重制敌人.xml","data/enemy_properties/诺亚新敌人.xml",
  "data/units/units.json","data/items/asset_source_map.xml","launcher/web/modules/arena-unit-catalog.js",
  "tools/cf6-bladebot-assets/BladebotAI.as","tools/cf6-bladebot-assets/build.py",
  "tools/cf6-bladebot-assets/native-manifest.json","tools/cf6-bladebot-assets/balance-inputs.json",
  "scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as"];
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
  return {...w,projectRoot,workerId:"bladebot-w"+(index+1),resourcePaths};
 });
 if(new Set(workers.map(w=>w.projectRoot.toLowerCase())).size!==workers.length)throw Error("Independent resource roots required");
 const identities=workers.map(w=>resolveExpectedRuntimeIdentity(w.projectRoot,w.candidateRoot));
 for(const identity of identities){
  if(identity.runtimeMode!=="isolated_candidate")throw Error("Isolated candidate required");
  for(const key of ["coreSha256","buildIdentity","payloadClosure"])if(identity[key]!==identities[0][key])throw Error("Worker binary payloads differ");
 }
 const output=path.resolve(config.outputDirectory);fs.mkdirSync(output,{recursive:true});const groups=[];
 for(const rival of rivals)for(const level of levels){
  const rivalId=rival==="blackiron"?347:286;
  const jobs=workers.map((worker,wi)=>{
   const sides=workers.length===2?[wi===0?"blue":"red"]:["blue","red"];
   const cases=sides.map(side=>{
    const bladebot={type:"兵种465",level,sourceId:"bladebot-"+level};
    const reference={type:"兵种"+rivalId,level,sourceId:rival+"-"+level};
    return {caseId:"level"+level+"-"+side,repeat,timeoutFrames,spawnDistance:650,
     blueRoster:[side==="blue"?bladebot:reference],redRoster:[side==="red"?bladebot:reference],
     tags:["cf6-bladebot",rival,config.variant,side],
     plannerReason:"同等级交换阵营复验大刀的重劈击退接波光束；保留全部重复、胜负与超时。",
     authorityContext:{candidateUnitId:465,candidateSide:side,stage:8,tier:9,rivalUnitId:rivalId,level,
      variant:config.variant,sourceBindings,targetPosition:rival==="blackiron"?"stable_wins":"meaningful_threat"}};
   });
   const buildCommit=cp.execFileSync("git",["rev-parse","HEAD"],{cwd:worker.projectRoot,encoding:"utf8",windowsHide:true}).trim();
   const batchId=config.experimentId+"-"+rival+"-l"+level+"-w"+(wi+1);
   const manifest=normalizeManifest({batchId,buildCommit,planner:{name:"cf6-bladebot-wave-"+rival,version:2},repeat:1,timeoutFrames,cases});
   const manifestPath=path.join(output,rival+"-level"+level+"-w"+(wi+1)+"-manifest.json");write(manifestPath,manifest);
   return {jobId:rival+"-level"+level+"-w"+(wi+1),workerId:worker.workerId,manifestPath,batchTimeoutMs:900000};
  });
  groups.push({groupId:rival+"-level"+level,mode:workers.length===2?"parallel":"serial",condition:config.variant,
   visibility:"background-visible",performance:{preset:"performance",mode:"fixed",maxRenderHeight:180},jobs});
 }
 const plan={schema:"arena-worker.experiment-plan.v1",experimentId:config.experimentId,workers,
  saveRoots:[path.join(ROOT,"saves"),...workers.map(w=>path.join(w.projectRoot,"saves"))],
  sharedObjectsRoot:path.join(process.env.APPDATA,"Macromedia","Flash Player","#SharedObjects"),groups,comparisons:[]};
 const planPath=path.join(output,"experiment-plan.json");write(planPath,plan);
 write(path.join(output,"input-identity.json"),{sourceBindings,runtimeIdentities:identities,levels,repeat,timeoutFrames,variant:config.variant,rivals,expectedRows:rivals.length*levels.length*2*repeat,performanceQualification:false});
 return {planPath,rows:rivals.length*levels.length*2*repeat,workers:workers.length};
}
if(require.main===module){if(process.argv.length!==3)throw Error("Usage: node arena-plan.js <explicit-config.json>");console.log(JSON.stringify(createPlan(JSON.parse(fs.readFileSync(process.argv[2],"utf8")))));}
module.exports={createPlan};