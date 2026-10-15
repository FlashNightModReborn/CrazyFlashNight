"use strict";
// Bounded development battles. This does not publish a calibrated production roster.
const fs = require("fs"), path = require("path"), cp = require("child_process"), crypto = require("crypto");
const { normalizeManifest } = require("../arena-calibration/lib/arena-calibration-core");
const ROOT = path.resolve(__dirname, "../..");
const sha = file => crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
const write = (file, value) => { fs.mkdirSync(path.dirname(file), {recursive:true}); fs.writeFileSync(file, JSON.stringify(value,null,2)+"\n", {flag:"wx"}); };

function createPlan(config) {
  if (!config || !["pilot", "ai", "integration", "crumble"].includes(config.mode)) throw Error("mode must be pilot, ai, integration or crumble");
  if (!/^[a-z0-9][a-z0-9-]{0,47}$/.test(config.experimentId || "")) throw Error("Use a fresh ASCII experimentId");
  if (!path.isAbsolute(config.candidateRoot || "") || !path.isAbsolute(config.seedPath || "")) throw Error("Explicit candidateRoot and read-only seedPath required");
  const levels = config.levels || [30,60,99];
  if (!Array.isArray(levels) || !levels.length || levels.length > 3 || new Set(levels).size !== levels.length
      || levels.some(value => !Number.isInteger(value) || value < 1 || value > 99)) throw Error("Use one to three distinct levels in 1..99");
  const resourceRoot = config.projectRoot === undefined ? ROOT : config.projectRoot;
  if (typeof resourceRoot !== "string" || !path.isAbsolute(resourceRoot)) throw Error("projectRoot must be an absolute owned resource checkout");
  const mirrorTimeoutFrames = config.mirrorTimeoutFrames === undefined ? 5400 : config.mirrorTimeoutFrames;
  if (!Number.isInteger(mirrorTimeoutFrames) || mirrorTimeoutFrames < 1800 || mirrorTimeoutFrames > 8100) throw Error("mirrorTimeoutFrames must be 1800..8100");
  const directory = path.join(ROOT, "tmp/cf6-manman-20261015", config.experimentId);
  const buildCommit = cp.execFileSync("git", ["rev-parse","HEAD"], {cwd:resourceRoot,encoding:"utf8",windowsHide:true}).trim();
  const sourceSwf = "flashswf/arts/new/Codex蛮蛮素材.swf";
  const aiSource = fs.readFileSync(path.join(resourceRoot,"tools/cf6-manman-assets/ManmanAI.as"),"utf8");
  const crumbleMatch = aiSource.match(/\bcrumblePercent\s*:\s*(\d+(?:\.\d+)?)/);
  const identity = {sourceSwf, sourceSwfSha256:sha(path.join(resourceRoot,sourceSwf)),
    aiSourceSha256:sha(path.join(resourceRoot,"tools/cf6-manman-assets/ManmanAI.as")), stage:7,tier:9,
    crumblePercent:crumbleMatch?Number(crumbleMatch[1]):0,
    dataPath:"data/enemy_properties/CF6重制敌人.xml",
    dataSha256:sha(path.join(resourceRoot,"data/enemy_properties/CF6重制敌人.xml"))};
  const unit = (level, mode) => ({type:"兵种463",level,sourceId:`manman-${mode}-${level}`,
    ...(mode === "baseline" ? {parameters:{蛮蛮AI模式:"baseline"}} : {})});
  const orc = level => ({type:"兵种125",level,sourceId:`undead-orc-${level}`});
  const groups = [];
  const add = (name, cases) => {
    const manifest = normalizeManifest({batchId:config.experimentId+"-"+name,buildCommit,
      planner:{name:"cf6-manman-development",version:1},repeat:1,timeoutFrames:1800,cases});
    const worst = manifest.cases.reduce((sum,row)=>sum+row.repeat*row.timeoutFrames/30*1000,0);
    if (manifest.cases.reduce((sum,row)=>sum+row.repeat,0)>25 || worst>780000) throw Error("Split the bounded shard");
    const manifestPath = path.join(directory,name+"-manifest.json");write(manifestPath,manifest);
    groups.push({groupId:name,mode:"serial",condition:config.mode,visibility:"unknown",
      jobs:[{jobId:name,workerId:"manman",manifestPath,batchTimeoutMs:900000}]});
  };
  const pair = (level, kind, repeat) => ["blue","red"].map(side => {
    const candidate=unit(level,"enhanced"), reference=kind==="mirror"?unit(level,"baseline"):orc(level);
    return {caseId:`${kind}-${level}-${side}`,blueRoster:[side==="blue"?candidate:reference],
      redRoster:[side==="red"?candidate:reference],repeat,timeoutFrames:kind==="mirror"&&config.mode!=="pilot"?mirrorTimeoutFrames:2400,
      tags:["manman",kind,side],plannerReason:kind==="mirror"?
        "同兵种、同等级和面板，仅切换私有 AI；交换红蓝，实际 startMaxHp 必须相等。":
        "与不死兽人同等级换边对照；包含阶段和档次差异，只检验整体行为，不归因于纯 AI 增益。",
      authorityContext:{...identity,mode:config.mode,comparison:kind,candidateSide:side}};
  });
  if (config.mode==="pilot") add("pilot",[...pair(30,"mirror",1),...pair(30,"orc",1)]);
  if (config.mode==="ai") for(const level of levels) add("mirror-"+level,pair(level,"mirror",1));
  if (config.mode==="crumble") {
    if (!(identity.crumblePercent>0)) throw Error("Crumble comparison requires an explicit positive source parameter");
    const crumbleUnit=(level,enabled,role)=>({...unit(level,"enhanced"),sourceId:`${role}-${enabled?"on":"off"}-${level}`,
      parameters:{蛮蛮击溃模式:enabled?"on":"off"}});
    for(const level of levels) for(const enabled of [false,true]) {
      const label=enabled?"crumble":"control";
      add(label+"-"+level,["blue","red"].map(side=>({caseId:`${label}-${level}-${side}`,
        blueRoster:[crumbleUnit(level,side==="blue"&&enabled,side==="blue"?"candidate":"reference")],
        redRoster:[crumbleUnit(level,side==="red"&&enabled,side==="red"?"candidate":"reference")],
        repeat:1,timeoutFrames:mirrorTimeoutFrames,tags:["manman","crumble-evaluation",label,side],
        plannerReason:"双方同素材、同 enhanced AI、同面板；control 双方关闭击溃，crumble 仅候选开启，交换红蓝。",
        authorityContext:{...identity,mode:"crumble",comparison:label,candidateSide:side,
          candidateCrumblePercent:enabled?identity.crumblePercent:0,referenceCrumblePercent:0}})));
    }
    add("crumble-mixed-30",["blue","red"].map(side=>({caseId:"crumble-mixed-30-"+side,
      blueRoster:[crumbleUnit(30,side==="blue",side==="blue"?"candidate":"reference"),orc(30)],
      redRoster:[crumbleUnit(30,side==="red",side==="red"?"candidate":"reference"),orc(30)],
      blueFormation:"column",redFormation:"column",formationSpacing:70,repeat:1,timeoutFrames:5400,
      tags:["manman","crumble","mixed",side],plannerReason:"两队均为 enhanced 蛮蛮加不死兽人，只切换候选蛮蛮的击溃。",
      authorityContext:{...identity,mode:"crumble",comparison:"mixed",candidateSide:side,
        candidateCrumblePercent:identity.crumblePercent,referenceCrumblePercent:0}})));
  }
  if (config.mode==="integration") {
    for(const level of levels) add("orc-"+level,pair(level,"orc",1));
    const cases=["blue","red"].map(side=>({caseId:"mixed-30-"+side,
      blueRoster:side==="blue"?[unit(30,"enhanced"),orc(30)]:[unit(30,"baseline"),orc(30)],
      redRoster:side==="red"?[unit(30,"enhanced"),orc(30)]:[unit(30,"baseline"),orc(30)],
      blueFormation:"column",redFormation:"column",formationSpacing:70,repeat:1,timeoutFrames:5400,
      tags:["manman","mixed",side],plannerReason:"两对两纵深错位场，观察换目标、对齐和死亡后收尾；不作玩家体验结论。",
      authorityContext:{...identity,mode:"mixed",candidateSide:side}}));
    add("mixed-30",cases);
  }
  const files=cp.execFileSync("git",["ls-files","-z","--cached","--others","--exclude-standard","--","flashswf","sound","sounds","music","font","fonts"],
    {cwd:resourceRoot,maxBuffer:32*1024*1024,windowsHide:true}).toString("utf8").split("\0");
  const resources=[...new Set(files.filter(p=>/^flashswf\//.test(p)&&/\.(swf|png|jpg|jpeg|webp|mp3|wav|ogg|mp4|flv|f4v)$/i.test(p)||/^(sounds?|music|fonts?)\//.test(p)))];
  const plan={schema:"arena-worker.experiment-plan.v1",experimentId:config.experimentId,
    workers:[{workerId:"manman",projectRoot:resourceRoot,candidateRoot:config.candidateRoot,seedPath:config.seedPath,resourcePaths:resources}],
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
