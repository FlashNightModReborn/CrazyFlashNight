"""R9 narrow recolor: collar fittings echo the sleeve's #947664 warm-copper stripe."""
from assemble import *
import shutil
TARGETS={'M161.4 23.8L164 25.1L159.9 31.4L157.6 30.2Z':'url(#r9-collar-copper)','M161.4 25L162.6 25.6L159.8 29.8L158.8 29.5Z':'#b69d86','M176.1 23L177.9 22.4L180.9 28.7L179 29.8Z':'url(#r9-collar-copper)'}
def defs():
 d=el('defs');g=el('linearGradient',id='r9-collar-copper',x1='0%',y1='0%',x2='100%',y2='100%')
 for t,c in [(0,'#6f5547'),(.3,'#947664'),(.46,'#b49a82'),(.6,'#967860'),(1,'#6a5143')]:g.append(el('stop',offset=t,stop_color=c))
 d.append(g);return d
changed=[]
for folder in ['parts','variants']:
 for p in sorted((B/'reference/r8'/folder).glob('*.svg')):
  dst=B/folder/p.name;shutil.copyfile(p,dst);r=E.parse(p).getroot();hits=[]
  for e in r.iter():
   if e.tag.endswith('path') and e.get('d') in TARGETS:e.set('fill',TARGETS[e.get('d')]);hits.append(e.get('d'))
  if hits:
   assert len(hits)==3 and set(hits)==set(TARGETS),(p,hits)
   r.insert(0,defs());E.ElementTree(r).write(dst,encoding='unicode');changed.append(str(dst.relative_to(B)))
(B/'qa/r9-change-scope.json').write_text(json.dumps({'source_sleeve_accent':'parts/486.svg, r6-instructor-arm-panel second path fill #947664; NOT dark-red cloth background','edited_native_paths':TARGETS,'changed_files':changed},ensure_ascii=False,indent=2))
save('instructor-unshielded.svg','instructor');save('instructor-shielded.svg','instructor',562)
print('R9:',len(changed),'files with exact3 collar fills changed; all other outputs byte-copied R8')
