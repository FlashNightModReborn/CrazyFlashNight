"use strict";
// Same-level development matchups with explicit frozen resources and isolated saves.
const fs=require("fs"),path=require("path"),cp=require("child_process"),crypto=require("crypto");
const {normalizeManifest}=require("../arena-calibration/lib/arena-calibration-core");
const ROOT=path.resolve(__dirname,"../..");
const sha=file=>crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
const write=(file,value)=>{fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,JSON.stringify(value,null,2)+"\n",{flag:"wx"});};

function createPlan(config) {
  if(!config || !["pilot","confirm"].includes(config.mode))throw Error("mode must be pilot or confirm");
  if(!/^[a-z0-9][a-z0-9-]{0,47}$/.test(config.experimentId||""))throw Error("Use a fresh ASCII experimentId");
  for(const key of ["projectRoot","candidateRoot","seedPath"])if(!path.isAbsolute(config[key]||""))throw Error("Explicit absolute "+key+" required");
  const levels=config.levels||[30,60,99],repeat=config.repeat===undefined?3:config.repeat;
  if(!Array.isArray(levels)||!levels.length||levels.length>3||new Set(levels).size!==levels.length||levels.some(n=>!Number.isInteger(n)||n<1||n>99))throw Error("Invalid levels");
  if(!Number.isInteger(repeat)||repeat<1||repeat>3)throw Error("repeat must be 1..3");
  const spawnDistance=config.spawnDistance===undefined?650:config.spawnDistance;
  if(!Number.isInteger(spawnDistance)||spawnDistance<360||spawnDistance>1000)throw Error("spawnDistance must be 360..1000");
  const timeoutFrames=config.timeoutFrames===undefined?3600:config.timeoutFrames;
  if(!Number.isInteger(timeoutFrames)||timeoutFrames<1800||timeoutFrames>8100)throw Error("Invalid timeoutFrames");
  const resourceRoot=config.projectRoot,directory=path.join(ROOT,"tmp/cf6-bladebot-20261015",config.experimentId);
  const buildCommit=cp.execFileSync("git",["rev-parse","HEAD"],{cwd:resourceRoot,encoding:"utf8",windowsHide:true}).trim();
  const sourceSwf="flashswf/arts/new/Codex大刀机器人素材.swf";
  const identity={sourceSwf,sourceSwfSha256:sha(path.join(resourceRoot,sourceSwf)),
    aiSourceSha256:sha(path.join(resourceRoot,"tools/cf6-bladebot-assets/BladebotAI.as")),stage:8,tier:9,
    dataPath:"data/enemy_properties/CF6重制敌人.xml",dataSha256:sha(path.join(resourceRoot,"data/enemy_properties/CF6重制敌人.xml")),
    rivalDataPath:"data/enemy_properties/诺亚新敌人.xml",rivalDataSha256:sha(path.join(resourceRoot,"data/enemy_properties/诺亚新敌人.xml"))};
  const groups=[];
  const rivals=[{id:347,key:"blackiron",name:"黑铁会改造人（诺亚试验体α）"},{id:286,key:"arkclaw",name:"方舟爪豪"}];
  for(const level of levels)for(const rival of rivals) {
    const groupId=rival.key+"-"+level;
    const cases=["blue","red"].map(side=>{
      const candidate={type:"兵种465",level,sourceId:"bladebot-"+level};
      const reference={type:"兵种"+rival.id,level,sourceId:rival.key+"-"+level};
      return {caseId:groupId+"-"+side,blueRoster:[side==="blue"?candidate:reference],
        redRoster:[side==="red"?candidate:reference],repeat,spawnDistance,timeoutFrames,
        tags:["bladebot",rival.key,side],plannerReason:"同等级交换红蓝，对照"+rival.name+"；只调整大刀机器人，双方使用真实命中结算。",
        authorityContext:{...identity,mode:config.mode,comparison:rival.key,candidateSide:side}};
    });
    const manifest=normalizeManifest({batchId:config.experimentId+"-"+groupId,buildCommit,
      planner:{name:"cf6-bladebot-development",version:1},repeat:1,timeoutFrames,cases});
    const worst=manifest.cases.reduce((sum,row)=>sum+row.repeat*row.timeoutFrames/30*1000,0);
    if(manifest.cases.reduce((sum,row)=>sum+row.repeat,0)>25||worst>780000)throw Error("Split the bounded shard");
    const manifestPath=path.join(directory,groupId+"-manifest.json");write(manifestPath,manifest);
    groups.push({groupId,mode:"serial",condition:config.mode,visibility:"unknown",
      ...(config.performance?{performance:config.performance}:{}),
      jobs:[{jobId:groupId,workerId:"bladebot",manifestPath,batchTimeoutMs:900000}]});
  }
  const files=cp.execFileSync("git",["ls-files","-z","--cached","--others","--exclude-standard","--","flashswf","sound","sounds","music","font","fonts"],
    {cwd:resourceRoot,maxBuffer:32*1024*1024,windowsHide:true}).toString("utf8").split("\0");
  const resources=[...new Set(files.filter(p=>/^flashswf\//.test(p)&&/\.(swf|png|jpg|jpeg|webp|mp3|wav|ogg|mp4|flv|f4v)$/i.test(p)||/^(sounds?|music|fonts?)\//.test(p)))];
  const plan={schema:"arena-worker.experiment-plan.v1",experimentId:config.experimentId,
    workers:[{workerId:"bladebot",projectRoot:resourceRoot,candidateRoot:config.candidateRoot,seedPath:config.seedPath,resourcePaths:resources}],
    saveRoots:[...new Set([path.join(ROOT,"saves"),path.join(resourceRoot,"saves")])],
    sharedObjectsRoot:path.join(process.env.APPDATA,"Macromedia","Flash Player","#SharedObjects"),groups,comparisons:[]};
  const planPath=path.join(directory,"experiment-plan.json");write(planPath,plan);
  return {planPath,groups:groups.length,source:identity};
}
if(require.main===module){if(process.argv.length!==3)throw Error("Usage: node arena-plan.js <explicit-config.json>");console.log(JSON.stringify(createPlan(JSON.parse(fs.readFileSync(process.argv[2],"utf8"))),null,2));}
module.exports={createPlan};
