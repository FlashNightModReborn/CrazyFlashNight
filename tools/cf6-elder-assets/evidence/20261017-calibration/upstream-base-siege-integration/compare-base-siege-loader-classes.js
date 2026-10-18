"use strict";
const fs=require("fs"),path=require("path"),cp=require("child_process"),crypto=require("crypto");
const {parseSwf}=require("../../tools/swf-metadata");
const root=path.resolve(__dirname,"../.."),out=__dirname;
const before=parseSwf(fs.readFileSync(path.join(out,"upstream-base-siege-integration/working/scripts/asLoader.swf")));
const after=parseSwf(fs.readFileSync(path.join(out,"build-integrated-base-siege-loader/asLoader.swf")));
const oldMap=new Map(before.classes.map(row=>[row.fqn,row]));
const newMap=new Map(after.classes.map(row=>[row.fqn,row]));
const changed=[...oldMap.keys()].filter(name=>newMap.has(name)&&oldMap.get(name).actionSha256!==newMap.get(name).actionSha256).sort();
const added=[...newMap.keys()].filter(name=>!oldMap.has(name)).sort();
const removed=[...oldMap.keys()].filter(name=>!newMap.has(name)).sort();
const allowedChanged=["org.flashNight.arki.scene.StageManager","org.flashNight.arki.scene.WaveSpawner"];
const allowedAdded=["org.flashNight.arki.scene.BaseSiegeController","org.flashNight.arki.scene.BaseSiegeRules"];
const qualified=!removed.length&&changed.every(name=>allowedChanged.includes(name))&&added.every(name=>allowedAdded.includes(name));
const sourcePaths=["scripts/类定义/org/flashNight/arki/scene/StageManager.as","scripts/类定义/org/flashNight/arki/scene/WaveSpawner.as",
    "scripts/类定义/org/flashNight/arki/scene/BaseSiegeController.as","scripts/类定义/org/flashNight/arki/scene/BaseSiegeRules.as",
    "scripts/逻辑/关卡系统/关卡系统_lsy_关卡回调函数.as","scripts/逻辑/关卡系统/关卡系统_lsy_无限过图.as"];
const sourceBindings=sourcePaths.map(name=>({path:name,sha256:crypto.createHash("sha256").update(fs.readFileSync(path.join(root,name))).digest("hex")}));
const report={qualified,beforeSha256:before.sha256,afterSha256:after.sha256,beforeClasses:before.classes.length,afterClasses:after.classes.length,
    changedExistingClasses:changed,addedClasses:added,removedClasses:removed,unchangedExistingClasses:oldMap.size-changed.length-removed.length,
    sourceBindings,classes:after.classes.map(row=>({name:row.fqn,actionSha256:row.actionSha256,actionBytes:row.actionBytes})),
    boundary:"Compiled-class scope comparison only. Scene startup and clearing changed and require current-loader execution; previous C3/C4 arena results remain historical. Current registrations are 472/473/474 and require fresh complete matrices."};
fs.writeFileSync(path.join(out,"base-siege-loader-class-scope.json"),JSON.stringify(report,null,2)+"\n",{flag:"wx"});
console.log(JSON.stringify({qualified,beforeClasses:before.classes.length,afterClasses:after.classes.length,changed,added,removed}));
if(!qualified)process.exitCode=1;
