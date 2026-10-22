'use strict';
const fs=require('fs'),path=require('path'),http=require('http'),crypto=require('crypto');
const root=path.resolve(__dirname,'../..');
function checked(base,relative){const p=path.resolve(base,relative);if(!p.startsWith(path.resolve(base)+path.sep))throw Error('Path outside allowed root');return p;}
async function startReviewServer(candidate,port=0){
 const directory=path.resolve(candidate),manifest=JSON.parse(fs.readFileSync(path.join(directory,'manifest.json'),'utf8'));
 const browserReport=path.join(directory,'browser-report.json');
 const sha=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
 const captures=new Map(),noPreview=new Set();
 if(fs.existsSync(browserReport)){
  const report=JSON.parse(fs.readFileSync(browserReport,'utf8'));
  if((report.consumerPass||report.pass)&&report.manifestSha256===sha(path.join(directory,'manifest.json'))){
   for(const view of report.views||[]){const file=checked(directory,view.file);if(fs.existsSync(file)&&sha(file)===view.sha256)captures.set(view.id,file);}
   for(const entry of report.noPreviewEntries||[])noPreview.add(entry.id);
  }
 }
 for(const stage of manifest.stages){stage.hasConsumerCapture=captures.has(stage.id);stage.noPreviewSurface=noPreview.has(stage.id);}
 const stages=new Map(manifest.stages.map(s=>[s.id,s]));
 const server=http.createServer((req,res)=>{
  try{
   const url=new URL(req.url,'http://localhost');let file;
   if(url.pathname==='/manifest'){res.writeHead(200,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});res.end(JSON.stringify(manifest));return;}
   if(url.pathname==='/')file=path.join(__dirname,'review.html');
   else{const match=url.pathname.match(/^\/image\/(original|baseline|candidate|thumb|consumer)\/(stage_\d+_\d+)$/);if(!match||!stages.has(match[2]))throw Error('Unknown image');const s=stages.get(match[2]);
    if(match[1]==='original')file=checked(path.join(root,'launcher/web'),s.original);
    else if(match[1]==='baseline')file=checked(root,s.baseline);
    else if(match[1]==='consumer'){file=captures.get(s.id);if(!file)throw Error('No verified consumer capture');}
    else file=checked(directory,match[1]==='thumb'?s.thumb:s.file);
   }
   const mime={'.html':'text/html; charset=utf-8','.png':'image/png','.jpg':'image/jpeg','.webp':'image/webp','.svg':'image/svg+xml'}[path.extname(file)];
   fs.readFile(file,(error,bytes)=>{res.writeHead(error?404:200,{'Content-Type':mime||'application/octet-stream','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(error?'Not found':bytes)});
  }catch(error){res.writeHead(404,{'Content-Type':'text/plain; charset=utf-8'});res.end('Not found');}
 });
 await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,'127.0.0.1',resolve)});return {server,url:'http://127.0.0.1:'+server.address().port+'/'};
}
module.exports={startReviewServer};
if(require.main===module){const candidate=process.argv[2];if(!candidate)throw Error('Usage: node tools/stage-preview/review-server.js <candidate-directory> [port]');startReviewServer(candidate,Number(process.argv[3]||0)).then(({url})=>console.log(url));}
