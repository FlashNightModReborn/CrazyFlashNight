"""Project the shared redrawn atlas into every original death and morph crop.
Raw shared effects/weapons are byte-preserved. Existing approved clone SVGs
are coordinate-wrapped only; no clone geometry or palette is edited.
"""
from pathlib import Path
import json,xml.etree.ElementTree as E,re,shutil,hashlib
R=Path(__file__).resolve().parents[1];NS='http://www.w3.org/2000/svg';E.register_namespace('',NS)
S=json.loads((R/'reference/shape-manifest.json').read_text());core=json.loads((R/'source/atlas-art.json').read_text());atlas=''.join(v['body'] for v in core.values())
M={x['id']:x for x in json.loads((R/'reference/clone-stabilized/drawing-manifest.json').read_text())['parts']}
rows=[]
for s in S:
 cid=s['id']
 if str(cid) in core:rows.append({'id':cid,'class':'redrawn-live-body','file':f'parts/{cid}.svg'});continue
 if cid in M:
  source=R/f'reference/clone-stabilized/{cid}.svg';orig=E.parse(source).getroot();root=E.parse(R/f'reference/{cid}.svg').getroot();root.clear();spec=s['viewBox'];root.attrib.update({'viewBox':' '.join(map(str,spec)),'width':str(spec[2]*3),'height':str(spec[3]*3)})
  ox,oy=M[cid]['origin'];g=E.SubElement(root,'{'+NS+'}g',{'transform':f'translate({-ox},{-oy})'})
  for c in orig:g.append(c)
  dest=R/f'transition-parts/{cid}.svg';E.ElementTree(root).write(dest,encoding='unicode');rows.append({'id':cid,'class':'reused-approved-stabilized-clone-archive','file':str(dest.relative_to(R)),'archiveSha256':hashlib.sha256(source.read_bytes()).hexdigest(),'registrationTranslation':[-ox,-oy],'note':'Historical approved SVG archive; current native XFL has later joint/death edits not represented here.'});continue
 folder='death-parts' if 600<=cid<=610 else 'transition-parts' if 877<=cid<=886 else 'shared'
 (R/folder).mkdir(exist_ok=True);dest=R/folder/f'{cid}.svg';src=R/f'reference/{cid}.svg'
 if 581 not in s['bitmapDependencies']:
  shutil.copy2(src,dest);rows.append({'id':cid,'class':'original-weapon-preserved' if cid in [592,877] else 'original-blood-vector-preserved' if 600<=cid<=610 else 'original-shared-effect-or-helper-preserved','file':str(dest.relative_to(R))});continue
 assert s['bitmapDependencies']==[581],s
 root=E.parse(src).getroot();defs=E.Element('{'+NS+'}defs');gid=f'guardAtlas581_{cid}';g=E.fromstring(f'<g xmlns="{NS}" id="{gid}">{atlas}</g>')
 mapping={el.get('id'):f'a{cid}_'+el.get('id') for el in g.iter() if el.get('id') and el is not g}
 for el in g.iter():
  if el.get('id') in mapping:el.set('id',mapping[el.get('id')])
  for key,val in list(el.attrib.items()):
   for old,new in mapping.items():
    val=val.replace('url(#'+old+')','url(#'+new+')')
    if val=='#'+old:val='#'+new
   el.set(key,val)
 defs.append(g);root.insert(0,defs);n=0
 for par in list(root.iter()):
  for el in list(par):
   if el.tag.rsplit('}',1)[-1]=='image':
    pos=list(par).index(el);attrs={'href':'#'+gid}
    if el.get('transform'):attrs['transform']=el.get('transform')
    if el.get('id'):attrs['id']=el.get('id')
    use=E.Element('{'+NS+'}use',attrs);par.remove(el);par.insert(pos,use);n+=1
 E.ElementTree(root).write(dest,encoding='unicode');rows.append({'id':cid,'class':'redrawn-atlas-projected-original-crops','file':str(dest.relative_to(R)),'replacedBitmapFills':sum(f['type']=='bitmap' for f in s['fills']),'replacedEmbeddedBitmapDefinitions':n,'atlas':581})
(R/'qa/adaptation-build.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
print('Adapted',len(rows),'shape identities;',sum(x.get('replacedBitmapFills',0) for x in rows),'death/morph crop fills from redrawn atlas.')
