from evidence_utils import *
import re

out=ROOT/'tools/cf6-bladebot-assets/evidence/20261017-wave'
package=Package(out)
report,rows,identities=package.collect('matrix','blade-wave-matrix-20261017',TMP/'blade-wave-matrix',True)
pilot,pilot_rows,pilot_identities=package.collect('pilot','blade-wave-pilot-20261017',TMP/'blade-wave-pilot',True)
assert len(rows)==24 and len({(r['batchId'],r['runId']) for r in rows})==24
assert len(pilot_rows)==4
levels=[]
for rival in [347,286]:
    for level in [30,60,99]:
        subset=[r for r in rows if r['authorityContext']['rivalUnitId']==rival and r['authorityContext']['level']==level]
        assert len(subset)==4
        for side in ['blue','red']:
            assert {r['repeatIndex'] for r in subset if r['authorityContext']['candidateSide']==side}=={1,2}
        percentages=[]
        for r in subset:
            side=r['authorityContext']['candidateSide'];other='red' if side=='blue' else 'blue'
            assert r['status']=='finished' and not r['errors']
            assert (r['winner']==side)==(rival==347)
            percentages.append(100*r[side]['remainHp']/r[side]['startMaxHp'] if rival==347 else 100*(1-r[other]['remainHp']/r[other]['startMaxHp']))
        levels.append({'rivalUnitId':rival,'level':level,'games':4,'wins':4 if rival==347 else 0,
            'measure':'candidate_remaining_hp_percent' if rival==347 else 'opponent_net_hp_loss_percent',
            'minPercent':min(percentages),'maxPercent':max(percentages),
            'minFrames':min(r['frames'] for r in subset),'maxFrames':max(r['frames'] for r in subset)})

inputs=js(TMP/'blade-wave-matrix/input-identity.json')
for row in inputs['sourceBindings']:assert sha(ROOT/row['path'])==row['sha256'],'Source drift: '+row['path']
paths={r['path'] for r in inputs['sourceBindings']}
paths.update(r['path'] for r in js(ROOT/'tools/cf6-bladebot-assets/native-manifest.json')['buildInputs'])
for base in ['tools/cf6-bladebot-assets','flashswf/arts/new/Codex大刀机器人素材',
    'flashswf/arts/new/Codex素材源稿/CF6大刀机器人-R2','scripts/test-runners/cf6-bladebot',
    'scripts/test-runners/cf6-bladebot-beam-render','scripts/test-runners/cf6-knockback-scope']:
    for p in (ROOT/base).rglob('*'):
        if p.is_file() and 'evidence' not in p.parts and '__pycache__' not in p.parts:paths.add(p.relative_to(ROOT).as_posix())
paths.update(['scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6BladebotAssetTest.as',
    'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6BladebotBeamRenderTest.as',
    'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6KnockbackScopeTest.as',
    'scripts/run-cf6-bladebot-asset-tests.ps1','scripts/run-cf6-bladebot-beam-render-tests.ps1',
    'scripts/run-cf6-knockback-scope-tests.ps1','tools/cf7-balance-tool/data/monster-flag-ledger.json'])
package.freeze(paths)

image_rows=[]
for name in ['stand','death-start','cleave-impact','sweep-front','sweep-back','death-fragments','death-late','airborne-shadow','beam-right','beam-left']:
    capture='blade-beam-capture-r3' if name.startswith('beam-') else 'blade-capture-r1'
    source=TMP/(capture+'-images')/(name+'.png')
    package.copy(source,'native/images/'+name+'.png')
    image_rows.append({'name':name,'sourceTrace':'raw/'+capture+'-trace.txt','sha256':sha(source),
        'sourceSwfSha256':'470cbafeccb5482c527fec4089db53fed67a1a184d51be2ca25364983510b1a3'})
jput(out/'native/image-provenance.json',{'scope':'Ten final selected native Flash captures, reviewed individually; fixed scales retained.',
    'images':image_rows,'intermediateImages':'raw/: initial beam framing clipped rear legs; second framing included fixture text; all retained.',
    'humanAcceptance':False})

selected=[]
for p in TMP.iterdir():
    if p.name.startswith(('blade-','knockback-','enemy-knockback-','asLoader-')):
        if p.is_dir():
            if p.name not in ['blade-wave-matrix','blade-wave-pilot']:package.tree(p,'raw/'+p.name)
        else:package.copy(p,'raw/'+p.name)
for name in ['production-class-audit-r6.json','xml-roundtrip-r6.json','bom-r6.log',
    'wings-post-knockback-r2.log','wings-post-knockback-r2-trace.txt','wings-post-knockback-r2-errors.txt',
    'wings-post-knockback-r2-TestLoader.swf','wings-post-knockback-r2-stop.log']:
    package.copy(TMP/name,'raw/'+name)
package.tree(TMP/'wings-post-knockback-timeout','raw/wings-post-knockback-timeout')
package.copy(TMP/'wings-post-knockback.log','raw/wings-post-knockback.log')

combo=read(TMP/'blade-capture-r1-trace.txt').decode('utf-8-sig')
assert '409 passed, 0 failed; 28 actual timeline cases' in combo
assert re.search(r'case=0 .*dx=308 .*beams=1 beamHits=1 combo=1',combo)
assert re.search(r'case=1 .*dx=308 .*beams=1 beamHits=1 combo=1',combo)
assert re.search(r'case=2 .*dx=185 .*beams=0 beamHits=0 combo=0',combo)
jput(out/'summary.json',{'schema':'cf6-bladebot.wave-combo.v1','completedAt':report['completedAt'],
    'evidenceState':'candidate_executed','positioningMatrixVerified':True,'formalRuntimePromoted':False,'standardEntryVerified':False,
    'fixed':{'stage':8,'tier':9},'unitId':465,'games':24,'pilotGamesSeparate':4,'timeouts':0,
    'blackironWins':12,'arkclawWins':0,'levels':levels,'sourceBindings':inputs['sourceBindings'],
    'runtimeIdentities':identities,'sourceSwf':{'bytes':49625,'sha256':sha(ROOT/'flashswf/arts/new/Codex大刀机器人素材.swf')},
    'native':{'shapes':73,'sprites':20,'bitmaps':0,'symbols':113},
    'behavior':{'runId':'c16367352c024453a46dd83e47d83fef','passed':409,'failed':0,'timelineCases':28,
        'productionDamageImpactAndKnockbackFixtureCases':3,'comboDistance':308,'immuneTargetDistance':185},
    'beamRender':{'runId':'8e6daaa094c049f38516ba9b221a9d42','passed':68,'failed':0,'drawPoints':32},
    'sharedKnockbackRepair':{'source':'scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as',
        'change':'this.speed -= 减速度 -> this.speed -= this.减速度','sourceBytesPreservedExceptScopedOneLine':True,
        'beforeScopeTests':{'passed':2,'failed':5},'afterScopeTests':{'passed':7,'failed':0},
        'headbotRegression':'../../../cf6-headbot-assets/evidence/20261017-knockback/summary.json','wingsAssertions':389},
    'priorMeleeEvidence':'../20261016/combat-summary.json','limits':'Finite repeated 1v1 matches; contact counters are not cumulative damage. Human appearance, feel, standard entry and performance acceptance remain separate.'})
print(json.dumps({'levels':levels,**package.finish()},ensure_ascii=False))
