'use strict';
// Read-only tooling adapter. Never reproduce domain rules or persist a render projection.
const path=require('path'),cp=require('child_process');
const sourceRoot=path.resolve(__dirname,'../..'),cache=new Map();
function invoke(command,root=sourceRoot,input){
 const args=['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(sourceRoot,'tools/map-workbench/run.ps1'),'-Command',command,'-ProjectRoot',root];
 const result=cp.spawnSync(path.join(process.env.SystemRoot||'C:/Windows','System32/WindowsPowerShell/v1.0/powershell.exe'),args,{encoding:'utf8',input:input===undefined?undefined:JSON.stringify(input),maxBuffer:24*1024*1024,timeout:120000,windowsHide:true});
 if(result.error)throw result.error;
 const line=(result.stdout||'').trim().split(/\r?\n/).at(-1);let value;
 try{value=JSON.parse(line);}catch(error){throw new Error('C# map adapter failed: '+(result.stderr||result.stdout||error.message));}
 if(result.status!==0||value.success===false)throw new Error(value.error||result.stderr||'C# map validation failed.');
 return value;
}
function loadRenderDefinition(root=sourceRoot){const key='render:'+path.resolve(root);if(!cache.has(key))cache.set(key,invoke('render-definition',root));return cache.get(key);}
function validateContent(root=sourceRoot){const key='validate:'+path.resolve(root);if(!cache.has(key))cache.set(key,invoke('validate-content',root));return cache.get(key);}
module.exports={invoke,loadRenderDefinition,validateContent};
