from __future__ import annotations
import argparse, hashlib, json, re, shutil, subprocess, sys, tempfile, xml.etree.ElementTree as ET, importlib.util
from collections import Counter
from pathlib import Path
from PIL import Image

NS={"x":"http://ns.adobe.com/xfl/2008/"}
BARE_AMP=re.compile(r"&(?!#\d+;|#x[0-9A-Fa-f]+;|[A-Za-z][A-Za-z0-9_.:-]*;)")
DIRECT_CALL=re.compile(r'配置装扮\(\s*this\s*,\s*(?:自机|_parent\._parent\._parent)\.([\w\u4e00-\u9fff]+)\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"',re.UNICODE)
ALIAS=re.compile(r'var\s+([\w\u4e00-\u9fff]+)\s*=\s*_parent\._parent\._parent\.([\w\u4e00-\u9fff]+)\s*;',re.UNICODE)
ALIAS_CALL=re.compile(r'配置装扮\(\s*this\s*,\s*([\w\u4e00-\u9fff]+)\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"',re.UNICODE)
VECTOR_SYMBOLS={"shape/Symbol 621":"effect-621","shape/Symbol 622":"effect-622","shape/Symbol 623":"wood-dummy-623","主角肢体素材/Symbol 3":"fragment-symbol-3"}
AUDITED_SWF_SHA256="1f2d0126c3c84b7f817bf1f6e9f40db4bfa69a1f57476f6ce8645a25d35b88f7"
AUDITED_FFDEC_SHA256="c03ad5d22008246b9f2523a70830502ed0d01610f4054912b43ae70f58dddd86"
AUDITED_XFL_SHAPES={
 "shape/Symbol 621":"0b8f0bbd054d599a28673b5f3a037d41996d4b665e34bc36019141c8dd9be299",
 "shape/Symbol 622":"f6de9d9c24a9d714f383dd9c870a556208bb7380225380a3a99da9ba45d9c375",
 "shape/Symbol 623":"05965f8278cc97211e8700bbc100fb6a575c3b486bbcddaad3646e713ea058cb",
}
FFDEC_SHAPES={
 "shape/Symbol 621":{"characterId":3209,"slug":"effect-621","size":[504,265],"alphaAtLeast128":81316,"fillColors":["#3F3F3F","#626262","#898989"]},
 "shape/Symbol 622":{"characterId":3210,"slug":"effect-622","size":[1277,392],"alphaAtLeast128":198147,"fillColors":["#3F3F3F","#626262","#898989"]},
 "shape/Symbol 623":{"characterId":3211,"slug":"wood-dummy-623","size":[340,841],"alphaAtLeast128":176692,"fillColors":["#848484","#AEAEAE","#CCCCCC"]},
}
def digest_bytes(data):return hashlib.sha256(data).hexdigest()
def digest_file(path):
 h=hashlib.sha256()
 with Path(path).open("rb") as f:
  for c in iter(lambda:f.read(1024*1024),b""):h.update(c)
 return h.hexdigest()
def parse_xml(path):
 text=Path(path).read_text(encoding="utf-8-sig")
 text=BARE_AMP.sub("&amp;",text)
 return ET.fromstring(text)
def local(tag):return tag.rsplit("}",1)[-1]
def fnum(value,default):
 try:return float(value) if value is not None else default
 except ValueError:return default
def line_num(path,needle):
 for i,line in enumerate(Path(path).read_text(encoding="utf-8-sig").splitlines(),1):
  if needle in line:return i
 return None
def frame_script_line(path,index,needle):
 current=False
 for line_no,line in enumerate(Path(path).read_text(encoding="utf-8-sig").splitlines(),1):
  match=re.search(r'<DOMFrame\b[^>]*\bindex="(\d+)"',line)
  if match:current=int(match.group(1))==index
  if current and needle in line:return line_no
 return None
def frame_script(frame):
 a=frame.find("./x:Actionscript",NS); s=a.find("./x:script",NS) if a is not None else None
 return (s.text or "").strip() if s is not None else ""
def parse_matrix(element):
 node=element.find("./x:matrix/x:Matrix",NS)
 raw=dict(node.attrib) if node is not None else {}
 values={k:fnum(raw.get(k),d) for k,d in (("a",1),("b",0),("c",0),("d",1),("tx",0),("ty",0))}
 return {"raw":raw,"values":[values[k] for k in ("a","b","c","d","tx","ty")],"explicit":node is not None}
