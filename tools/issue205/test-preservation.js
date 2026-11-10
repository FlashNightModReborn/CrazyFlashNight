"use strict";
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),{EventEmitter}=require('node:events');
const {preserveFirst}=require('./preserve-first');
const {readJson}=require('./bounded-http');
test('R0 an HTTP peer that keeps trickling cannot extend the absolute evidence deadline',async()=>{
 const server=require('node:http').createServer((req,res)=>{
  res.writeHead(200);res.write('{');const interval=setInterval(()=>res.write(' '),20);
  res.on('close',()=>clearInterval(interval));
 });
 await new Promise(r=>server.listen(0,'localhost',r));const began=performance.now();
 try{await assert.rejects(readJson(server.address().port,'/',120),/absolute snapshot deadline|snapshot aborted/);
  assert(performance.now()-began<1200);
 }finally{server.closeAllConnections();await new Promise(r=>server.close(r));}
});
test('R0 first facts survive a permanently unresolved optional evidence worker',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'cf7-205-r0-'));
 let began=false;
 const started=performance.now();
 const record=preserveFirst(dir,'first',{reason:'synthetic F silence',generation:7},{createWorker:()=>{
  assert(fs.existsSync(path.join(dir,'first.json')),'seal precedes heavy worker creation');began=true;
  const worker=new EventEmitter();worker.terminate=()=>new Promise(()=>{});worker.unref=()=>{};return worker;
 }});
 assert(began);assert(performance.now()-started<1000,'optional worker cannot be on the awaited path');
 assert.equal(JSON.parse(fs.readFileSync(record.target)).generation,7);
 assert.throws(()=>preserveFirst(dir,'first',{generation:8}),/EEXIST/,'first incident cannot be overwritten');
});
