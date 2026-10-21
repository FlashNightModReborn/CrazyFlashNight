"use strict";
const fs=require("fs"),path=require("path"),crypto=require("crypto"),cp=require("child_process");
const {normalizeManifest}=require("../arena-calibration/lib/arena-calibration-core");
const {resolveExpectedRuntimeIdentity}=require("../lib/runtime-process-identity");
const ROOT=path.resolve(__dirname,"../..");
const DOG_TYPE="兵种"+require("./balance-inputs.json").unitId;
const hash=p=>crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex");
function createPlan(config){
  if(!/^[a-z0-9][a-z0-9-]{0,47}$/.test(config.experimentId||""))throw Error("Fresh experimentId required");
  for(const key of ["projectRoot","candidateRoot","seedPath","outputDirectory"])
    if(!path.isAbsolute(config[key]||""))throw Error("Explicit "+key+" required");
  const workerRoot=path.resolve(config.projectRoot),out=path.resolve(config.outputDirectory);
  // PathManager only accepts these local resource directory names.
  if(!["CrazyFlashNight","flashNight","resources"].includes(path.basename(workerRoot)))
    throw Error("Worker resource root must retain a PathManager-recognized directory name");
  if(!out.startsWith(path.join(ROOT,"tmp")+path.sep))throw Error("Output must be in this task's tmp tree");
  const bindings=["scripts/asLoader.swf","flashswf/arts/things-new.swf","flashswf/arts/new/Codex专用素材.swf",
    "data/units/units.json","data/enemy_properties/军阀新人物.xml","data/enemy_properties/原版敌人 2011-2012.xml",
    "data/items/asset_source_map.xml","launcher/web/modules/arena-unit-catalog.js",
    "data/stages/地下2层/禁区边缘.xml",
    "scripts/类定义/org/flashNight/arki/unit/UnitAI/Custom/WarlordDogController.as",
    "tools/warlord-dog-assets/balance-inputs.json"].map(relative=>({path:relative,sha256:hash(path.join(ROOT,relative))}));
  for(const row of bindings)if(hash(path.join(workerRoot,row.path))!==row.sha256)throw Error("Worker differs: "+row.path);
  const runtimeIdentity=resolveExpectedRuntimeIdentity(workerRoot,config.candidateRoot);
  if(runtimeIdentity.runtimeMode!=="isolated_candidate")throw Error("Isolated runtime candidate required");
  if(fs.existsSync(out))throw Error("Experiment output already exists; preserve the previous attempt");
  const kinds=config.kinds||["baseline","candidate","plain"];
  if(kinds.some(k=>!["baseline","candidate","plain"].includes(k)))throw Error("Invalid composition");
  const repeat=config.repeat===undefined?3:config.repeat;
  if(!Number.isInteger(repeat)||repeat<1||repeat>3)throw Error("repeat must be 1..3");
  const sides=config.sides||["blue","red"],timeoutFrames=config.timeoutFrames||1800;
  if(!sides.length||new Set(sides).size!==sides.length||sides.some(s=>!["blue","red"].includes(s)))throw Error("Invalid sides");
  if(!Number.isInteger(timeoutFrames)||timeoutFrames<1800||timeoutFrames>5400)throw Error("timeoutFrames must be 1800..5400");
  const soldier=n=>({type:"兵种56",level:20,sourceId:"soldier-"+n});
  const machines=[{type:"兵种25",level:20,sourceId:"t800-l85",parameters:{长枪:"L85A1"}},
    {type:"兵种25",level:20,sourceId:"t800-ak",parameters:{长枪:"AK47"}}];
  const resourcePaths=cp.execFileSync("git",["ls-files","-z","--cached","--others","--exclude-standard","--","flashswf","sound","sounds","music","font","fonts"],
    {cwd:workerRoot,maxBuffer:32*1024*1024,windowsHide:true}).toString("utf8").split("\0")
    .filter(p=>/^flashswf\//.test(p)&&/\.(swf|png|jpg|jpeg|webp|mp3|wav|ogg|mp4|flv|f4v)$/i.test(p)||/^(sounds?|music|fonts?)\//.test(p));
  fs.mkdirSync(out,{recursive:true});
  const write=(name,value)=>{const file=path.join(out,name);fs.writeFileSync(file,JSON.stringify(value,null,2)+"\n",{flag:"wx"});return file;};
  const groups=kinds.map(kind=>{
    const dog={type:DOG_TYPE,level:20,sourceId:"iron-guard"};
    if(kind==="plain")dog.parameters={铁卫犬关闭能力:true};
    const military=kind==="baseline"?[soldier(0),soldier(1),soldier(2)]:[dog,soldier(1),soldier(2)];
    const cases=sides.map(side=>({caseId:kind+"-"+side,repeat,timeoutFrames,
      spawnDistance:420,blueFormation:"line",redFormation:"line",formationSpacing:90,
      blueRoster:side==="blue"?military:machines,redRoster:side==="red"?military:machines,
      tags:["iron-guard",kind,side],plannerReason:config.plannerReason||"同级同枪同站位，交换阵营比较军阀编队，保留胜负与超时。",
      authorityContext:{militarySide:side,composition:kind,level:20,sourceBindings:bindings,
        limitation:"Arena faction rules apply; this is a composition comparison, not human acceptance of the story stage."}}));
    const manifest=normalizeManifest({batchId:config.experimentId+"-"+kind,
      buildCommit:cp.execFileSync("git",["rev-parse","HEAD"],{cwd:workerRoot,encoding:"utf8",windowsHide:true}).trim(),
      planner:{name:"iron-guard-composition",version:1},repeat:1,timeoutFrames,cases});
    const manifestPath=write(kind+"-manifest.json",manifest);
    return {groupId:kind,mode:"serial",condition:kind,visibility:"background-visible",
      performance:{preset:"performance",mode:"fixed",maxRenderHeight:180},
      jobs:[{jobId:kind+"-w1",workerId:"iron-guard-w1",manifestPath,batchTimeoutMs:900000}]};
  });
  const plan={schema:"arena-worker.experiment-plan.v1",experimentId:config.experimentId,
    workers:[{workerId:"iron-guard-w1",projectRoot:workerRoot,candidateRoot:config.candidateRoot,seedPath:config.seedPath,resourcePaths}],
    saveRoots:[path.join(ROOT,"saves"),path.join(workerRoot,"saves")],
    sharedObjectsRoot:path.join(process.env.APPDATA,"Macromedia","Flash Player","#SharedObjects"),groups,comparisons:[]};
  const planPath=write("experiment-plan.json",plan);
  write("input-identity.json",{bindings,runtimeIdentity,repeat,sides,timeoutFrames,expectedRuns:kinds.length*sides.length*repeat});
  return {planPath,expectedRuns:kinds.length*sides.length*repeat};
}
if(require.main===module){if(process.argv.length!==3)throw Error("Usage: node arena-plan.js <config.json>");console.log(JSON.stringify(createPlan(JSON.parse(fs.readFileSync(process.argv[2],"utf8")))));}
module.exports={createPlan};
