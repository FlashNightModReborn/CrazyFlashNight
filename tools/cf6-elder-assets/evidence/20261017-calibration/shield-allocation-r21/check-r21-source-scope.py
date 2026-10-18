from pathlib import Path
import hashlib,json,zipfile
from lxml import etree as E
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017'
sha=lambda b:hashlib.sha256(b).hexdigest()
index=json.loads((O/'before-r21-shield-allocation-index.json').read_text('utf8'))
allowed={'tools/cf6-elder-assets/build.py','tools/cf6-elder-assets/ElderAI.as','tools/cf6-elder-assets/README.md',
         'tools/cf6-elder-assets/native-manifest.json','tools/cf6-elder-assets/balance-inputs.json',
         'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderAssetTest.as',
         'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderCombatEffectsTest.as',
         'data/enemy_properties/CF6重制敌人.xml','flashswf/arts/new/Codex老头素材.swf',
         'tools/cf6-audio/test-fixture-manifest.json','scripts/test-runners/cf6-audio/AudioFixture.as'}
changed=[];unchanged=[]
with zipfile.ZipFile(O/'before-r21-shield-allocation.zip')as z:
    before_manifest=json.loads(z.read('tools/cf6-elder-assets/native-manifest.json'))
    owner=before_manifest['owner'];graphic_paths={owner+'/'+row['path'] for row in before_manifest['outputs']+before_manifest['projectFiles']}
    def graphical(data):
        root=E.fromstring(data)
        for n in root.xpath('//*[local-name()="Actionscript"]'):n.getparent().remove(n)
        return E.tostring(root,method='c14n')
    graphics=[]
    for row in index:
        name=row['path'];data=(R/name).read_bytes();current=sha(data)
        assert sha(z.read(name))==row['sha256']
        if current==row['sha256']:unchanged.append(name);continue
        if name in graphic_paths:
            assert name.endswith('.xml') and graphical(data)==graphical(z.read(name)),name
            graphics.append(name)
        else:assert name in allowed,name
        changed.append({'path':name,'beforeSha256':row['sha256'],'afterSha256':current})
    for name in graphic_paths:
        old=z.read(name);new=(R/name).read_bytes()
        assert old==new or (name.endswith('.xml') and graphical(old)==graphical(new)),name
    for name in ['scripts/asLoader.swf','data/units/units.json','launcher/web/modules/arena-unit-catalog.js',
                 'tools/cf7-balance-tool/data/monster-flag-ledger.json']:
        assert (R/name).read_bytes()==z.read(name),name
for name in allowed:
    if name.endswith('.as'):assert (R/name).read_bytes().startswith(b'\xef\xbb\xbf'),name
report={'ok':True,'beforeFiles':len(index),'unchangedFiles':len(unchanged),'changed':changed,
        'graphicalFilesChecked':len(graphic_paths),'changedGraphics':0,'scriptOnlyGeneratedXml':graphics,
        'sharedLoaderRegistrationsCatalogLedgerByteUnchanged':True,
        'scopedDataImpact':'r21-scoped-data-impact.json',
        'boundary':'Byte identity for unchanged source and exact generated graphical XML after removing only Actionscript; no human visual acceptance or arena outcome is claimed.'}
with(O/'r21-source-scope-check.json').open('x',encoding='utf8')as f:json.dump(report,f,ensure_ascii=False,indent=2)
print(json.dumps({'ok':True,'changedFiles':len(changed),'unchangedFiles':len(unchanged),'graphicalFilesChecked':len(graphic_paths),'scriptOnlyGeneratedXml':graphics},ensure_ascii=False))
