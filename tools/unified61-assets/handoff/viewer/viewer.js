"use strict";
const KIT = JSON.parse(document.getElementById("kitData").textContent);
const CAT = KIT.catalog;
const INITIAL = Object.assign({}, KIT.files);
const FILES = Object.assign({}, KIT.files);
const $ = function(id) { return document.getElementById(id); };
const SVG_NS = "http://www.w3.org/2000/svg";
let lastSvg = "";
let lastContact = "";
let generation = 0;
let importedCount = 0;

function escapeXml(text) {
  return String(text).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");
}
function parseSvg(text) {
  const doc = new DOMParser().parseFromString(text, "image/svg+xml");
  if (doc.querySelector("parsererror")) throw new Error("SVG XML 无法解析");
  return doc.documentElement;
}
function innerSvg(text, prefix) {
  const root = parseSvg(text);
  const ids = new Map();
  root.querySelectorAll("[id]").forEach(function(el) { ids.set(el.id,prefix+el.id); });
  root.querySelectorAll("*").forEach(function(el) {
    Array.from(el.attributes).forEach(function(attr) {
      let value = attr.value;
      if(attr.name==="id") value=ids.get(value);
      else value=value.replace(/url\(#([^)]+)\)/g,function(all,id){return "url(#"+(ids.get(id)||id)+")";});
      el.setAttribute(attr.name,value);
    });
  });
  return Array.from(root.childNodes).map(function(el){return new XMLSerializer().serializeToString(el);}).join("");
}
function pathFor(variant, part, state, baseline) {
  const item=CAT.variants[variant].parts[part];
  let path=item.states[state]||item.states.closed;
  if(baseline&&variant==="unified") path="baseline/"+path;
  return path;
}
function getPose() { return KIT.poses.genders[$("gender").value].find(function(p){return p.id===$("pose").value;}); }
function body(variant, baseline, raster, prefix) {
  const gender=$("gender").value, pose=getPose(), state=$("state").value;
  const map=CAT.variants[variant].fieldsByGender[gender];
  let count=0, result="";
  pose.holders.forEach(function(holder,index){
    const part=map[holder.field];
    if(!part)return;
    const item=CAT.variants[variant].parts[part];
    let content;
    if(raster){
      const r=item.raster;
      content='<image x="'+(-r.originX/r.zoom)+'" y="'+(-r.originY/r.zoom)+'" width="'+(r.width/r.zoom)+'" height="'+(r.height/r.zoom)+'" href="'+FILES[r.path]+'"/>';
    }else content=innerSvg(FILES[pathFor(variant,part,state,baseline)],prefix+index+"_");
    result+='<g data-part="'+part+'" transform="matrix('+holder.matrix.join(" ")+')">'+content+'</g>';
    count++;
  });
  if(count!==15)throw new Error("组装缺件："+count+" / 15");
  if($("mirror").checked)result='<g transform="matrix(-1 0 0 1 0 0)">'+result+'</g>';
  if($("origin").checked)result+='<path d="M-6 0H6 M0-6V6" fill="none" stroke="#ff5353" stroke-width="0.7"/>';
  return result;
}
function svg(variant, baseline, raster, height, prefix, backgroundOverride) {
  const box=CAT.reviewCanvas, width=Math.round(box[2]/box[3]*height), bg=backgroundOverride||$("background").value;
  return '<svg xmlns="'+SVG_NS+'" viewBox="'+box.join(" ")+'" width="'+width+'" height="'+height+'">'+
    (bg==="transparent"?"":'<rect x="'+box[0]+'" y="'+box[1]+'" width="'+box[2]+'" height="'+box[3]+'" fill="'+bg+'"/>')+
    body(variant,baseline,raster,prefix)+'</svg>';
}
function dataSvg(text) { return "data:image/svg+xml;charset=utf-8,"+encodeURIComponent(text); }
function rasterize(text) {
  return new Promise(function(resolve,reject){
    const root=parseSvg(text), image=new Image();
    image.onload=function(){
      const canvas=document.createElement("canvas");
      canvas.width=Number(root.getAttribute("width"));canvas.height=Number(root.getAttribute("height"));
      const context=canvas.getContext("2d");
      context.drawImage(image,0,0,canvas.width,canvas.height);
      resolve(canvas.toDataURL("image/png"));
    };
    image.onerror=function(){reject(new Error("浏览器无法渲染当前 SVG"));};
    image.src=dataSvg(text);
  });
}
function imageElement(uri, text) {
  const image=document.createElement("img");image.src=uri;image.alt=text;return image;
}
function card(title, image, checker) {
  const element=document.createElement("article");element.className="card";
  const head=document.createElement("h3");head.textContent=title;element.appendChild(head);
  const wrap=document.createElement("div");wrap.className="image-wrap"+(checker?" checker":"");wrap.appendChild(image);
  element.appendChild(wrap);return element;
}
function fillPoses() {
  const selected=$("pose").value, select=$("pose");select.replaceChildren();
  KIT.poses.genders[$("gender").value].forEach(function(pose){
    const opt=document.createElement("option");opt.value=pose.id;
    opt.textContent=pose.label+(pose.group==="archived_authored"?" · 作者参考关键帧":"");
    select.appendChild(opt);
  });
  if(Array.from(select.options).some(function(o){return o.value===selected;}))select.value=selected;
}
function partPreview(text) {
  const root=parseSvg(text), view=root.getAttribute("viewBox").split(/\s+/).map(Number);
  const x=view[0],y=view[1],w=view[2],h=view[3], r=Math.max(w,h)*.035;
  const cross=document.createElementNS(SVG_NS,"path");
  cross.setAttribute("d","M"+(-r)+" 0H"+r+" M0 "+(-r)+"V"+r);
  cross.setAttribute("fill","none");cross.setAttribute("stroke","#ff5050");cross.setAttribute("stroke-width",String(Math.max(w,h)*.004));
  root.appendChild(cross);
  root.setAttribute("width","300");root.setAttribute("height","250");
  root.setAttribute("preserveAspectRatio","xMidYMid meet");
  return new XMLSerializer().serializeToString(root);
}
function updateParts() {
  const part=$("part").value, spec=CAT.variants.unified.parts[part], state=$("state").value;
  const root=$("partsReview");root.replaceChildren();
  [true,false].forEach(function(base){
    const image=imageElement(dataSvg(partPreview(FILES[pathFor("unified",part,state,base)])),spec.label);
    root.appendChild(card((base?"现役基准":"工作稿")+" · "+spec.label,image,true));
  });
}
function iconSvg(slot, frame, prefix) {
  const recipe=CAT.icons[slot];
  const shadow=frame===1?innerSvg(FILES["data/icon-shadow.svg"],prefix+"shadow_"):"";
  const crop=innerSvg(FILES["data/icon-crop.svg"],prefix+"crop_");
  const art=innerSvg(FILES[pathFor("unified",recipe.part,"closed",false)],prefix+"art_");
  return '<svg xmlns="'+SVG_NS+'" viewBox="-12 -12 24 24" width="24" height="24">'+shadow+
    '<defs><clipPath id="'+prefix+'clip" clipPathUnits="userSpaceOnUse">'+crop+'</clipPath></defs>'+
    '<g clip-path="url(#'+prefix+'clip)"><g transform="matrix('+recipe.matrix.join(" ")+')">'+art+'</g></g></svg>';
}
async function update() {
  const stamp=++generation;
  try{
    const height=Number($("height").value), raster=$("source").value==="raster";
    if(raster&&$("state").value!=="closed"){$("state").value="closed";}
    const specs=$("comparison").value==="family"?
      [["regular",false,"普通61"],["titanium",false,"钛合金61"],["unified",false,"统合61工作稿"]]:
      [["unified",true,"现役基准"],["unified",false,"工作稿"]];
    const main=$("mainReview");main.replaceChildren();
    const svgRows=[];
    for(let i=0;i<specs.length;i++){
      const item=specs[i],text=svg(item[0],item[1],raster,height,"main"+i+"_"), uri=await rasterize(text);
      if(stamp!==generation)return;
      main.appendChild(card(item[2],imageElement(uri,item[2]),$("background").value==="transparent"));svgRows.push(text);
    }
    lastSvg=svg("unified",false,false,height,"download_");
    const width=Number(parseSvg(svgRows[0]).getAttribute("width")), gap=16;
    const contactWidth=(width+gap)*svgRows.length+gap, contactHeight=height+60;
    lastContact='<svg xmlns="'+SVG_NS+'" width="'+contactWidth+'" height="'+contactHeight+'" viewBox="0 0 '+contactWidth+' '+contactHeight+'"><rect width="100%" height="100%" fill="#18242f"/>';
    svgRows.forEach(function(text,i){
      lastContact+='<text x="'+(gap+i*(width+gap))+'" y="23" font-size="14" fill="#eef1f3" font-family="sans-serif">'+escapeXml(specs[i][2])+'</text>';
      const nested=parseSvg(text);nested.setAttribute("x",String(gap+i*(width+gap)));nested.setAttribute("y","38");
      lastContact+=new XMLSerializer().serializeToString(nested);
    });lastContact+='</svg>';
    $("placementInfo").textContent="12个分件 · 15次放置 · "+getPose().label;
    $("notice").textContent=raster?"此模式显示现有导出像素，胸甲仅含闭合帧；工作 SVG 的修改请切换回可编辑矢量查看。":
      "静态姿态预览。画布高度为评审档位，实际游戏角色像素高度待 Windows 端核对。开门和开火只应用于统合61。";
    const small=$("smallReview");small.replaceChildren();
    for(const size of [96,128,160]){
      const tile=document.createElement("article");tile.className="small-card";
      const heading=document.createElement("h3");heading.textContent=size+" px 画布 · 基准 / 工作稿";tile.appendChild(heading);
      const pair=document.createElement("div");pair.className="small-pair complex";
      for(const base of [true,false]){
        const uri=await rasterize(svg("unified",base,false,size,"small"+size+(base?"b":"w")+"_","transparent"));
        if(stamp!==generation)return;
        const image=imageElement(uri,base?"基准":"工作稿"), multiplier=$("pixelZoom").checked?2:1;
        const naturalWidth=Math.round(CAT.reviewCanvas[2]/CAT.reviewCanvas[3]*size);
        image.style.width=naturalWidth*multiplier+"px";image.style.height=size*multiplier+"px";
        if(multiplier===2)image.style.imageRendering="pixelated";
        pair.appendChild(image);
      }tile.appendChild(pair);small.appendChild(tile);
    }
    const icons=$("iconsReview");icons.replaceChildren();
    for(const slot of Object.keys(CAT.icons)){
      const el=document.createElement("article");el.className="icon-card";
      const title=document.createElement("span");title.textContent=CAT.icons[slot].label;el.appendChild(title);
      const holder=document.createElement("div");holder.className="icon-images";
      for(const frame of [1,2]){
        const uri=await rasterize(iconSvg(slot,frame,"ic"+slot+frame+"_"));
        if(stamp!==generation)return;
        const image=imageElement(uri,"图标帧"+frame);image.width=48;image.height=48;holder.appendChild(image);
      }
      el.appendChild(holder);
      const caption=document.createElement("div");caption.className="icon-caption";caption.textContent="24px取样 · 2倍放大 · 物品栏 / 掉落";el.appendChild(caption);
      icons.appendChild(el);
    }
    updateParts();window.TYPE61_READY={ok:true,placements:15,pose:getPose().id,gender:$("gender").value,revision:generation};
  }catch(error){$("notice").textContent="预览失败："+error.message;window.TYPE61_READY={ok:false,error:error.message};}
}
function validateFile(text,path){
  const root=parseSvg(text), original=parseSvg(INITIAL["baseline/"+path]);
  for(const key of ["viewBox","width","height"])if(root.getAttribute(key)!==original.getAttribute(key))throw new Error(path+"：请保留 "+key);
  const allowed=new Set(["svg","g","defs","title","desc","metadata","path","rect","circle","ellipse","line","polyline","polygon","linearGradient","radialGradient","stop","clipPath"]);
  for(const element of [root].concat(Array.from(root.querySelectorAll("*")))){
    if(!allowed.has(element.localName))throw new Error("不支持的 SVG 元素："+element.localName);
    for(const attr of Array.from(element.attributes)){
      if(/^on/i.test(attr.localName)||["href","src","filter","mask","style","vector-effect"].includes(attr.localName))throw new Error("不支持的 SVG 属性："+attr.localName);
      for(const ref of attr.value.matchAll(/url\(([^)]+)\)/g))if(!ref[1].startsWith("#"))throw new Error("请移除外部资源引用");
    }
  }
}
async function importFiles(list, directory){
  try{
    const expected=[];
    Object.values(CAT.variants.unified.parts).forEach(function(part){Object.values(part.states).forEach(function(path){expected.push(path);});});
    const changes={};
    for(const file of list){
      if(!file.name.toLowerCase().endsWith(".svg"))continue;
      const relative=(file.webkitRelativePath||file.name).replace(/\\/g,"/");
      let match=expected.find(function(path){return relative===path||relative.endsWith("/"+path);});
      if(!match&&directory)match=expected.find(function(path){const short=path.replace("assets/unified/","");return relative===short||relative.endsWith("/"+short);});
      if(!match&&!directory){
        const options=expected.filter(function(path){return path.split("/").pop()===file.name;});
        if(options.length===1)match=options[0];
      }
      if(!match)continue;
      if(Object.prototype.hasOwnProperty.call(changes,match))throw new Error("重复的工作分件："+match);
      const text=await file.text();validateFile(text,match);changes[match]=text;
    }
    if(!Object.keys(changes).length)throw new Error("没有找到 assets/unified 下的工作分件");
    Object.assign(FILES,changes);importedCount=Object.keys(changes).length;$("loadStatus").textContent="已载入 "+importedCount+" 个工作文件";await update();
  }catch(error){$("notice").textContent="载入失败："+error.message;}
}
function download(content,name,type){
  const url=URL.createObjectURL(new Blob([content],{type:type})),a=document.createElement("a");a.href=url;a.download=name;a.click();setTimeout(function(){URL.revokeObjectURL(url);},1000);
}
Object.entries(CAT.variants.unified.parts).forEach(function(pair){const o=document.createElement("option");o.value=pair[0];o.textContent=pair[1].label;$("part").appendChild(o);});
for(const id of ["comparison","gender","pose","state","height","background","source","mirror","origin","pixelZoom"])$(id).addEventListener("change",function(){if(id==="gender")fillPoses();update();});
$("part").addEventListener("change",updateParts);
$("loadFolder").onclick=function(){$("folderInput").click();};$("loadFiles").onclick=function(){$("fileInput").click();};
$("folderInput").onchange=function(){importFiles(this.files,true);};$("fileInput").onchange=function(){importFiles(this.files,false);};
$("reset").onclick=function(){Object.assign(FILES,INITIAL);importedCount=0;$("loadStatus").textContent="包内工作稿";update();};
$("exportSvg").onclick=function(){download(lastSvg,"type61_"+$("gender").value+"_"+$("pose").value+"_"+$("state").value+".svg","image/svg+xml");};
$("exportPng").onclick=async function(){try{const uri=await rasterize(lastContact),a=document.createElement("a");a.href=uri;a.download="type61_review.png";a.click();}catch(e){$("notice").textContent=e.message;}};
window.Type61Kit={update:update,compose:svg,importFiles:importFiles,files:FILES,catalog:CAT,poses:KIT.poses,iconSvg:iconSvg};
fillPoses();update();
