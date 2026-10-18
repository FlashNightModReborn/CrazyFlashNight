from pathlib import Path
import json,hashlib
TMP=Path(__file__).resolve().parent
rows=[]
for actor,count in [('headbot',20),('elder',25),('bladebot',2)]:
    folder=TMP/'final-images'/actor/'images'
    data=json.loads((folder/'provenance.json').read_text('utf8'))
    assert len(data['images'])==count
    assert {p.name for p in folder.glob('*.png')}=={r['image'] for r in data['images']}
    for row in data['images']:
        assert hashlib.sha256((folder/row['image']).read_bytes()).hexdigest()==row['sha256']
    rows.append({'actor':actor,'imageCount':count,'resource':data['resource'],'resourceSha256':data['resourceSha256'],'images':data['images']})
probe=json.loads((TMP/'beam-pixel-probe.json').read_text('utf8'))
for row in probe['nativeCrossSections']:
    assert hashlib.sha256((TMP/'final-images/elder/images'/(row['name']+'.png')).read_bytes()).hexdigest()==row['sha256']
result={'reviewer':'assistant','reviewedNativeImages':47,'humanAcceptanceState':'pending','actors':rows,
 'observations':['Headbot charge grows before either cyan beam; both corrected second-beam frames fit the capture. Late death frames contain separated falling or resting native parts.',
  'Elder primer and heavy beam share the emitter center; heavy charge, threefold authored thickness, recovery pose, mirror, transition and final wreckage are present.',
  'Bladebot native beam and full unit are visible in both directions without capture clipping. These images use a neutral beam angle; actual player aim and visual/collision rotation are checked by the separate 334-assertion suite.'],
 'limitations':['Static native keyframes do not establish animation feel, live input, full combat balance or standard-entry acceptance.',
  'The render fixture does not perform the final map blit and retains its configured ground shadow; production death delegation, once-only layer-2 stamp request and cleanup are checked separately by the behavior fixtures.',
  'Headbot images retain per-frame provenance across the initial capture and the successful two-frame framing repair. The failed full sweep is not upgraded.'],
 'previewPolicy':'Review sheets and the handoff comparison only compose native RGBA on a declared background and label/crop/scale the preview; source PNGs remain unchanged.'}
(TMP/'image-review.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n','utf8')
print('Recorded review and provenance verification for 47 native images')