def direct_elements(frame):
 wrapper=frame.find("./x:elements",NS)
 if wrapper is None:return []
 result=[]
 for order,e in enumerate(list(wrapper)):
  typ=local(e.tag)
  if typ not in {"DOMSymbolInstance","DOMBitmapInstance","DOMShape","DOMGroup","DOMRectangleObject","DOMOvalObject","DOMVideoInstance","DOMSoundInstance"}:continue
  filters=[]
  fx=e.find("./x:filters",NS)
  if fx is not None:
   for filt in list(fx):
    filters.append({"type":local(filt.tag),"attributes":dict(sorted(filt.attrib.items())),"empty":not filt.attrib and not len(filt)})
  result.append({"elementOrder":order,"type":typ,"libraryItemName":e.get("libraryItemName",""),"instanceName":e.get("name",""),"sourceVisible":e.get("visible")!="false","attributes":dict(sorted(e.attrib.items())),"matrix":parse_matrix(e),"filters":filters})
 return result
def build_components(library):
 entries={}
 for path in sorted((library/"主角肢体素材").glob("*.xml"),key=lambda p:p.name):
  root=parse_xml(path)
  inst=root.find("./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer/x:frames/x:DOMFrame/x:elements/x:DOMSymbolInstance",NS)
  if inst is None:continue
  script_el=inst.find("./x:Actionscript/x:script",NS);script=script_el.text or "" if script_el is not None else ""
  calls=[]
  for m in DIRECT_CALL.finditer(script):
   calls.append({"field":m.group(1),"attachName":m.group(2),"referenceName":m.group(3)})
  aliases={m.group(1):m.group(2) for m in ALIAS.finditer(script)}
  for m in ALIAS_CALL.finditer(script):
   if m.group(1) in aliases:calls.append({"field":aliases[m.group(1)],"attachName":m.group(2),"referenceName":m.group(3)})
  mat=inst.find("./x:matrix/x:Matrix",NS)
  wrapper={k:fnum(mat.get(k),d) if mat is not None else d for k,d in (("a",1),("b",0),("c",0),("d",1),("tx",0),("ty",0))}
  entries[path.stem]={"sourcePath":str(path),"sourceSha256":digest_file(path),"hostSymbol":inst.get("libraryItemName",""),"wrapperMatrix":wrapper,"fields":list(dict.fromkeys(x["field"] for x in calls)),"bindings":calls,"basicHiddenAtLoad":"this.基本款._visible = 0" in script or "this.基本款._visible = false" in script,"attachConditional":"!= undefined" in script or "!=undefined" in script}
 return entries
def validate_audited_sources(repo):
 swf=repo/"flashswf"/"arts"/"things0.swf";ffdec=repo/"tools"/"ffdec"/"ffdec-cli.exe"
 if digest_file(swf)!=AUDITED_SWF_SHA256:raise ValueError("things0.swf digest differs from audited FFDec mapping; stop for re-audit")
 if digest_file(ffdec)!=AUDITED_FFDEC_SHA256:raise ValueError("FFDec CLI digest differs from audited exporter; stop for re-audit")
 for symbol,expected in AUDITED_XFL_SHAPES.items():
  path=repo/"flashswf"/"arts"/"things0"/"LIBRARY"/(symbol+".xml")
  if digest_file(path)!=expected:raise ValueError("XFL shape digest differs from audited mapping: "+symbol)
 return swf,ffdec
def png_coverage(path):
 image=Image.open(path).convert("RGBA");alpha=image.getchannel("A")
 count=sum(alpha.histogram()[128:])
 return {"size":[image.width,image.height],"alphaAtLeast128":count}
