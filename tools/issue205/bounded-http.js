"use strict";
const http=require('node:http');
function readJson(port,route,deadlineMs=900) {
 return new Promise((resolve,reject)=>{
  let done=false;
  const finish=(error,value)=>{if(done)return;done=true;clearTimeout(timer);error?reject(error):resolve(value)};
  const req=http.get({hostname:'localhost',port,path:route},res=>{
   const chunks=[];let size=0;
   res.on('data',b=>{size+=b.length;if(size>2*1024*1024)req.destroy(Error('snapshot size bound'));else chunks.push(b)});
   res.on('error',e=>finish(e));res.on('aborted',()=>finish(Error('snapshot aborted')));
   res.on('end',()=>{try{if(res.statusCode!==200)throw Error('HTTP '+res.statusCode);finish(null,JSON.parse(Buffer.concat(chunks).toString('utf8')))}catch(e){finish(e)}});
  });
  const timer=setTimeout(()=>req.destroy(Error('absolute snapshot deadline')),deadlineMs);
  req.on('error',e=>finish(e));
 });
}
module.exports={readJson};
