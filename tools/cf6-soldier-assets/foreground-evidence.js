"use strict";
// Reuse the arena resource/save algorithms around the ordinary-window test lane.
const fs=require("fs"),path=require("path"),cp=require("child_process"),crypto=require("crypto");
const {runEvidenceTask}=require("../arena-calibration/lib/arena-worker-evidence");
const {captureGlobalProtectionSnapshot}=require("../arena-calibration/lib/unattended-save-safety");
const {compareProtectedSaveSnapshots}=require("../arena-calibration/run-unattended");
const {assertRuntimeIdentity}=require("../lib/runtime-process-identity");
const ROOT=path.resolve(__dirname,"../..");
const read=file=>JSON.parse(fs.readFileSync(path.toNamespacedPath(path.resolve(file)),"utf8").replace(/^\uFEFF/,""));
const write=(file,value)=>{fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,JSON.stringify(value,null,2)+"\n",{flag:"wx"});};
const hash=file=>crypto.createHash("sha256").update(fs.readFileSync(path.toNamespacedPath(file))).digest("hex");

async function main() {
  const [mode,input,output]=process.argv.slice(2);
  if(!["before","after"].includes(mode)||!input||!output)throw Error("Usage: node foreground-evidence.js before <config.json> <before.json> | after <before.json> <run-report.json>");
  if(mode==="before") {
    const config=read(input);
    for(const key of ["resourceRoot","candidateRoot","manifestPath"])if(!path.isAbsolute(config[key]||""))throw Error("Explicit absolute "+key+" required");
    if(!/^cf7_agent_[A-Za-z0-9_-]+$/.test(config.slot||""))throw Error("Dedicated slot required");
    const files=cp.execFileSync("git",["ls-files","-z","--cached","--others","--exclude-standard","--","flashswf","sound","sounds","music","font","fonts"],
      {cwd:config.resourceRoot,maxBuffer:32*1024*1024,windowsHide:true}).toString("utf8").split("\0");
    const resourcePaths=[...new Set(files.filter(p=>/^flashswf\//.test(p)&&/\.(swf|png|jpg|jpeg|webp|mp3|wav|ogg|mp4|flv|f4v)$/i.test(p)||/^(sounds?|music|fonts?)\//.test(p)))];
    resourcePaths.push("tools/cf6-soldier-assets/SoldierAI.as");
    const options={saveRoots:[path.join(ROOT,"saves"),path.join(config.resourceRoot,"saves")],
      sharedObjectsRoot:path.join(process.env.APPDATA,"Macromedia","Flash Player","#SharedObjects"),
      allowedTargets:[{swfOrigin:path.join(config.resourceRoot,"CRAZYFLASHER7MercenaryEmpire.swf"),slot:config.slot}]};
    const evidence=await runEvidenceTask({operation:"before",projectRoot:config.resourceRoot,
      candidateRoot:config.candidateRoot,slot:config.slot,resourcePaths});
    write(path.resolve(output),{schema:"cf6-soldier.foreground-before.v1",config,resourcePaths,options,
      manifestSha256:hash(config.manifestPath),evidence,global:captureGlobalProtectionSnapshot(options)});
    console.log(JSON.stringify({ok:true,phase:"before",resourceFiles:evidence.resourceClosure.files.length}));
    return;
  }
  const before=read(input),report=read(output);
  if(before.schema!=="cf6-soldier.foreground-before.v1"||report.slot!==before.config.slot)throw Error("Evidence/slot mismatch");
  const config=before.config;
  const after=await runEvidenceTask({operation:"after",projectRoot:config.resourceRoot,candidateRoot:config.candidateRoot,
    slot:config.slot,resourcePaths:before.resourcePaths});
  assertRuntimeIdentity(before.evidence.runtimeIdentity,after.runtimeIdentity);
  assertRuntimeIdentity(before.evidence.runtimeIdentity,report.runtimeIdentity);
  const global=captureGlobalProtectionSnapshot(before.options);
  const differences=compareProtectedSaveSnapshots(before.global,global);
  const markerPath=path.join(config.resourceRoot,"saves/.launcher-version-marker.json");
  const markerKey="shadow_file:.launcher-version-marker.json:"+crypto.createHash("sha256").update(path.resolve(markerPath).toLowerCase(),"utf8").digest("hex").slice(0,16);
  const metadataChanges=differences.filter(d=>d.key===markerKey);
  if(metadataChanges.length) {
    const marker=read(markerPath);
    if(marker.version!==1||Object.keys(marker).sort().join(",")!=="version,writtenAt"
      ||typeof marker.writtenAt!=="string"||!Number.isFinite(Date.parse(marker.writtenAt)))throw Error("Unexpected startup metadata shape");
  }
  const playerDifferences=differences.filter(d=>d.key!==markerKey);
  const resourcesUnchanged=before.evidence.resourceClosure.closureHash===after.resourceClosure.closureHash;
  const localDifferences=compareProtectedSaveSnapshots(before.evidence.protectedSave,after.protectedSave);
  const resultPath=report.resultPath?path.resolve(config.resourceRoot,report.resultPath):null;
  const rows=resultPath?fs.readFileSync(path.toNamespacedPath(resultPath),"utf8").trim().split(/\r?\n/).filter(Boolean).map(JSON.parse):[];
  const allNatural=rows.length===report.expectedRows&&rows.length>0&&rows.every(r=>r.status==="finished"&&(!r.errors||r.errors.length===0));
  const processJson=cp.execFileSync("powershell.exe",["-NoProfile","-Command",
    "Get-CimInstance Win32_Process | Select-Object ProcessId,ExecutablePath | ConvertTo-Json -Compress"],
    {encoding:"utf8",windowsHide:true,maxBuffer:4*1024*1024});
  const processes=JSON.parse(processJson);
  const ownedPrefix=path.resolve(config.resourceRoot).toLowerCase()+path.sep;
  const remainingOwnedProcesses=(Array.isArray(processes)?processes:[processes])
    .filter(p=>typeof p.ExecutablePath==="string"&&path.resolve(p.ExecutablePath).toLowerCase().startsWith(ownedPrefix));
  const qualified=report.status==="completed"&&report.runtimeIdentity.verified===true
    &&report.postRunShutdown?.stopped===true&&report.saveProtection?.unchanged===true
    &&resourcesUnchanged&&localDifferences.length===0&&playerDifferences.length===0
    &&allNatural&&remainingOwnedProcesses.length===0&&hash(config.manifestPath)===before.manifestSha256;
  const target=path.resolve(input).replace(/\.json$/,"-after.json");
  if(target===path.resolve(input))throw Error("Before evidence must use a .json suffix");
  write(target,{schema:"cf6-soldier.foreground-after.v1",beforePath:path.resolve(input),beforeSha256:hash(path.resolve(input)),
    runReportPath:path.resolve(output),runReportSha256:hash(path.resolve(output)),after,global,
    resultPath,resultSha256:resultPath?hash(resultPath):null,allNatural,remainingOwnedProcesses,
    resourcesUnchanged,playerSaveFilesUnchanged:playerDifferences.length===0&&localDifferences.length===0,
    allGlobalFilesUnchanged:differences.length===0,metadataChanges,
    metadataAttribution:"Normal Launcher writes its own .launcher-version-marker.json at startup (Program.cs / LauncherVersionGate). Original all-file differences remain recorded.",
    differences,localDifferences,qualified});
  console.log(JSON.stringify({qualified,resourcesUnchanged,playerSaveFilesUnchanged:playerDifferences.length===0&&localDifferences.length===0,
    allGlobalFilesUnchanged:differences.length===0,ownStartupMetadataChanges:metadataChanges.length,output:target}));
  if(!qualified)process.exitCode=1;
}
main().catch(error=>{console.error(error.stack||error.message);process.exitCode=1;});
