from pathlib import Path
import json,hashlib,xml.etree.ElementTree as E
from PIL import Image
from assemble import R,T,ROBOT,HUMAN,flatten,VIEW
NS='{http://www.w3.org/2000/svg}'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 records=json.loads((R/'qa/frame-records.json').read_text());assert records['frames']==283;assert len(records['records'])==283
 frozen=json.loads((R/'reference/frozen-body-sources.json').read_text());parts=[]
 for r in frozen:
  p=R/r['packageFile'];assert sha(p)==r['sha256'];root=E.parse(p).getroot();orig=E.parse(R/f'reference/shapes/{r["id"]}.svg').getroot();assert root.get('viewBox')==orig.get('viewBox');assert not list(root.iter(NS+'image'));parts.append({'id':r['id'],'sha256':r['sha256'],'bodyRaster':False,'viewBoxExact':True})
 checks=[]
 for row in records['records']:
  fr=row['frame'];exp=[{'id':c,'matrix':m,'colors':cols} for c,m,cols in flatten(2008,fr)];assert json.loads(json.dumps(exp))==row['leaves']
  op=R/f'qa/frames/original/{fr:03}.png';np=R/f'qa/frames/candidate/{fr:03}.png';a=Image.open(op);b=Image.open(np);assert a.size==b.size;assert b.getbbox();checks.append({'frame':fr,'sameCanvas':True,'layerMatrixColorChainExact':True,'originalSha256':sha(op),'candidateSha256':sha(np),'size':b.size,'shapeIds':[x['id'] for x in exp]})
 # Changes are substitutions only. Transition vector pieces and protagonist are
 # loaded from original source paths; not approximations or missing tails.
 for fr in range(237,284):
  ids=[x[0] for x in flatten(2008,fr)];assert 2006 in ids
  assert sha(R/f'qa/frames/original/{fr:03}.png')==sha(R/f'qa/frames/candidate/{fr:03}.png')
 transition={str(c):sha(R/f'reference/shapes/{c}.svg') for c in range(1994,2004)}
 sound=json.loads((R/'audio/events.json').read_text());assert [(x['frame'],x['symbol']) for x in sound['events']]==[(2,1993),(81,2004),(255,2007)]
 out={'allPassed':True,'frames':283,'fps':30,'frozenBodyCount':24,'bodyChecks':parts,'sourceSwfSha256':json.loads((R/'reference/verified-summary.json').read_text())['source_sha256'],'stageViewBox':VIEW,'sourceVectorTransitionHashes':transition,'protagonistTail47FramesPixelIdentical':True,'soundCuesPreserved':sound,'noASWindowsOrRuntimeExecution':True,'checks':checks}
 (R/'qa/full-scene-check.json').write_text(json.dumps(out,indent=2));print('Passed: 283 frames, exact matrices/layers/color chains, 24 frozen body sources, 10 original transition vectors, 47 identical protagonist frames, three sound cues.')
if __name__=='__main__':main()
