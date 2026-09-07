'use strict';
// Read-only diagnostic: infer assignment labels of anonymous AVM1 frame functions.
const fs=require('fs'),path=require('path'),vm=require('vm');
const source=fs.readFileSync(path.join(__dirname,'../swf-function-sizes.js'),'utf8');
if(!/\nmain\(\);\s*$/.test(source))throw new Error('SWF scanner entry changed.');
const baseline=process.argv.includes('--baseline')?require('child_process').execFileSync('git',['show','HEAD:scripts/asLoader.swf'],{cwd:path.resolve(__dirname,'../..'),maxBuffer:8*1024*1024}):null;
const sandbox={require:name=>name==='fs'&&baseline?Object.assign({},fs,{readFileSync:()=>baseline}):require(name),module:{exports:{}},console,process};
vm.runInNewContext(source.replace(/\nmain\(\);\s*$/,'\nmodule.exports={readSwf,tagAreaStart,parseDF,parseDF2,readCStr};'),sandbox);
const api=sandbox.module.exports;
function actions(buf,owner,constants=[]){let off=0,tail=[];
 while(off<buf.length){const code=buf[off++];if(!code)break;if(code<128)continue;if(off+2>buf.length)throw Error('Truncated action');const len=buf.readUInt16LE(off);off+=2;const rec=buf.subarray(off,off+len);off+=len;
  if(code===0x88){constants=[];let p=2;for(let i=0;i<rec.readUInt16LE(0);i++){const s=api.readCStr(rec,p);constants.push(s.str);p=s.next;}}
  if(code===0x96){let p=0;while(p<rec.length){const type=rec[p++];let text='';if(type===0){const s=api.readCStr(rec,p);text=s.str;p=s.next;}else if(type===8)text=constants[rec[p++]];else if(type===9){text=constants[rec.readUInt16LE(p)];p+=2;}else p+=({1:4,2:0,3:0,4:1,5:1,6:8,7:4})[type]??(()=>{throw Error('Unknown push type');})();if(text)tail.push(text);if(tail.length>16)tail.shift();}}
  if(code===0x8e||code===0x9b){const f=code===0x8e?api.parseDF2(rec):api.parseDF(rec);if(f.codeSize>=45000)console.log(JSON.stringify({owner,name:f.name||'(anon)',bytes:f.codeSize,precedingPushes:tail}));actions(buf.subarray(off,off+f.codeSize),owner+' > '+(f.name||tail.at(-1)||'(anon)'),constants);off+=f.codeSize;}
 }
}
function tags(buf,start,owner){let off=start,frame=0;while(off+2<=buf.length){const head=buf.readUInt16LE(off);off+=2;const code=head>>6;let len=head&63;if(len===63){len=buf.readUInt32LE(off);off+=4;}const body=buf.subarray(off,off+len);off+=len;if(code===39)tags(body,4,'sprite '+body.readUInt16LE(0));else if(code===12)actions(body,owner+' frame '+frame);else if(code===59)actions(body.subarray(2),'class sprite '+body.readUInt16LE(0));if(code===1)frame++;if(!code)break;}}
const swf=api.readSwf(path.resolve(__dirname,'../../scripts/asLoader.swf'));tags(swf.body,api.tagAreaStart(swf.body),'root');
