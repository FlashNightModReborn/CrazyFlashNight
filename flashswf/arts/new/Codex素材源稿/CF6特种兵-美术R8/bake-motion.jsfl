function enc(v){if(v===null || v===undefined)return "null";if(typeof v=="string")return '"'+v.replace(/\\/g,'\\\\').replace(/"/g,'\\"').replace(/\n/g,'\\n').replace(/\r/g,'\\r')+'"';if(typeof v=="number" || typeof v=="boolean")return String(v);var a=[],k;if(v instanceof Array){for(k=0;k<v.length;k++)a.push(enc(v[k]));return '['+a.join(',')+']';}for(k in v){if(typeof v[k]!='function')a.push(enc(k)+':'+enc(v[k]));}return '{'+a.join(',')+'}';}
var doc=fl.openDocument("file:///C:/Users/iuo/Documents/Codex/2026-10-25/session-de0692be-3404-49a1-9817-ca442769ee50/work/full-rework-r8/animate-source/%E5%85%89%E5%A4%B4%E4%BF%9D%E5%AE%89.xfl");var actions=["倒地恢复", "击飞", "匕首刺击", "持盾匕首刺击", "持盾点射与装填", "持盾站立", "持盾行走", "持盾被击", "死亡", "破盾", "站立", "行走", "被击", "被投", "跑步", "长枪点射与装填"];
function mat(m){return {a:m.a,b:m.b,c:m.c,d:m.d,tx:m.tx,ty:m.ty};}
function combine(p,q){return [p.a*q.a+p.c*q.b,p.b*q.a+p.d*q.b,p.a*q.c+p.c*q.d,p.b*q.c+p.d*q.d,p.a*q.tx+p.c*q.ty+p.tx,p.b*q.tx+p.d*q.ty+p.ty];}
function percent(e,k){var v=e[k];return typeof v=="number"?v:100;}
function amount(e,k){var v=e[k];return typeof v=="number"?v:0;}
var report={version:fl.version,source:doc.pathURI,actions:{}};
for(var ai=0;ai<actions.length;ai++){
 var name=actions[ai];doc.library.editItem("Codex2/特种兵/动作/"+name);
 var tl=doc.getTimeline(),count=tl.frameCount;
 for(var li=0;li<tl.layers.length;li++){
  tl.layers[li].locked=false;tl.setSelectedLayers(li,true);tl.convertToKeyframes(0,count);
 }
 var poses=[];
 for(var fi=0;fi<count;fi++){
  tl.currentFrame=fi;var pose=[];
  for(var li=0;li<tl.layers.length;li++){
   var layer=tl.layers[li], frame=layer.frames[fi];if(!frame)continue;
   var rig=layer.getRigMatrixAtFrame(fi);if(!rig)rig={a:1,b:0,c:0,d:1,tx:0,ty:0};
   for(var ei=0;ei<frame.elements.length;ei++){
    var e=frame.elements[ei];if(e.elementType!="instance" || !e.libraryItem)continue;
    var ref=e.libraryItem.name;if(ref.indexOf("Codex2/特种兵/分件/")!==0 && ref!="Codex2/特种兵/武器/可配置长枪")continue;
    pose.push({depth:tl.layers.length-li,part:ref,matrix:combine(rig,e.matrix),firstFrame:e.firstFrame,
     colorMult:[percent(e,"colorRedPercent"),percent(e,"colorGreenPercent"),percent(e,"colorBluePercent"),percent(e,"colorAlphaPercent")],
     colorAdd:[amount(e,"colorRedAmount"),amount(e,"colorGreenAmount"),amount(e,"colorBlueAmount"),amount(e,"colorAlphaAmount")]});
   }
  }
  poses.push(pose);
 }
 report.actions[name]={frameCount:count,poses:poses};FLfile.write("file:///C:/Users/iuo/Documents/Codex/2026-10-25/session-de0692be-3404-49a1-9817-ca442769ee50/work/full-rework-r8/native-motion-progress.txt",name+" "+count+" frames");
}
FLfile.write("file:///C:/Users/iuo/Documents/Codex/2026-10-25/session-de0692be-3404-49a1-9817-ca442769ee50/work/full-rework-r8/native-motion-samples.json",enc(report));FLfile.write("file:///C:/Users/iuo/Documents/Codex/2026-10-25/session-de0692be-3404-49a1-9817-ca442769ee50/work/full-rework-r8/native-motion-progress.txt","complete");
