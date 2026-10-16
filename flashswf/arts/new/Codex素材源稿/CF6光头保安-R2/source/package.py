from pathlib import Path
import zipfile,json,hashlib
R=Path(__file__).resolve().parents[1]
large={'live-actions.gif','knockdown-variants.gif'}
# Complete source plus compact visual QA; all omitted frame rasters are reproducible.
files=[]
for folder in ['source','reference','parts','death-parts','transition-parts','shared']:
 files +=[p for p in (R/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts]
files += [R/name for name in ['README.md','INTEGRATION.md','asset-manifest.json']]
files += [p for p in (R/'previews').glob('*') if p.suffix in ['.png','.gif'] and p.name not in large and p.name not in ['stand-original.png','stand-candidate.png','611-death-comparison.png','887-transform-comparison.png','stand-comparison.png','face-comparison.png','jacket-comparison.png']]
files += [p for p in (R/'qa').glob('*.json')]
files += [p for p in (R/'qa').glob('*.md')]
for p in [R/'qa/fragment-coverage/report.json',R/'qa/fragment-coverage/review-32x/report.json']:
 if p.exists():files.append(p)
files += [p for p in (R/'qa').glob('gif-*-samples.png')]
files += [p for p in (R/'qa/fragment-coverage').rglob('flagged-comparison-sheet.png')]
files=sorted(set(files));out=R.with_suffix('.zip')
with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for f in files:z.write(f,str(Path(R.name)/f.relative_to(R)))
with zipfile.ZipFile(out) as z:
 assert z.testzip() is None
 for f in files:assert z.read(str(Path(R.name)/f.relative_to(R)))==f.read_bytes()
res={'path':str(out),'bytes':out.stat().st_size,'under15MB':out.stat().st_size<15_000_000,'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'fileCount':len(files),'byteVerified':True,'separateAnimations':[{'path':str(R/'previews'/n),'bytes':(R/'previews'/n).stat().st_size,'sha256':hashlib.sha256((R/'previews'/n).read_bytes()).hexdigest()} for n in sorted(large)]}
(R/'package-result.json').write_text(json.dumps(res,indent=2));print(json.dumps(res,indent=2));assert res['under15MB']

# Independent review atlas, not a split/archive continuation. Source reconstruction
# never requires this optional picture-only companion.
review=R.with_name(R.name+'-visual-review').with_suffix('.zip')
pics=[p for p in (R/'previews').glob('*.png')]
pics += list((R/'previews/limbs').glob('comparison-*.png'))
pics += list((R/'previews/iterations').glob('*.png'))
pics += list((R/'qa').glob('gif-*-samples.png'))
pics += list((R/'qa/fragment-coverage').rglob('flagged-comparison-sheet.png'))
with zipfile.ZipFile(review,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for p in sorted(set(pics)):z.write(p,str(Path(R.name+'-visual-review')/p.relative_to(R)))
 z.writestr(R.name+'-visual-review/README.txt','CF6 bald guard R2 visual review companion. Each comparison uses equal source/R1/R2 scale. Includes all action and branch contacts, eight limb comparisons and decoded GIF samples. The independent source ZIP rebuilds these images; this is not a split archive. Static reconstruction only, not CS6 or gameplay acceptance. Clone uses historical approved SVG, not current native XFL.\n')
with zipfile.ZipFile(review) as z:assert z.testzip() is None
assert review.stat().st_size<15_000_000
res['visualReview']={'path':str(review),'bytes':review.stat().st_size,'sha256':hashlib.sha256(review.read_bytes()).hexdigest(),'under15MB':True}
(R/'package-result.json').write_text(json.dumps(res,indent=2));print('Visual review:',res['visualReview'])
