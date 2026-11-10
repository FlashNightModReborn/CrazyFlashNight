"use strict";
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),os=require('node:os'),assert=require('node:assert/strict');
const {preserveFirst}=require('./preserve-first');
const {readJson}=require('./bounded-http');
const Identity=require('../lib/runtime-process-identity'),Ports=require('../lib/legacy-http-client');
const [specFile,directory]=process.argv.slice(2);assert(specFile&&directory,'spec and exact evidence directory required');
const spec=JSON.parse(fs.readFileSync(specFile,'utf8').replace(/^\uFEFF/,''));
const root=path.resolve(__dirname,'../..'),expected=Identity.resolveExpectedRuntimeIdentity(root,spec.candidateRoot);
const asLoaderSha256=require('node:crypto').createHash('sha256').update(fs.readFileSync(path.join(root,'scripts/asLoader.swf'))).digest('hex');
assert.equal(asLoaderSha256,spec.asLoaderSha256.toLowerCase(),'ASLoader changed after qualification freeze');
const endpoint=Ports.readExactLauncherPorts(root),actual=Identity.verifyRuntimeIdentity(root,endpoint.httpPort,expected);
assert.equal(actual.buildIdentity.toLowerCase(),spec.buildIdentity.toLowerCase());assert.equal(actual.payloadClosure.toLowerCase(),spec.payloadClosure.toLowerCase());
fs.mkdirSync(directory,{recursive:true});
const began=performance.now(),startUtc=new Date().toISOString();let first=false,last=null,failures=0,rows=0,stopped=false,streak=0,externalSilence=false,hostDirectory=null;
const stopFile=path.join(directory,'seal.request');
function get(full=false){return readJson(endpoint.httpPort,'/issue205/snapshot'+(full?'?evidence=1':''));}
function facts(snapshot,reason){return {schema:'cf7.issue205.external-preservation.v1',reason,startUtc,elapsedMs:performance.now()-began,
 identity:actual,asLoaderSha256,hostOs:{platform:os.platform(),release:os.release(),architecture:os.arch(),cpus:os.cpus().length,freeMemory:os.freemem(),totalMemory:os.totalmem()},
 snapshot,rows,readFailures:failures,sourcePixels:'NOT_CAPTURED',nativeGrab:'NOT_REQUESTED'};}
async function tick(){
 if(stopped)return;
 try{
  const current=Ports.readExactLauncherPorts(root);assert.equal(current.pid,actual.pid,'runtime replacement forbidden');
  const snapshot=await get();
  if(hostDirectory===null)hostDirectory=snapshot.directory;
  assert.equal(snapshot.directory,hostDirectory,'diagnostic session replacement forbidden');
  last=snapshot;rows++;streak=0;
  fs.appendFileSync(path.join(directory,'observer.jsonl'),JSON.stringify({utc:new Date().toISOString(),elapsedMs:performance.now()-began,...snapshot})+'\n');
  if(snapshot.firstSuspect&&!first){first=true;
   preserveFirst(directory,'first-observed',facts(snapshot,'first_suspect'),{root});
   try{fs.writeFileSync(path.join(directory,'first-full-evidence.json'),JSON.stringify(await get(true),null,2)+'\n',{flag:'wx'})}catch(e){fs.writeFileSync(path.join(directory,'first-evidence-read-error.txt'),e.message+'\n')}
  }
 }catch(e){failures++;streak++;fs.appendFileSync(path.join(directory,'observer-errors.jsonl'),JSON.stringify({utc:new Date().toISOString(),elapsedMs:performance.now()-began,error:e.message})+'\n');
  if(streak>=2&&!externalSilence){externalSilence=true;preserveFirst(directory,'first-observer-silence',facts(last,'diagnostic_http_unavailable; game_fault_not_proven'),{root});}
 }
 const elapsed=performance.now()-began;
 if(fs.existsSync(stopFile)||elapsed>73*60*1000){stopped=true;
  preserveFirst(directory,'external-sealed',facts(last,fs.existsSync(stopFile)?'explicit_before_shutdown':'73min_supervisor_budget'),{root});
  process.stdout.write(JSON.stringify({sealed:true,startUtc,elapsedMs:elapsed,rows,failures,firstSuspect:first,externalSilence})+'\n');return;
 }
 setTimeout(tick,Math.max(100,1000-(performance.now()-began)%1000));
}
fs.writeFileSync(path.join(directory,'observer-start.json'),JSON.stringify(facts(null,'start'),null,2)+'\n',{flag:'wx'});
process.stdout.write(JSON.stringify({started:true,startUtc,pid:actual.pid,directory})+'\n');tick();
