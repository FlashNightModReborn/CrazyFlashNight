'use strict';
const assert=require('assert'),fs=require('fs'),path=require('path'),os=require('os'),cp=require('child_process'),crypto=require('crypto');
const {writeReport}=require('./report-io');
const root=path.resolve(__dirname,'../..'),dir=path.join(root,'tmp/stage-intro-report-io',crypto.randomBytes(6).toString('hex'));
fs.mkdirSync(dir,{recursive:true});const target=path.join(dir,'report.json');
writeReport(target,{old:true});assert.deepStrictEqual(JSON.parse(fs.readFileSync(target)),{old:true});
let count=0;
writeReport(target,{retry:true},{write:(p,v)=>{if(++count===1)throw Object.assign(Error('busy'),{code:'EBUSY'});fs.writeFileSync(p,JSON.stringify(v));},wait:()=>{}});
assert.equal(count,2);assert.deepStrictEqual(JSON.parse(fs.readFileSync(target)),{retry:true});
count=0;assert.throws(()=>writeReport(target,{}, {write:()=>{count++;throw Object.assign(Error('permanent busy'),{code:'EBUSY'});},wait:()=>{},attempts:3}),/permanent busy/);assert.equal(count,3);
count=0;assert.throws(()=>writeReport(target,{}, {write:()=>{count++;throw Object.assign(Error('invalid target'),{code:'atomic_target_invalid'});},wait:()=>{}}),/invalid target/);assert.equal(count,1);
assert.deepStrictEqual(JSON.parse(fs.readFileSync(target)),{retry:true});
async function main(){
    if(process.platform==='win32'){
        const ready=path.join(dir,'reader-ready');
        const ps=String.raw`C:\Users\iuo\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe`;
        const script="$f=[IO.File]::Open($env:CF7_INTRO_REPORT_TEST_TARGET,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);try{[IO.File]::WriteAllText($env:CF7_INTRO_REPORT_TEST_READY,'ready');Start-Sleep -Milliseconds 600}finally{$f.Dispose()}";
        const child=cp.spawn(ps,['-NoProfile','-Command',script],{windowsHide:true,stdio:['ignore','ignore','pipe'],env:{...process.env,CF7_INTRO_REPORT_TEST_TARGET:target,CF7_INTRO_REPORT_TEST_READY:ready}});
        let stderr='';child.stderr.on('data',b=>stderr+=b.toString());
        const done=new Promise((resolve,reject)=>{child.on('error',reject);child.on('exit',code=>code===0?resolve():reject(Error(stderr)));});
        const deadline=Date.now()+10000;
        while(!fs.existsSync(ready)){if(Date.now()>deadline)throw Error('Native read-lock fixture did not start');await new Promise(resolve=>setTimeout(resolve,10));}
        const result=writeReport(target,{nativeReaderRecovered:true});
        assert(result.attempts>1&&result.attempts<=101);await done;
        assert.deepStrictEqual(JSON.parse(fs.readFileSync(target)),{nativeReaderRecovered:true});
        console.log('PASS real Windows reader lock: bounded retry retained and replaced the report ('+result.attempts+' attempts).');
    }
    console.log('PASS transient retry, bounded permanent failure and immediate invalid-target rejection; no saves touched.');
}
main().catch(error=>{console.error(error);process.exitCode=1});
