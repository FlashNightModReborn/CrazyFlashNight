"""Read-only source/identity gate. This does not execute AVM1 or certify pixels."""
from pathlib import Path
import ast
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
manifest=json.loads((HERE/'source-manifest.json').read_text(encoding='utf-8'))
for group in ('inputs','outputs'):
    for ref,row in manifest[group].items():
        data=(ROOT/ref).read_bytes()
        if len(data)!=row['bytes'] or hashlib.sha256(data).hexdigest()!=row['sha256']:
            raise ValueError('fixture source identity drift: '+ref)
for name in ('prepare.py','check-fixture.py'):
    ast.parse((HERE/name).read_text(encoding='utf-8'))
source=(HERE/'Cf6ItemVisualTest.as.txt').read_text(encoding='utf-8')
if manifest['expectedAssertions']!=54 or 'Tests Passed: 54' not in (HERE/'run-tests.ps1').read_text(encoding='utf-8'):
    raise ValueError('native frame-control assertion count or runner drift')
if 'cacheAsBitmap=false' in source or '.filters=[]' in source or '.filters = []' in source:
    raise ValueError('fixture must preserve original native filters and cache settings')
suite=ROOT/'scripts/类定义/org/flashNight/arki/scene/Cf6ItemVisualTest.as'
if suite.read_bytes()!=b'\xef\xbb\xbf'+source.encode('utf-8'):
    raise ValueError('installed suite lacks copied UTF-8 BOM or differs from its source')
for required in ['XMLParser.parseXMLNode','DressupReferenceManager.refreshAll',
                 'DressupReferenceManager.attach','hero.man.枪.枪','icon.gotoAndStop(1)',
                 'icon.gotoAndStop(2)','a.getPixel32(x,y)!==b.getPixel32(x,y)',
                 'pixels(blank)==0','hero.man.枪.枪.getBounds(world)','capture(world,sampleRegion)',
                 'actorDelta>20','mc.transform.matrix','stableDelta==0','restoreDelta==0',
                 'freezeTree(hero.man,0)','stage=="hidden" && age>=2','stage=="restored" && age>=2',
                 'phaseKey()==samplePhase','legs.length==2','if(age<2)return false;',
                 'legs[i]._currentframe','legs[i]._totalframes','tracePhase("stable")',
                 'tracePhase("hidden")','tracePhase("restored")','age>phaseLimit',
                 'sampleRegion.xMin<=skinRegion.xMin','sampleRegion.xMax>=skinRegion.xMax']:
    if required not in source:
        raise ValueError('missing non-vacuous native fixture path: '+required)
if len(manifest.get('nativeWalkingLegs',{}))!=2 or any(row['authoredFrames']!=22 for row in manifest['nativeWalkingLegs'].values()):
    raise ValueError('native walking-leg source/frame binding missing')
if 'SharedObject' in source or '_root.存档系统' in source:
    raise ValueError('presentation fixture acquired a persistence dependency')
n='{http://ns.adobe.com/xfl/2008/}'
host=ROOT/'tmp-cf6-item-visuals-host'
imports=[ET.parse(p).getroot() for p in (host/'LIBRARY').glob('*.xml')]
for link in ('枪-长枪-CAR','图标-CAR'):
    rows=[p for p in imports if p.get('linkageIdentifier')==link]
    if len(rows)!=1 or rows[0].get('linkageURL')!='flashswf/arts/new/3102&Leave.swf':
        raise ValueError('CAR fixture does not consume its original RSL: '+link)
doc=ET.parse(host/'DOMDocument.xml').getroot()
if '../scripts/TestLoader.as' not in doc.find('.//'+n+'script').text:
    raise ValueError('host bypasses the transactional focused scratch entry')
print('CF6 item visual source gates: identities/BOM/native XML/rack/pixel controls/original RSL OK; AVM1 pixels not run')
