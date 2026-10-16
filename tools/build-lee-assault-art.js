'use strict';
// Native SWF vectors remain the art authority. This tool lays them out as comic panels.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),cp=require('child_process');
const root=process.env.CF7_ART_ROOT||path.resolve(__dirname,'..');
const dest=path.join(root,'launcher/web/assets/book-comic/lee');
const sourceRels=[...[3,2,4,5].map(n=>'flashswf/backgrounds/black-dragon-original/hthhltnb_'+n+'_BG.swf'),
 'flashswf/backgrounds/hthhltnb_5_BG.swf','flashswf/arts/things4.swf','flashswf/arts/things5.swf'];
const digest=b=>crypto.createHash('sha256').update(b).digest('hex');
const sources=()=>sourceRels.map(file=>({file,sha256:digest(fs.readFileSync(path.join(root,file)))}));
const manifestPath=path.join(dest,'manifest.json');
if(process.argv.includes('--check')){
 const m=JSON.parse(fs.readFileSync(manifestPath,'utf8'));
 if(JSON.stringify(m.sources)!==JSON.stringify(sources()))throw Error('Lee comic native inputs changed; rebuild art');
 for(const row of m.files){const bytes=fs.readFileSync(path.join(dest,row.file));if(digest(bytes)!==row.sha256||bytes.length!==row.bytes)throw Error('Lee comic art changed: '+row.file)}
 console.log('Lee comic native sources and '+m.files.length+' vector pages verified');process.exit(0);
}
let imports=process.argv.find(a=>a.startsWith('--imports-dir='));imports=imports?imports.slice(14):path.join(root,'tmp/lee-assault-art-source');
function run(args){const r=cp.spawnSync(path.join(root,'tools/ffdec/ffdec-cli.exe'),args,{cwd:root,encoding:'utf8',windowsHide:true,timeout:240000});if(r.status!==0)throw Error('Native vector export failed: '+(r.stderr||r.stdout).slice(-800))}
function allFiles(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?allFiles(path.join(dir,e.name)):[path.join(dir,e.name)])}
function native(dir,frame){const file=allFiles(path.join(imports,dir)).find(p=>path.basename(p)===frame+'.svg');if(!file)throw Error('Missing native frame '+dir+'/'+frame);return file}
async function main(){
 fs.mkdirSync(imports,{recursive:true});
 if(!fs.existsSync(path.join(imports,'map3-before/1.svg'))){
  for(const n of [3,2,4,5])run(['-select','1','-format','frame:svg','-export','frame',path.join(imports,'map'+n+'-before'),path.join(root,'flashswf/backgrounds/black-dragon-original/hthhltnb_'+n+'_BG.swf')]);
  run(['-select','1','-format','frame:svg','-export','frame',path.join(imports,'map5-after'),path.join(root,'flashswf/backgrounds/hthhltnb_5_BG.swf')]);
  for(const [dir,id,swf] of [['lee',906,'things4'],['unit1841',1841,'things5'],['unit1783',1783,'things5']])run(['-selectid',String(id),'-format','sprite:svg','-export','sprite',path.join(imports,dir),path.join(root,'flashswf/arts/'+swf+'.swf')]);
 }
 const {chromium}=require(path.join(root,'launcher/perf/node_modules/playwright'));
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
 const page=await browser.newPage();
 async function fragment(file,selection){
  await page.setContent(fs.readFileSync(file,'utf8'));
  return page.evaluate(selection=>{
   const svg=document.querySelector('svg'),g=svg.querySelector(':scope > g');
   if(selection)for(const node of [...g.children]){const match=selection==='man'?node.id==='man':node.getAttribute('xlink:href')===selection;if(!match)node.remove()}
   const wanted=new Set(),pending=[];
   function refs(text){for(const m of text.matchAll(/(?:href=["']#|url\(#)([^"')]+)["')]/g))if(!wanted.has(m[1])){wanted.add(m[1]);pending.push(m[1])}}
   refs(g.outerHTML);
   while(pending.length){const el=document.getElementById(pending.pop());if(el)refs(el.outerHTML)}
   const defs=svg.querySelector(':scope > defs');
   if(defs)for(const el of [...defs.children])if(!wanted.has(el.id))el.remove();
   const b=svg.getBBox();if(!(b.width>5&&b.height>5))throw Error('Empty actor/scene');
   svg.setAttribute('viewBox',[b.x-2,b.y-2,b.width+4,b.height+4].join(' '));svg.setAttribute('width',b.width+4);svg.setAttribute('height',b.height+4);
   return new XMLSerializer().serializeToString(svg);
  },selection);
 }
 const bg=[];for(const n of [3,2,4,5])bg.push(await fragment(native('map'+n+'-before',1),null));
 const lee=await fragment(native('lee',2),'man'),punch=await fragment(native('lee',36),'man');
 const fallen=await fragment(native('lee',96),'man');
 const horse=await fragment(native('unit1841',20),'man'),dragon=await fragment(native('unit1783',2),'man');
 const dragonDown=await fragment(native('unit1783',99),'man');
 const captive=await fragment(native('map5-after',1),'#sprite20');
 await browser.close();
 const data=s=>'data:image/svg+xml;base64,'+Buffer.from(s).toString('base64');
 const files=[];
 function make(name,count,room,draw){
  let out='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1024" height="'+count*384+'" viewBox="0 0 1024 '+count*384+'"><defs>';
  const pictures={bg:bg[room],lee,punch,fallen,horse,dragon,dragonDown,captive};
  for(const [key,value]of Object.entries({bg:bg[room]}))out+='<image id="'+key+'" xlink:href="'+data(value)+'" width="1024" height="384" preserveAspectRatio="xMidYMid meet"/>';
  out+='</defs>';
  function actor(key,x,y,w,h,flip=false){return '<svg x="'+x+'" y="'+y+'" width="'+w+'" height="'+h+'" viewBox="0 0 '+w+' '+h+'"><g transform="'+(flip?'translate('+w+' 0) scale(-1 1)':'')+(key==='fallen'?' rotate(-75 '+w/2+' '+h/2+')':'')+'"><image xlink:href="'+data(pictures[key])+'" width="'+w+'" height="'+h+'" preserveAspectRatio="xMidYMid meet"/></g></svg>'}
  for(let i=0;i<count;i++){
   out+='<svg y="'+i*384+'" width="1024" height="384" viewBox="0 0 1024 384"><rect width="1024" height="384" fill="#101519"/><use xlink:href="#bg"/><rect width="1024" height="384" fill="#061017" opacity=".35"/>';
   out+=draw(i,actor);out+='<rect x="3" y="3" width="1018" height="378" fill="none" stroke="#07090a" stroke-width="6"/></svg>';
  }
  out+='</svg>\n';const file=name+'.svg';fs.writeFileSync(path.join(dest,file),out);files.push({file,sha256:digest(Buffer.from(out)),bytes:Buffer.byteLength(out)});
 }
 const flash='<path d="M370 0L342 84L377 78L328 174L360 162L319 290" fill="none" stroke="#dbffff" stroke-width="5"/><path d="M322 0L355 70L327 84L367 144L338 164L350 295" fill="none" stroke="#65d9ef" stroke-width="2"/>';
 const cracks='<path d="M320 20L390 95L357 140L425 210L370 295M357 140L287 128L214 182M425 210L531 187L575 235" fill="none" stroke="#070808" stroke-width="7"/>';
 fs.mkdirSync(dest,{recursive:true});
 make('ambush',4,2,(i,a)=>i===0?a('lee',250,70,430,280)+a('horse',-90,40,650,320):i===1?a('horse',100,30,830,350)+a('fallen',590,50,350,300):i===2?a('fallen',150,100,500,250)+a('dragon',630,30,350,320):a('captive',250,0,500,370));
 make('captured',3,3,(i,a)=>a('captive',i===1?160:260,-10,i===1?700:500,390)+'<path d="M0 50H1024" stroke="#3e332f" stroke-width="7"/>');
 make('breakout',4,3,(i,a)=>i<2?a('captive',240,-10,520,390)+(i===1?'<path d="M440 60L480 120L525 60L575 150" stroke="#edc872" stroke-width="5" fill="none"/>':''):cracks+a(i===2?'punch':'lee',100,35,600,340)+(i===3?a('dragon',660,40,360,320):''));
 make('victory',3,3,(i,a)=>a('dragonDown',510,120,470,230)+a(i===0?'punch':'lee',i===2?100:160,40,450,300)+(i===2?'<path d="M0 0H150V384H0" fill="#8da591" opacity=".22"/>':''));
 for(const file of ['room1.svg','room2.svg','room3.svg','room4.svg','awakening.svg']){
  const old=fs.existsSync(manifestPath)?JSON.parse(fs.readFileSync(manifestPath,'utf8')).files.find(r=>r.file===file):null;
  const target=path.join(dest,file);if(old&&fs.existsSync(target)){if(digest(fs.readFileSync(target))!==old.sha256)throw Error('Changed retired art: '+file);fs.unlinkSync(target)}
 }
 fs.writeFileSync(manifestPath,JSON.stringify({schema:'lee-assault-comic-art.v1',generator:'tools/build-lee-assault-art.js',nativeVectors:true,sources:sources(),files},null,2)+'\n');
 console.log('Built '+files.length+' native vector comic pages, '+files.reduce((a,f)=>a+f.bytes,0)+' bytes');
}
main().catch(e=>{console.error(e);process.exitCode=1});
