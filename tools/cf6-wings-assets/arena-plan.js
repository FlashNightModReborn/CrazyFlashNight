"use strict";
// Bounded development battles; this does not publish a production calibration roster.
const fs = require("fs"), path = require("path"), cp = require("child_process"), crypto = require("crypto");
const { normalizeManifest } = require("../arena-calibration/lib/arena-calibration-core");
const ROOT = path.resolve(__dirname, "../..");
const sha = file => crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
const write = (file, value) => { fs.mkdirSync(path.dirname(file), {recursive:true}); fs.writeFileSync(file, JSON.stringify(value,null,2)+"\n", {flag:"wx"}); };

function createPlan(config) {
  if (!config || !["pilot", "ai", "integration"].includes(config.mode)) throw Error("mode must be pilot, ai or integration");
  if (!/^[a-z0-9][a-z0-9-]{0,47}$/.test(config.experimentId || "")) throw Error("Use a fresh ASCII experimentId");
  if (!path.isAbsolute(config.candidateRoot || "") || !path.isAbsolute(config.seedPath || "")) throw Error("Explicit candidateRoot and read-only seedPath required");
  const levels = config.levels || [30,60,99];
  if (!Array.isArray(levels) || !levels.length || levels.length > 3 || new Set(levels).size !== levels.length
      || levels.some(value => !Number.isInteger(value) || value < 1 || value > 99)) throw Error("Use one to three distinct levels in 1..99");
  const resourceRoot = config.projectRoot === undefined ? ROOT : config.projectRoot;
  if (typeof resourceRoot !== "string" || !path.isAbsolute(resourceRoot)) throw Error("projectRoot must be an absolute owned resource checkout");
  const mirrorTimeoutFrames = config.mirrorTimeoutFrames === undefined ? 5400 : config.mirrorTimeoutFrames;
  if (!Number.isInteger(mirrorTimeoutFrames) || mirrorTimeoutFrames < 1800 || mirrorTimeoutFrames > 8100) throw Error("mirrorTimeoutFrames must be 1800..8100");
  const spawnDistance = config.spawnDistance === undefined ? 650 : config.spawnDistance;
  if (!Number.isInteger(spawnDistance) || spawnDistance < 360 || spawnDistance > 1000) throw Error("spawnDistance must be 360..1000, matching the arena manifest lower bound");
  const directory = path.join(ROOT, "tmp/cf6-wings-20261015", config.experimentId);
  const buildCommit = cp.execFileSync("git", ["rev-parse","HEAD"], {cwd:resourceRoot,encoding:"utf8",windowsHide:true}).trim();
  const sourceSwf = "flashswf/arts/new/CodexWings素材.swf";
  const identity = {sourceSwf, sourceSwfSha256:sha(path.join(resourceRoot,sourceSwf)),
    aiSourceSha256:sha(path.join(resourceRoot,"tools/cf6-wings-assets/WingsAI.as")), stage:7,tier:8,
    dataPath:"data/enemy_properties/CF6重制敌人.xml",
    dataSha256:sha(path.join(resourceRoot,"data/enemy_properties/CF6重制敌人.xml"))};
  const unit = (level, mode) => ({type:"兵种464",level,sourceId:`wings-${mode}-${level}`,
    ...(mode === "baseline" ? {parameters:{WingsAI模式:"baseline"}} : {})});
  const donor = level => ({type:"兵种373",level,sourceId:`cf7-agent-${level}`});
  const groups = [];
  const add = (name, cases) => {
    const manifest = normalizeManifest({batchId:config.experimentId+"-"+name,buildCommit,
      planner:{name:"cf6-wings-development",version:1},repeat:1,timeoutFrames:1800,cases});
    const worst = manifest.cases.reduce((sum,row)=>sum+row.repeat*row.timeoutFrames/30*1000,0);
    if (manifest.cases.reduce((sum,row)=>sum+row.repeat,0)>25 || worst>780000) throw Error("Split the bounded shard");
    const manifestPath = path.join(directory,name+"-manifest.json");write(manifestPath,manifest);
    groups.push({groupId:name,mode:"serial",condition:config.mode,visibility:"unknown",
      jobs:[{jobId:name,workerId:"wings",manifestPath,batchTimeoutMs:900000}]});
  };
  const pair = (level, kind) => ["blue","red"].map(side => {
    const candidate=unit(level,"enhanced"), reference=kind==="mirror"?unit(level,"baseline"):donor(level);
    return {caseId:`${kind}-${level}-${side}`,blueRoster:[side==="blue"?candidate:reference],
      redRoster:[side==="red"?candidate:reference],repeat:1,spawnDistance,timeoutFrames:kind==="mirror"&&config.mode!=="pilot"?mirrorTimeoutFrames:2400,
      tags:["wings",kind,side],plannerReason:kind==="mirror"?
        "同 Wings、同等级和面板，仅切换私有 AI；交换红蓝，实际 startMaxHp 必须相等。":
        "与原版闪6特工同等级换边比较；包含素材和阶段档次差异，不归因于纯 AI 增益。",
      authorityContext:{...identity,mode:config.mode,comparison:kind,candidateSide:side}};
  });
  if (config.mode==="pilot") add("pilot",[...pair(30,"mirror"),...pair(30,"donor")]);
  if (config.mode==="ai") for(const level of levels) add("mirror-"+level,pair(level,"mirror"));
  if (config.mode==="integration") {
    for(const level of levels) add("donor-"+level,pair(level,"donor"));
    add("mixed-30",["blue","red"].map(side=>({caseId:"mixed-30-"+side,
      blueRoster:[unit(30,side==="blue"?"enhanced":"baseline"),donor(30)],
      redRoster:[unit(30,side==="red"?"enhanced":"baseline"),donor(30)],
      blueFormation:"column",redFormation:"column",formationSpacing:70,repeat:1,spawnDistance,timeoutFrames:5400,
      tags:["wings","mixed",side],plannerReason:"两队各为 Wings 与原版特工，纵深错位，观察换目标和死亡后收尾。",
      authorityContext:{...identity,mode:"mixed",candidateSide:side}})));
  }
  const files=cp.execFileSync("git",["ls-files","-z","--cached","--others","--exclude-standard","--","flashswf","sound","sounds","music","font","fonts"],
    {cwd:resourceRoot,maxBuffer:32*1024*1024,windowsHide:true}).toString("utf8").split("\0");
  const resources=[...new Set(files.filter(p=>/^flashswf\//.test(p)&&/\.(swf|png|jpg|jpeg|webp|mp3|wav|ogg|mp4|flv|f4v)$/i.test(p)||/^(sounds?|music|fonts?)\//.test(p)))];
  const plan={schema:"arena-worker.experiment-plan.v1",experimentId:config.experimentId,
    workers:[{workerId:"wings",projectRoot:resourceRoot,candidateRoot:config.candidateRoot,seedPath:config.seedPath,resourcePaths:resources}],
    saveRoots:[...new Set([path.join(ROOT,"saves"),path.join(resourceRoot,"saves")])],sharedObjectsRoot:path.join(process.env.APPDATA,"Macromedia","Flash Player","#SharedObjects"),
    groups,comparisons:[]};
  const planPath=path.join(directory,"experiment-plan.json");write(planPath,plan);
  return {planPath,groups:groups.length,source:identity};
}
if(require.main===module) {
  if(process.argv.length!==3)throw Error("Usage: node arena-plan.js <explicit-config.json>");
  console.log(JSON.stringify(createPlan(JSON.parse(fs.readFileSync(process.argv[2],"utf8"))),null,2));
}
module.exports={createPlan};
