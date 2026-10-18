const fs=require('fs'),zlib=require('zlib'),crypto=require('crypto');
const file=process.argv[2],raw=fs.readFileSync(file),body=raw.toString('ascii',0,3)==='CWS'?zlib.inflateSync(raw.subarray(8)):raw.subarray(8);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
function str(b,p){const e=b.indexOf(0,p);if(e<0)throw Error('String');return {s:b.toString('utf8',p,e),p:e+1};}
function push(b,pool){let p=0,out=[];while(p<b.length){const t=b[p++];if(t===0){const s=str(b,p);p=s.p;out.push(s.s);}else if(t===8){out.push(pool[b[p++]]);}else if(t===9){out.push(pool[b.readUInt16LE(p)]);p+=2;}else if(t===4){out.push({register:b[p++]});}else if(t===1||t===7){p+=4;}else if(t===6){p+=8;}else if(t===5){p++;}else if(t!==2&&t!==3)throw Error('Push '+t);}return out;}
const found=[];
function actions(buf,owner,inherited=[]){let p=0,pool=inherited,recent=[];while(p<buf.length){const at=p,code=buf[p++];if(code===0)break;let rec=Buffer.alloc(0);if(code>=128){const n=buf.readUInt16LE(p);p+=2;rec=buf.subarray(p,p+n);p+=n;}
 let detail={code:code.toString(16),offset:at};
 if(code===0x88){let q=2;pool=[];const n=rec.readUInt16LE(0);for(let i=0;i<n;i++){const v=str(rec,q);pool.push(v.s);q=v.p;}detail.poolSize=pool.length;}
 if(code===0x96)detail.values=push(rec,pool);
 if(code===0x8e||code===0x9b){const name=str(rec,0);let q=name.p,n=rec.readUInt16LE(q);q+=code===0x8e?5:2;const params=[];for(let i=0;i<n;i++){if(code===0x8e)q++;const v=str(rec,q);params.push(v.s);q=v.p;}const size=rec.readUInt16LE(q),fn=buf.subarray(p,p+size);if(fn.length!==size)throw Error('Body');
  if(size>=10000){const values=[];let x=0,localPool=pool;while(x<fn.length){const c=fn[x++];if(!c)break;if(c<128)continue;const l=fn.readUInt16LE(x);x+=2;const r=fn.subarray(x,x+l);x+=l;if(c===0x96)values.push(...push(r,localPool).filter(v=>typeof v==='string'));if(c===0x88){let k=2;localPool=[];for(let j=0;j<r.readUInt16LE(0);j++){let v=str(r,k);k=v.p;localPool.push(v.s);}}if(c===0x8e||c===0x9b){let v=str(r,0),k=v.p,count=r.readUInt16LE(k);k+=c===0x8e?5:2;for(let j=0;j<count;j++){if(c===0x8e)k++;k=str(r,k).p;}x+=r.readUInt16LE(k);}}
   found.push({owner,name:name.s||'(anon)',codeSize:size,offset:at,params,bodySha256:sha(fn),preceding:recent.slice(-8),strings:[...new Set(values)].slice(0,110)});
  }actions(fn,owner+' > '+(name.s||'(anon)'),pool);p+=size;detail.functionSize=size;}
 recent.push(detail);if(recent.length>10)recent.shift();
}}
function tags(p,end,sprite){let frame=0;while(p<end){const h=body.readUInt16LE(p);p+=2;const c=h>>6;let n=h&63;if(n===63){n=body.readUInt32LE(p);p+=4;}const next=p+n;if(c===0)break;if(c===39)tags(p+4,next,body.readUInt16LE(p));if(c===12)actions(body.subarray(p,next),'DoAction[sprite='+sprite+' frame='+frame+']');if(c===59)actions(body.subarray(p+2,next),'DoInitAction[sprite='+body.readUInt16LE(p)+']');if(c===1)frame++;p=next;}}
tags(Math.ceil((5+(body[0]>>3)*4)/8)+4,body.length,null);
console.log(JSON.stringify({file,swfSha256:sha(raw),functions:found.sort((a,b)=>b.codeSize-a.codeSize)},null,2));
