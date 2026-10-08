#!/usr/bin/env node
'use strict';
// 漫画节拍运镜 dev harness 静态服务：仓根起服，默认自动打开浏览器。
// 用法：node tools/run-book-comic-harness.js [--port=8931] [--no-open]
// 页面参数：?page=prologue|boss  ?source=json（直读源 JSON 调参）  ?reduced=1（低特效）  ?trace（请求回显）
const fs=require('fs'),path=require('path'),http=require('http'),{exec}=require('child_process');
const ROOT=path.resolve(__dirname,'..');
const portArg=process.argv.find(a=>a.startsWith('--port='));
const preferred=portArg?Number(portArg.slice(7)):8931;
const noOpen=process.argv.includes('--no-open');
const mime={'.html':'text/html','.js':'text/javascript','.css':'text/css','.json':'application/json','.png':'image/png','.jpg':'image/jpeg','.svg':'image/svg+xml','.mp3':'audio/mpeg'};
const server=http.createServer((req,res)=>{
    const url=new URL(req.url,'http://localhost');
    const file=path.resolve(ROOT,'.'+decodeURIComponent(url.pathname));
    if(path.relative(ROOT,file).startsWith('..')){res.writeHead(403);res.end();return;}
    fs.readFile(file,(err,data)=>{
        if(err){res.writeHead(404);res.end();return;}
        res.setHeader('Content-Type',(mime[path.extname(file)]||'application/octet-stream')+'; charset=utf-8');
        res.end(data);
    });
});
function listen(port){return new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,'127.0.0.1',resolve)})}
(async()=>{
    try{await listen(preferred)}catch(e){if(e.code!=='EADDRINUSE')throw e;await listen(0)}
    const port=server.address().port;
    const base='http://127.0.0.1:'+port+'/launcher/web/modules/book-comic/dev/harness.html';
    console.log('漫画节拍运镜 harness:');
    console.log('  序章(调参)  '+base+'?page=prologue&source=json');
    console.log('  Boss(调参)  '+base+'?page=boss&source=json');
    console.log('  生产派生    '+base+'?page=prologue');
    console.log('  低特效      '+base+'?page=prologue&source=json&reduced=1');
    console.log('Ctrl+C 停止。');
    if(!noOpen&&process.platform==='win32')exec('start "" "'+base+'?page=prologue&source=json"');
})().catch(e=>{console.error(e);process.exitCode=1});
