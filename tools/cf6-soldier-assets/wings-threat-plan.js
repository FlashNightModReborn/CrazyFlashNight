"use strict";
const fs=require("fs"),path=require("path"),crypto=require("crypto"),cp=require("child_process");
const root=path.resolve(__dirname,"../..");
const {normalizeManifest}=require(path.join(root,"tools/arena-calibration/lib/arena-calibration-core"));
if(process.argv.length!==3)throw Error("Usage: node wings-threat-plan.js <explicit-config.json>");
const config=JSON.parse(fs.readFileSync(process.argv[2],"utf8"));
for(const key of ["resourceRoot","candidateRoot","outputDirectory"])
 if(!path.isAbsolute(config[key]||""))throw Error("Explicit absolute "+key+" required");
if(!path.resolve(config.candidateRoot).startsWith(path.join(path.resolve(config.resourceRoot),"tmp/runtime-candidates/v2")+path.sep))
 throw Error("Owned isolated candidate required");
if(!/^[a-z0-9][a-z0-9-]{0,35}$/.test(config.experimentId||""))throw Error("Fresh bounded experimentId required");
if(!["baseline","pool"].includes(config.mode))throw Error("Explicit baseline or pool mode required");
const output=path.resolve(config.outputDirectory);
if(!output.startsWith(path.join(root,"tmp")+path.sep))throw Error("Owned tmp output required");
const hash=f=>crypto.createHash("sha256").update(fs.readFileSync(f)).digest("hex");
const write=(f,d)=>fs.writeFileSync(path.join(output,f),JSON.stringify(d,null,2)+"\n",{flag:"wx"});
const sourceFiles=["flashswf/arts/new/Codex特种兵素材.swf","flashswf/arts/new/CodexWings素材.swf",
 "scripts/asLoader.swf","data/enemy_properties/CF6重制敌人.xml","data/units/units.json",
 "tools/cf6-soldier-assets/SoldierAI.as","tools/cf6-wings-assets/WingsAI.as","data/items/武器_长枪_突击步枪.xml"];
const sourceBindings=sourceFiles.map(p=>({path:p,sha256:hash(path.join(config.resourceRoot,p))}));
for(const r of sourceBindings)if(hash(path.join(root,r.path))!==r.sha256)throw Error("Worker differs: "+r.path);
const cases=[];
const profiles=config.mode==="baseline"
 ?[30,60,99].flatMap(level=>["blue","red"].map(side=>({level,side,weapon:"M4A1战术版",repeat:1})))
 :["M4A1改","AK74战术版","M4A1战术版","DD MK18战术版"].map((weapon,index)=>({level:60,side:"red",weapon,index,repeat:3}));
for(const {level,side,weapon,index,repeat} of profiles){
 const soldier={type:"兵种466",level,sourceId:"soldier-"+level,parameters:{长枪:weapon}};
 const wings={type:"兵种464",level,sourceId:"wings-"+level};
 cases.push({caseId:"wings-"+level+"-"+side+(config.mode==="pool"?"-gun"+index:""),blueRoster:[side==="blue"?soldier:wings],redRoster:[side==="red"?soldier:wings],
 repeat,timeoutFrames:config.mode==="pool"?900:2700,spawnDistance:650,blueFormation:"line",redFormation:"line",formationSpacing:54,
 tags:["cf6-soldier","wings-threat",config.revision,side],
 plannerReason:"同级指定军校生池内长枪，保留标准人形友军生命三倍规则。pool模式特种兵只放红方，每枪3场，观察默认池覆盖。",
 authorityContext:{revision:config.revision,candidateSide:side,weapon,stage:7,tier:5,rivalStage:7,rivalTier:8,sourceBindings}});
}
const batchId=config.experimentId+"-wings";
const manifest=normalizeManifest({batchId,buildCommit:cp.execFileSync("git",["rev-parse","HEAD"],{cwd:config.resourceRoot,encoding:"utf8"}).trim(),
 planner:{name:"cf6-soldier-wings-threat",version:1},repeat:1,timeoutFrames:2700,cases});
const rows=cases.reduce((sum,c)=>sum+c.repeat,0),worstCaseCombatMs=cases.reduce((sum,c)=>sum+c.repeat*c.timeoutFrames/30*1000,0);
if(rows>25 || worstCaseCombatMs>780000)throw Error("Split the bounded batch");
fs.mkdirSync(output,{recursive:true});write("wings-manifest.json",manifest);
write("wings-evidence-config.json",{resourceRoot:config.resourceRoot,candidateRoot:config.candidateRoot,
 manifestPath:path.join(output,"wings-manifest.json"),slot:"cf7_agent_"+batchId.replace(/-/g,"_")});
write("plan.json",{config,sourceBindings,cases:cases.length,rows,worstCaseCombatMs});
console.log(JSON.stringify({output,cases:cases.length,rows,slot:"cf7_agent_"+batchId.replace(/-/g,"_")}));
