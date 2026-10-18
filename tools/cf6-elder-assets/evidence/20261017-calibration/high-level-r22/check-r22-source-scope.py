from pathlib import Path
import hashlib,json,zipfile
from lxml import etree as E
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';sha=lambda b:hashlib.sha256(b).hexdigest()
index=json.loads((O/'before-r22-high-level-budget-index.json').read_text('utf8'))
allowed={'tools/cf6-elder-assets/ElderAI.as','tools/cf6-elder-assets/README.md','tools/cf6-elder-assets/arena-plan.js',
         'tools/cf6-elder-assets/analyze-arena.py','tools/cf6-elder-assets/native-manifest.json',
         'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderCombatEffectsTest.as',
         'flashswf/arts/new/Codex老头素材.swf','tools/cf6-audio/test-fixture-manifest.json','scripts/test-runners/cf6-audio/AudioFixture.as'}
changed=[];unchanged=[]
with zipfile.ZipFile(O/'before-r22-high-level-budget.zip')as z:
    m=json.loads(z.read('tools/cf6-elder-assets/native-manifest.json'))
    graphics={m['owner']+'/'+r['path']for r in m['outputs']+m['projectFiles']}
    def graph(data):
        node=E.fromstring(data)
        for child in node.xpath('//*[local-name()="Actionscript"]'):child.getparent().remove(child)
        return E.tostring(node,method='c14n')
    scripted=[]
    for row in index:
        name=row['path'];old=z.read(name);new=(R/name).read_bytes();assert sha(old)==row['sha256']
        if old==new:unchanged.append(name);continue
        if name in graphics:
            assert name.endswith('.xml') and graph(old)==graph(new),name
            scripted.append(name)
        else:assert name in allowed,name
        changed.append({'path':name,'beforeSha256':sha(old),'afterSha256':sha(new)})
    for name in graphics:
        old=z.read(name);new=(R/name).read_bytes()
        assert old==new or (name.endswith('.xml') and graph(old)==graph(new)),name
    fixed=['scripts/asLoader.swf','data/enemy_properties/CF6重制敌人.xml','data/units/units.json',
           'launcher/web/modules/arena-unit-catalog.js','tools/cf7-balance-tool/data/monster-flag-ledger.json',
           'tools/cf6-elder-assets/build.py','tools/cf6-elder-assets/balance-inputs.json',
           'tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts','.gitattributes']
    for name in fixed:assert z.read(name)==(R/name).read_bytes(),name
for name in allowed:
    if name.endswith('.as'):assert (R/name).read_bytes().startswith(b'\xef\xbb\xbf'),name
report={'ok':True,'beforeFiles':len(index),'changed':changed,'unchangedFiles':len(unchanged),
        'graphicalFilesChecked':len(graphics),'changedGraphics':0,'scriptOnlyGeneratedXml':scripted,
        'fixedInputsByteUnchanged':fixed,'acceptanceProfile':[60,80,100],
        'boundary':'Only periodic shield slope and its diagnostic changed in production behavior. New analysis/planner support is separately verified; no old arena execution is relabeled.'}
with(O/'r22-source-scope-check.json').open('x',encoding='utf8')as f:json.dump(report,f,ensure_ascii=False,indent=2)
print(json.dumps({'ok':True,'changedFiles':len(changed),'unchangedFiles':len(unchanged),'graphicalFilesChecked':len(graphics)},ensure_ascii=False))