def render_symbol_assets(repo,asset_dir):
 tool=repo/"tools"/"xfl-ui-svg"/"xfl_to_svg.py";library=repo/"flashswf"/"arts"/"things0"/"LIBRARY"
 swf,ffdec=validate_audited_sources(repo);swf_sha=digest_file(swf);ffdec_sha=digest_file(ffdec)
 sys.dont_write_bytecode=True
 spec=importlib.util.spec_from_file_location("cf7_gym_package_svg",tool);mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
 renderer=mod.Renderer(library,set());out={};symbols_dir=asset_dir/"symbols";symbols_dir.mkdir(parents=True,exist_ok=True)
 with tempfile.TemporaryDirectory(prefix=".gym-export-",dir=str(asset_dir)) as temp:
  root=Path(temp);svg_dir=root/"svg";png_dir=root/"png";svg_dir.mkdir();png_dir.mkdir()
  svg_cmd=[str(ffdec),"-selectid","3209-3211","-format","shape:svg","-zoom","4","-export","shape",str(svg_dir),str(swf)]
  png_cmd=[str(ffdec),"-selectid","3209-3211","-format","shape:png","-zoom","4","-export","shape",str(png_dir),str(swf)]
  subprocess.run(svg_cmd,check=True,capture_output=True,text=True,encoding="utf-8")
  subprocess.run(png_cmd,check=True,capture_output=True,text=True,encoding="utf-8")
  for symbol,record in FFDEC_SHAPES.items():
   cid=record["characterId"];slug=record["slug"]
   xfl=library/(symbol+".xml");source_sha=digest_file(xfl)
   if source_sha!=AUDITED_XFL_SHAPES[symbol]:raise ValueError("XFL shape digest changed during export: "+symbol)
   png=png_dir/(str(cid)+".png");svg=svg_dir/(str(cid)+".svg")
   if not png.is_file() or not svg.is_file():raise ValueError("FFDec omitted shape output for "+symbol)
   coverage=png_coverage(png)
   if coverage["size"]!=record["size"] or coverage["alphaAtLeast128"]!=record["alphaAtLeast128"]:
    raise ValueError("FFDec alpha coverage differs from audited raster baseline: "+symbol)
   target=symbols_dir/(slug+".svg");shutil.copyfile(svg,target)
   bbox=renderer.symbol_bbox(symbol,0)
   if not bbox:raise ValueError("No XFL local bounds for "+symbol)
   out[symbol]={
    "uri":"symbols/"+target.name,"sha256":digest_file(target),"repoRelativePath":xfl.relative_to(repo).as_posix(),"sourceSha256":source_sha,"bounds":bbox,
    "backend":"FFDec compiled SWF shape export","characterId":cid,
    "compiledSwf":{"repoRelativePath":swf.relative_to(repo).as_posix(),"sha256":swf_sha},
    "ffdecCli":{"repoRelativePath":ffdec.relative_to(repo).as_posix(),"sha256":ffdec_sha},
    "ffdecExportCommand":"ffdec-cli.exe -selectid 3209-3211 -format shape:svg -zoom 4 -export shape <scratch-output> flashswf/arts/things0.swf",
    "referencePngCoverage":coverage,"fillColors":record["fillColors"],
    "mappingEvidence":"XFL fill palette and local dimensions match this compiled DefineShape ID; Symbol 623 is also placed on the compiled 木人桩 frame. The SWF is a pinned compiled reference, not an editable source.",
   }
  symbol="主角肢体素材/Symbol 3";slug=VECTOR_SYMBOLS[symbol]
  symbol_out=root/"symbol-3";cmd=[sys.executable,str(tool),"--library",str(library),"--symbol",symbol,"--frame","0","--stage","1024x576","--out",str(symbol_out),"--portrait-symbols","","--button-ids",""]
  process=subprocess.run(cmd,check=True,capture_output=True,text=True,encoding="utf-8")
  bbox=renderer.symbol_bbox(symbol,0);source=symbol_out/"source.svg"
  if not bbox or not source.is_file():raise ValueError("Cannot export "+symbol)
  tree=ET.parse(source);svg_root=tree.getroot();svg_root.set("viewBox"," ".join(f"{x:.6f}" for x in (bbox[0],bbox[1],bbox[2]-bbox[0],bbox[3]-bbox[1])))
  svg_root.set("width",f"{bbox[2]-bbox[0]:.6f}");svg_root.set("height",f"{bbox[3]-bbox[1]:.6f}")
  target=symbols_dir/(slug+".svg");tree.write(target,encoding="utf-8",xml_declaration=True)
  exp=json.loads((symbol_out/"manifest.json").read_text(encoding="utf-8-sig"))
  out[symbol]={"uri":"symbols/"+target.name,"sha256":digest_file(target),"repoRelativePath":(library/(symbol+".xml")).relative_to(repo).as_posix(),"sourceSha256":digest_file(library/(symbol+".xml")),"bounds":bbox,"backend":"XFL source SVG export","rendererUnsupported":exp.get("unsupported",[]),"rendererSkipped":exp.get("skipped",[]),"motionCaveat":"Visible radial-gradient shadow; AS2 flight-time position changes are not executed by this offline renderer."}
 return out,digest_file(tool)

