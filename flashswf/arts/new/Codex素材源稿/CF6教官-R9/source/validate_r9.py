from assemble import *
import hashlib
scope=json.loads((B/'qa/r9-change-scope.json').read_text());targets=set(scope['edited_native_paths'])
oldmaster=E.parse(B/'reference/r8/parts/487.svg').getroot();oldfills={e.get('d'):e.get('fill') for e in oldmaster.iter() if e.get('d') in targets}
report={'checks':[],'changed_files':[]}
for folder in ['parts','variants']:
 for p in sorted((B/folder).glob('*.svg')):
  o=E.parse(B/'reference/r8'/folder/p.name).getroot();r=E.parse(p).getroot();norm=deepcopy(r)
  for par in norm.iter():
   for c in list(par):
    if c.tag.endswith('defs') and len(c)==1 and c[0].get('id')=='r9-collar-copper':par.remove(c)
   if par.get('d') in targets:par.set('fill',oldfills[par.get('d')])
  ids=[e.get('id') for e in r.iter() if e.get('id')];refs=re.findall(r'url\(#([^\)]+)\)',p.read_text())
  hit=sum(e.get('d') in targets for e in r.iter());changed=p.read_bytes()!=(B/'reference/r8'/folder/p.name).read_bytes()
  rec={'file':str(p.relative_to(B)),'only_three_collar_fills_plus_gradient_changed':E.tostring(norm)==E.tostring(o),'target_path_count':hit,'unique_ids':len(ids)==len(set(ids)),'all_refs_resolved':not(set(refs)-set(ids)),'root_dimensions_preserved':all(r.get(k)==o.get(k) for k in ['viewBox','width','height'])}
  assert rec['only_three_collar_fills_plus_gradient_changed'] and rec['unique_ids'] and rec['all_refs_resolved'] and rec['root_dimensions_preserved'],rec
  if changed:assert hit==3;report['changed_files'].append(rec['file'])
  report['checks'].append(rec)
assert len(report['checks'])==43 and len(report['changed_files'])==27
assert len([x for x in report['changed_files'] if x.startswith('parts/')])==1
report['changed_mothers']=1;report['changed_body_atlas_variants']=26;report['byte_identical_other_outputs']=16
report['sha256']={str(p.relative_to(B)):hashlib.sha256(p.read_bytes()).hexdigest() for folder in ['parts','variants'] for p in sorted((B/folder).glob('*.svg'))}
report['timeline_sha256']=hashlib.sha256((B/'reference/timelines.json').read_bytes()).hexdigest()
(B/'qa/validation-r9.json').write_text(json.dumps(report,indent=2));print('43SVG pass;27 changed only3 fills+gradient;16 byte-identical')
