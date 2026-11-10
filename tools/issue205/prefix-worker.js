"use strict";
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{workerData:d}=require('node:worker_threads');
const records=[];
for(const name of ['launcher.log','launcher.log.1']) {
 const source=path.join(d.root,'logs',name);
 if(!fs.existsSync(source))continue;
 const stat=fs.statSync(source),size=Math.min(stat.size,8*1024*1024),fd=fs.openSync(source,'r');
 const bytes=Buffer.alloc(size);let read=0;
 try{while(read<size){const n=fs.readSync(fd,bytes,read,size-read,read);if(!n)break;read+=n;}}finally{fs.closeSync(fd)}
 const body=bytes.subarray(0,read),output=path.join(d.directory,d.name+'-'+name+'.prefix');
 fs.writeFileSync(output,body,{flag:'wx'});
 records.push({name,sourceSizeAtOpen:stat.size,bytesPreserved:read,completePrefix:read===stat.size,
  sha256:crypto.createHash('sha256').update(body).digest('hex'),output});
}
fs.writeFileSync(path.join(d.directory,d.name+'-log-prefix-manifest.json'),JSON.stringify({utc:new Date().toISOString(),records},null,2)+'\n',{flag:'wx'});