def extract_station_loop(root,layer_nodes,start,end):
 """Keep source keyframe exposure and element order for one labelled Flash loop."""
 layers=[];filters=Counter();tweens=[]
 for order,layer in enumerate(layer_nodes):
  keys=[]
  frames=sorted(layer.findall("./x:frames/x:DOMFrame",NS),key=lambda f:int(f.get("index","0")))
  for ix,frame in enumerate(frames):
   index=int(frame.get("index","0"))
   duration=max(1,int(frame.get("duration","1"))) if frame.get("duration") is not None else (max(1,int(frames[ix+1].get("index","0"))-index) if ix+1<len(frames) else 1)
   lo=max(start,index);hi=min(end,index+duration)
   if lo>=hi:continue
   elements=direct_elements(frame)
   for element in elements:
    for flt in element["filters"]:
     filters["emptyAdjustColorFilter" if flt["empty"] and flt["type"]=="AdjustColorFilter" else flt["type"]+"NonEmpty"]+=1
   if frame.get("tweenType"):tweens.append({"layerIndex":order,"keyframeIndex":index,"tweenType":frame.get("tweenType")})
   keys.append({"sourceIndex":index,"loopStart":lo-start,"loopEndExclusive":hi-start,"sourceDuration":duration,"label":frame.get("name",""),"tweenType":frame.get("tweenType",""),"elements":elements})
  layers.append({"index":order,"name":layer.get("name",""),"type":layer.get("layerType","normal"),"visible":layer.get("visible","true")!="false","keyframes":keys})
 controls=[{"timelineIndex":int(f.get("index","0")),"script":frame_script(f)} for f in root.findall(".//x:DOMFrame",NS) if frame_script(f) and start<=int(f.get("index","0"))<=end]
 return layers,controls,filters,tweens

