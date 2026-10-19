"use strict";
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../../..');
const {parseSwf}=require(path.join(root,'tools/swf-metadata'));
const old=parseSwf(fs.readFileSync(path.join(__dirname,'asLoader-c5.swf')));
const fresh=parseSwf(fs.readFileSync(path.join(__dirname,'publish/asLoader.swf')));
const before=new Map(old.classes.map(x=>[x.fqn,x]));
const after=new Map(fresh.classes.map(x=>[x.fqn,x]));
const changed=[...before.keys()].filter(n=>after.has(n)&&before.get(n).actionSha256!==after.get(n).actionSha256).sort();
const added=[...after.keys()].filter(n=>!before.has(n)).sort();
const removed=[...before.keys()].filter(n=>!after.has(n)).sort();
const qualified=changed.length===1&&changed[0]==='org.flashNight.neur.Server.ServerManager'&&!added.length&&!removed.length;
const report={qualified,beforeSha256:old.sha256,afterSha256:fresh.sha256,beforeClasses:before.size,afterClasses:after.size,
  changedExistingClasses:changed,addedClasses:added,removedClasses:removed,unchangedExistingClasses:before.size-changed.length-removed.length,
  reason:'ServerManager contains the already merged read-only ragTerminalAvailable allowlist addition. Communication frame chunks and the already merged Agent root script also change; class equality does not establish whole-root-script equality.',
  classes:fresh.classes.map(x=>({name:x.fqn,actionSha256:x.actionSha256,actionBytes:x.actionBytes})),
  boundary:'C5 complete calibration remains historical. C6 requires fresh bootstrap and arena integration; these bounded runs do not replace the prior full performance matrix.'};
fs.writeFileSync(path.join(__dirname,'c5-c6-class-scope.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({qualified,changed,added,removed,unchanged:report.unchangedExistingClasses}));
if(!qualified)process.exitCode=1;
