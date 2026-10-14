'use strict';
// Owned machine fixture only. No player file is read or written.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const repo=path.resolve(__dirname,'..');
const schema=JSON.parse(fs.readFileSync(path.join(repo,'launcher/contracts/settings-authority.v2.json'),'utf8'));
const nonce=crypto.randomBytes(10).toString('hex'),slot='cf7_env_set_'+nonce;
const out=path.join(repo,'tmp/focus-sol-20261013','owned-sol-'+nonce);
fs.mkdirSync(out,{recursive:false});fs.mkdirSync(path.join(out,'journal'));
const hash=s=>crypto.createHash('sha256').update(s,'utf8').digest('hex');
const swf=path.join(repo,'scripts/TestLoader.swf');
const origin=hash('cf7.settings.origin.v1|'+swf.replace(/\\/g,'/').toUpperCase());
const context='ctx.'+hash('cf7.settings.context.v1|'+repo.toUpperCase()+'|'+origin+'|'+slot);
const owner='owner.'+nonce,epoch='vm.'+nonce,sourceEpoch=epoch+'.1',operation='op.'+nonce,attempt='save.'+nonce;
const retry='save.retry.'+nonce;
const base='observe.'+sourceEpoch+'.1';
const codes=[87,83,65,68,74,75,82,49,50,51,52,53,54,55,56,57,48,32,85,73,79,80,76,72,71,67,66,78,77,47,69,70,18,81,16,17];
const values=[43,55,1,1,1,1,12,1,0,1,1,0,0,1];
const canonical='cf7.settings.payload.v1'+values.map((v,i)=>'|s'+i+'='+v).join('')+codes.map((v,i)=>'|k'+i+'='+v).join('');
const digest=hash(canonical);
const mutation=hash('cf7.settings.apply.v1|'+[context,owner,sourceEpoch,operation,base,'0',digest].map(v=>Buffer.byteLength(v)+':'+v).join(''));
const cfg={slot,installRoot:repo,swfPath:swf,evidenceDirectory:out,
  metadata:{protocol:2,contextId:context,saveOwnerId:owner,originNamespaceDigest:origin,authorityEpoch:epoch,slot,writeAdmission:'allowed'},
  apply:{v:2,contextId:context,saveOwnerId:owner,authorityEpoch:sourceEpoch,operationToken:operation,saveAttemptId:attempt,
    baseStateToken:base,expectedRevision:0,originMutationRequestDigest:mutation,settingsDigest:digest,expectedCanonical:canonical,keySchemaVersion:2},
  save:{v:2,contextId:context,saveOwnerId:owner,authorityEpoch:sourceEpoch,sourceAuthorityEpoch:sourceEpoch,
    operationToken:operation,saveAttemptId:retry,stateToken:operation,expectedRevision:1,originMutationRequestDigest:mutation,settingsDigest:digest},
  canonical,settingsDigest:digest};
function durable(file,value){const fd=fs.openSync(file,'wx');try{fs.writeFileSync(fd,JSON.stringify(value));fs.fsyncSync(fd);}finally{fs.closeSync(fd);}}
const journal=path.join(out,'journal');
durable(path.join(journal,'contexts.json'),{schema:1,contexts:[context]});
const record={schema:1,recordId:crypto.randomUUID().replace(/-/g,''),contextId:context,saveOwnerId:owner,originNamespaceDigest:origin,slot,
  sourceAuthorityEpoch:sourceEpoch,operationToken:operation,baseStateToken:base,baseRevision:0,targetStateToken:operation,targetRevision:1,
  settingsDigest:digest,originMutationRequestDigest:mutation,digestSchema:1,rootOperationState:'AppliedUnconfirmed',
  currentAttempt:{saveAttemptId:retry,command:'save',dispatchAuthorityEpoch:sourceEpoch,expectedStateToken:operation,expectedRevision:1,dispatchPhase:'Dispatching',attemptOutcome:'Unknown'},
  sequence:2,createdUtc:new Date().toISOString(),lastObservation:null,confirmation:'none'};
durable(path.join(journal,hash(context)+'.json'),record);
durable(path.join(out,'fixture.json'),cfg);
process.stdout.write(path.join(out,'fixture.json')+'\n');