def build(args):
 repo=args.repo.resolve();package=args.out.resolve();asset=package/"launcher"/"web"/"assets"/"gym"
 library=repo/"flashswf"/"arts"/"things0"/"LIBRARY"
 timeline=library/"sprite"/"Symbol 624.xml";document=repo/"flashswf"/"arts"/"things0"/"DOMDocument.xml";dressup=repo/"launcher"/"web"/"assets"/"dressup"/"manifest.json"
 for p in (timeline,document,dressup):
  if not p.is_file():raise FileNotFoundError(p)
 root=parse_xml(timeline);xfl_doc=parse_xml(document);fps=float(xfl_doc.get("frameRate","0"))
 if fps<=0:raise ValueError("Missing positive document frameRate")
 layer_nodes=root.findall("./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer",NS)
 labels=[(int(f.get("index","0")),f.get("name","")) for f in root.findall(".//x:DOMFrame",NS) if f.get("name")]
 starts=[i for i,n in labels if n=="木人桩"]
 if len(starts)!=1:raise ValueError("Expected one 木人桩 frame label")
 start=starts[0]
 goto_indices=[int(f.get("index","0")) for f in root.findall(".//x:DOMFrame",NS) if "gotoAndPlay" in frame_script(f) and "_parent" in frame_script(f)]
 ends=[i for i in goto_indices if i>start]
 if not ends:raise ValueError("No loopback goto after 木人桩 label")
 end=min(ends);frame_count=end-start
 layer_records=[];tweens=[];filter_counts=Counter()
 for order,layer in enumerate(layer_nodes):
  keys=[]
  frames=layer.findall("./x:frames/x:DOMFrame",NS);frames.sort(key=lambda x:int(x.get("index","0")))
  for ix,fr in enumerate(frames):
   index=int(fr.get("index","0"))
   if fr.get("duration") is not None:duration=max(1,int(fr.get("duration","1")))
   elif ix+1<len(frames):duration=max(1,int(frames[ix+1].get("index","0"))-index)
   else:duration=1
   lo=max(start,index);hi=min(end,index+duration)
   if lo>=hi:continue
   elements=direct_elements(fr)
   for el in elements:
    for flt in el["filters"]:
     if flt["empty"] and flt["type"]=="AdjustColorFilter":filter_counts["emptyAdjustColorFilter"]+=1
     else:filter_counts[flt["type"]+"NonEmpty"]+=1
   if fr.get("tweenType"):tweens.append({"layerIndex":order,"keyframeIndex":index,"tweenType":fr.get("tweenType")})
   keys.append({"sourceIndex":index,"loopStart":lo-start,"loopEndExclusive":hi-start,"sourceDuration":duration,"label":fr.get("name",""),"tweenType":fr.get("tweenType",""),"elements":elements})
  layer_records.append({"index":order,"name":layer.get("name",""),"type":layer.get("layerType","normal"),"visible":layer.get("visible","true")!="false","keyframes":keys})
 controls=[{"timelineIndex":int(f.get("index","0")),"script":frame_script(f)} for f in root.findall(".//x:DOMFrame",NS) if frame_script(f) and int(f.get("index","0"))>=start]
 components=build_components(library)
 vector_assets,tool_sha=render_symbol_assets(repo,asset)
 for binding in components.values():
  binding["repoRelativePath"]=Path(binding.pop("sourcePath")).resolve().relative_to(repo).as_posix()
 frame_data={"schema":"cf7-wood-dummy-motion-v1","source":{"repoRelativePath":"flashswf/arts/things0/LIBRARY/sprite/Symbol 624.xml","sha256":digest_file(timeline),"timelineIndices":[start,end-1],"flashFrames":[start+1,end],"frameCount":frame_count,"frameRate":fps,"registration":"source-local matrices preserved"},"layers":layer_records,"controlEvents":controls,"componentBindings":components,"vectors":vector_assets}
 asset.mkdir(parents=True,exist_ok=True);motion_path=asset/"wood-dummy-loop.json";motion_path.write_text(json.dumps(frame_data,ensure_ascii=False,separators=(",",":"))+"\n",encoding="utf-8")
 stations={"dummy":{"label":"木人桩","motionUri":"wood-dummy-loop.json","timelineStart":start,"timelineEndExclusive":end,"frameCount":frame_count,"frameRate":fps,"layerCount":len(layer_records),"keyframeExposureCount":sum(len(x["keyframes"]) for x in layer_records),"directInstanceKeyCount":sum(len(k["elements"]) for l in layer_records for k in l["keyframes"]),"loopbackFrameIndex":end}}
 for station_id,label,motion_uri in (("dumbbell","哑铃","dumbbell-loop.json"),("squat","深蹲","squat-loop.json")):
  station_starts=[i for i,n in labels if n==label]
  if len(station_starts)!=1:raise ValueError("Expected one "+label+" frame label")
  station_start=station_starts[0]
  station_ends=[i for i in goto_indices if i>station_start and i<start]
  if not station_ends:raise ValueError("No loopback after "+label+" label")
  station_end=min(station_ends)
  station_layers,station_controls,station_filters,station_tweens=extract_station_loop(root,layer_nodes,station_start,station_end)
  station_motion={"schema":"cf7-gym-station-motion-v1","stationId":station_id,"source":{"repoRelativePath":"flashswf/arts/things0/LIBRARY/sprite/Symbol 624.xml","sha256":digest_file(timeline),"timelineIndices":[station_start,station_end-1],"flashFrames":[station_start+1,station_end],"frameCount":station_end-station_start,"frameRate":fps,"registration":"source-local matrices preserved"},"layers":station_layers,"controlEvents":station_controls,"componentBindings":components,"vectors":vector_assets}
  (asset/motion_uri).write_text(json.dumps(station_motion,ensure_ascii=False,separators=(",",":"))+"\n",encoding="utf-8")
  stations[station_id]={"label":label,"motionUri":motion_uri,"timelineStart":station_start,"timelineEndExclusive":station_end,"frameCount":station_end-station_start,"frameRate":fps,"layerCount":len(station_layers),"keyframeExposureCount":sum(len(x["keyframes"]) for x in station_layers),"directInstanceKeyCount":sum(len(k["elements"]) for l in station_layers for k in l["keyframes"]),"loopbackFrameIndex":station_end,"labelSourceLine":line_num(timeline,'<DOMFrame index="'+str(station_start)+'" name="'+label+'"'),"loopbackSourceLine":frame_script_line(timeline,station_end,"gotoAndPlay"),"emptyAdjustColorFilterCount":station_filters["emptyAdjustColorFilter"],"otherSourceFilters":{k:v for k,v in station_filters.items() if k!="emptyAdjustColorFilter"},"tweenSegments":station_tweens}
 outputs={p.relative_to(asset).as_posix():digest_file(p) for p in sorted(asset.rglob("*")) if p.is_file() and p.name!="manifest.json"}
 swf,ffdec=validate_audited_sources(repo)
 equipment_sources={symbol:{"repoRelativePath":"flashswf/arts/things0/LIBRARY/"+symbol+".xml","sha256":digest_file(library/(symbol+".xml"))} for symbol in AUDITED_XFL_SHAPES}
 manifest={"schema":"cf7-gym-motion-manifest-v1","motionUri":"wood-dummy-loop.json","frameRate":fps,"loop":{"label":"木人桩","timelineStart":start,"timelineEndExclusive":end,"frameCount":frame_count,"loopbackFrameIndex":end,"frameRate":fps,"labelSourceLine":line_num(timeline,'<DOMFrame index="'+str(start)+'" name="木人桩"'),"durationSourceLine":line_num(timeline,'<DOMFrame index="'+str(start)+'" duration="'+str(frame_count)+'"'),"loopbackSourceLine":frame_script_line(timeline,end,"gotoAndPlay"),"boundaryPolicy":"Play source frame order; no synthetic seam frames."},"stations":stations,"sourceDigests":{"timeline":{"repoRelativePath":"flashswf/arts/things0/LIBRARY/sprite/Symbol 624.xml","sha256":digest_file(timeline)},"document":{"repoRelativePath":"flashswf/arts/things0/DOMDocument.xml","sha256":digest_file(document),"frameRate":fps,"frameRateLine":1},"dressupManifest":{"repoRelativePath":"launcher/web/assets/dressup/manifest.json","sha256":digest_file(dressup)},"xflSvgExporter":{"repoRelativePath":"tools/xfl-ui-svg/xfl_to_svg.py","sha256":tool_sha},"compiledSwf":{"repoRelativePath":swf.relative_to(repo).as_posix(),"sha256":digest_file(swf)},"ffdecCli":{"repoRelativePath":ffdec.relative_to(repo).as_posix(),"sha256":digest_file(ffdec)},"equipmentXflShapes":equipment_sources},"layerCount":len(layer_records),"keyframeExposureCount":sum(len(x["keyframes"]) for x in layer_records),"directInstanceKeyCount":sum(len(k["elements"]) for l in layer_records for k in l["keyframes"]),"emptyAdjustColorFilterCount":filter_counts["emptyAdjustColorFilter"],"otherSourceFilters":{k:v for k,v in filter_counts.items() if k!="emptyAdjustColorFilter"},"tweenSegments":tweens,"componentBindings":components,"vectors":vector_assets,"dressupManifestUri":"../dressup/manifest.json","readinessContract":{"api":"window.GymMotionRenderer.canRenderPortrait(portrait, stationId) -> boolean","rule":"Return true only after every required appearance field used by this station resolves to an existing, digest-valid image URI in the linked dressup manifest. This is tuple-specific; unknown or incomplete equipment returns false without fallback.","exactPreviewTupleReadiness":"Recorded separately in outfit-loop-preview.manifest.json","flashParityVerified":False,"shadowPositionParityVerified":False},"outputs":outputs}
 (asset/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
 return manifest
def line_num(p,needle):
 for i,line in enumerate(Path(p).read_text(encoding="utf-8-sig").splitlines(),1):
  if needle in line:return i
 return None
def main():
 p=argparse.ArgumentParser(description="Build compact offline gym animation assets from read-only XFL sources.")
 p.add_argument("--repo",type=Path,required=True)
 p.add_argument("--out",type=Path,default=Path(__file__).resolve().parents[1])
 a=p.parse_args();m=build(a)
 print(json.dumps({"ok":{sid:m["stations"][sid]["frameCount"] for sid in ("dummy","dumbbell","squat")}=={"dummy":127,"dumbbell":77,"squat":75},"assets":str((a.out/"launcher"/"web"/"assets"/"gym").resolve()),"frameRate":m["frameRate"],"stations":{sid:{"frames":entry["frameCount"],"exposures":entry["keyframeExposureCount"],"instances":entry["directInstanceKeyCount"]} for sid,entry in m["stations"].items()},"vectorBytes":sum((a.out/"launcher"/"web"/"assets"/"gym"/v["uri"]).stat().st_size for v in m["vectors"].values())},ensure_ascii=False,indent=2))
if __name__=="__main__":main()
