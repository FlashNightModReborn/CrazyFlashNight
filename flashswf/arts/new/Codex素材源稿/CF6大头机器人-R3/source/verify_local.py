"""R3 local scope: topology/matrices plus the single standing pose, not 183 frames."""
from pathlib import Path
import hashlib,json,xml.etree.ElementTree as E
import numpy as np
from PIL import Image
R=Path(__file__).resolve().parents[1];NS='http://www.w3.org/2000/svg';SM={s['id']:s for s in json.loads((R/'reference/shape-manifest.json').read_text())};NEW=list(range(928,933))+list(range(941,951))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
rows=[]
for sid in NEW:
 a=E.parse(R/f'reference/shapes/{sid}.svg').getroot();b=E.parse(R/f'parts/{sid}.svg').getroot();ids={n.get('id'):n for n in b.iter() if n.get('id')}
 assert not list(b.iter('{'+NS+'}image'));assert a.get('viewBox')==b.get('viewBox');fills=[]
 for f in SM[sid]['fills']:
  if f['type']!='bitmap':continue
  cid=f'c{sid}f{f["fillIndex"]}';newpath=ids[cid][0].get('d');same=newpath==f['path']
  if sid==929:
   assert not same;assert newpath.startswith('M-71.9,-167 C-69.1,-191.9');assert 'L11.9,-211.9 L11.9,-209.85' not in newpath
  else:assert same
  og=next(n for n in a if n.get('clip-path')==f'url(#{cid})');ng=next(n for n in b if n.get('clip-path')==f'url(#{cid})')
  oi=next(og.iter('{'+NS+'}image'));nu=next(ng.iter('{'+NS+'}use'));assert oi.get('transform')==nu.get('transform');assert nu.get('href')=='#vectorAtlas927'
  fills.append({'fillIndex':f['fillIndex'],'clipExact':same,'authorizedCrownException':sid==929,'bitmapMatrixExact':True})
 assert [E.tostring(n) for n in a if n.tag=='{'+NS+'}path']==[E.tostring(n) for n in b if n.tag=='{'+NS+'}path']
 rows.append({'shape':sid,'viewBoxExact':True,'nativeSolidAndLinePathsExact':True,'rasterImages':0,'fills':fills})
for sid in [926,939,940]:assert (R/f'parts/{sid}.svg').read_bytes()==(R/f'reference/shapes/{sid}.svg').read_bytes()
a=np.array(Image.open(R/'reference/r2-review/929.png').convert('RGBA'));b=np.array(Image.open(R/'parts/929.png').convert('RGBA'));assert a.shape==b.shape
mask=np.zeros(a.shape[:2],bool);mask[:225,:]=True;mask[350:503,108:268]=True;mask[350:485,411:]=True
diff=np.max(np.abs(a.astype(int)-b.astype(int)),2);assert not np.any(diff[~mask]>1)
# Intake work must not change exterior alpha; only the crown has the explicit exception.
ad=a[:,:,3]!=b[:,:,3];assert not ad[225:,:].any()
f=json.loads((R/'qa/frame-coverage.json').read_text());assert f['candidateFrames']==1 and f['originalFrames']==1
from assemble import flatten
assert f['records'][0]['leaves']==json.loads(json.dumps([{'id':c,'matrix':m,'colorTransforms':co} for c,m,co in flatten(933,1)]))
assert f['checks'][0]['clearOfCanvasEdge'];assert f['checks'][0]['alphaBox']
# The actual assembled body clip must be the locally repaired shape, not stale reference.
assembled=(R/'qa/frames/candidate/stand-walk-001.svg').read_text();assert 'M-71.9,-167 C-69.1,-191.9' in assembled
report={'revision':'R3 crown and intakes local candidate','runtimeGameValidation':False,'framesRendered':1,'sequence':933,'frame':1,'all183FrameRegressionRun':False,'fragmentFillRasterRegressionRun':False,'bodyAndFragmentStructureChecked':True,'partCount':18,'bitmapFillCount':sum(len(r['fills']) for r in rows),'allBitmapMatricesExact':True,'originalClipException':[929],'allOtherOriginalClipsExact':True,'retainedNativeIds':[926,939,940],'rgbChangedPixelsOutsideAuthorizedRegionsOverTolerance1':int((diff[~mask]>1).sum()),'alphaChangedPixelsBelowCrown':int(ad[225:].sum()),'crownChangedAlphaPixels':int(ad[:225].sum()),'crownAddedAlphaPixels':int(((b[:,:,3]>32)&(a[:,:,3]<=32)).sum()),'crownRemovedAlphaPixels':int(((a[:,:,3]>32)&(b[:,:,3]<=32)).sum()),'standMatricesAndColorChainsExact':True,'clearOfCanvasEdge':True,'checks':rows,'allLocalChecksPassed':True}
(R/'qa/local-check.json').write_text(json.dumps(report,indent=2));print(json.dumps({k:v for k,v in report.items() if k!='checks'},indent=2))
