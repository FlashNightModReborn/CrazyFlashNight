"""Replace CF6 clone-beast drawing shapes with current native tyrant parts.
No placement, bone registration, matrix, color transform, depth, clip, or
ActionScript is changed. This is 13 articulated drawings, not a body snapshot.
CLI: python source/tyrant_culture.py --root . --native-library reference/tyrant-native/LIBRARY
"""
from pathlib import Path
import argparse, hashlib, json, shutil, subprocess
from render_native_reference import NativeRenderer
COMMIT='951145190cd45646abdfd4ebde1fbe68a4dd38ff'
PREFIX='Codex/γECHO克隆兽/完全体/分件/'
MAP={262:'上臂',263:'小腿',264:'膝部尖刺护片',265:'大腿',266:'躯干',267:'颈肩',268:'下颌',269:'头部',270:'前臂一',271:'前臂二',272:'正向爪手',273:'侧向爪手',274:'脚掌'}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def build(root,library=None):
 root=Path(root);library=Path(library or root/'reference/tyrant-native/LIBRARY').resolve()
 identity=json.loads((library.parent/'source-identity.json').read_text())
 assert identity['commit']==COMMIT, 'Native source commit mismatch'
 source_manifest=json.loads((library.parent/'native-manifest.json').read_text())
 variant=next(v for v in source_manifest['variants'] if v['variant']=='完全体')
 assert variant['displayName']=='暴君克隆兽'
 assert {v['id']:v['name'] for v in variant['parts']}=={k:PREFIX+v for k,v in MAP.items()}, 'Authoritative native manifest mapping mismatch'
 parts=root/'parts';parts.mkdir(parents=True,exist_ok=True);(root/'qa').mkdir(parents=True,exist_ok=True)
 records=[];sources=set();warnings=set()
 for cid,name in MAP.items():
  symbol=PREFIX+name;r=NativeRenderer(library);body=r.render_symbol(symbol,0,symbol)
  if r.unsupported:raise ValueError(json.dumps(r.unsupported,ensure_ascii=False))
  body='<defs>'+''.join(r.defs)+'</defs><g id="native-part">'+body+'</g>'
  # viewBox is presentation metadata only. Native geometry stays at (0,0).
  svg='<svg xmlns="http://www.w3.org/2000/svg" viewBox="-500 -500 1000 1000" width="1000" height="1000"><title>CF6 shape '+str(cid)+' native tyrant '+name+'</title><desc>Native source '+COMMIT+'; local registration unchanged; replaces drawing only.</desc>'+body+'</svg>'
  out=parts/f'shape-{cid}.svg';out.write_text(svg)
  # PATCHED(cf6-map-source): Inkscape 未安装；经 svgrender.query_bbox 工具发现
  # （Inkscape 优先，缺失时 Chrome getBBox 实测几何包围盒）。查询只决定 viewBox
  # 展示元数据（源注释：viewBox is presentation metadata only），不改几何/注册点
  try:
   from svgrender import query_bbox as _cf6_qb
  except ImportError:
   _cf6_qb=None
  vals=list(_cf6_qb(out,'native-part')[:4]) if _cf6_qb else [float(x) for x in subprocess.run(['inkscape',str(out),'--query-id=native-part','--query-x','--query-y','--query-width','--query-height'],capture_output=True,text=True,check=True).stdout.strip().splitlines()]
  x,y,w,h=vals;vb=[x-502,y-502,w+4,h+4]
  svg=svg.replace('viewBox="-500 -500 1000 1000" width="1000" height="1000"','viewBox="'+' '.join(format(v,'.15g') for v in vb)+'" width="'+format(vb[2],'.15g')+'" height="'+format(vb[3],'.15g')+'"')
  out.write_text(svg);sources.update(r.sources);warnings.update(r.warnings)
  records.append({'cf6ShapeId':cid,'nativeSymbol':symbol,'registration':[0,0],'adapterMatrix':[1,0,0,1,0,0],'viewBox':vb,'drawingSha256':sha(out),'nativeSources':[str(p.relative_to(library)) for p in sorted(r.sources)]})
 manifest={'sourceCommit':COMMIT,'map':records,'sourceCount':len(sources),'sources':[{'path':str(p.relative_to(library)),'sha256':sha(p)} for p in sorted(sources)],'authoritativeNativeManifestMappingVerified':True,'availableNativeClosureXmlCount':len(list(library.rglob('*.xml'))),'sourceType':'current repository native XFL XML, never archived donor SVG','registrationPolicy':'native local registration; no fitting or root 0.799987 scale; original CF6 1906 and 1939 rig untouched','timelinePolicy':'replace all 262–274 references in 1906 and every 1939 frame; 1933–1938 remain original glass fragments','warnings':sorted(warnings),'limitations':'SVG preview reproduces exported discrete frame states, not Flash Player execution or gameplay. No ActionScript, hitbox, collision or timing edited.'}
 (root/'qa/tyrant-culture-native-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
 return manifest
if __name__=='__main__':
 a=argparse.ArgumentParser();a.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);a.add_argument('--native-library',type=Path);args=a.parse_args();lib=args.native_library or args.root/'reference/tyrant-native/LIBRARY';m=build(args.root,lib);print(json.dumps({'parts':len(m['map']),'nativeSources':m['sourceCount'],'sourceCommit':COMMIT}))
