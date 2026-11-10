"use strict";
const fs=require('node:fs'),path=require('node:path'),{Worker}=require('node:worker_threads');
// The small immutable record is written before optional heavy evidence. The
// caller never awaits native capture, file-copy worker termination, or a dump.
function preserveFirst(directory,name,facts,options={}) {
 fs.mkdirSync(directory,{recursive:true});
 const target=path.join(directory,name+'.json');
 fs.writeFileSync(target,JSON.stringify({preservedUtc:new Date().toISOString(),...facts},null,2)+'\n',{flag:'wx'});
 const create=options.createWorker||((data)=>new Worker(path.join(__dirname,'prefix-worker.js'),{workerData:data}));
 let worker=null,timer=null;
 try {
  worker=create({root:options.root,directory,name});
  // Termination is requested but never awaited by the preservation path.
  timer=setTimeout(()=>{try{void worker.terminate()}catch{}},1500);
  timer.unref?.();
  worker.once('error',()=>clearTimeout(timer));worker.once('exit',()=>clearTimeout(timer));
  worker.unref?.();
 } catch(error) {fs.writeFileSync(path.join(directory,name+'-heavy-error.txt'),error.name+'\n');}
 return {target,heavyEvidence:'external_optional_worker',deadlineMs:1500};
}
module.exports={preserveFirst};
