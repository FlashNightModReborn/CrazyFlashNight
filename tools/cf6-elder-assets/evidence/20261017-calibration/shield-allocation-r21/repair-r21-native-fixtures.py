from pathlib import Path
import hashlib,json,zipfile
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017'
load=lambda p:json.loads(p.read_text('utf-8-sig'))
sha=lambda data:hashlib.sha256(data).hexdigest()
for name in ['elder-asset','audio','player-aim','elder-render']:
    result=load(O/'native-r21-shield-allocation'/name/'result.json')
    assert result['bindingsUnchanged'] and result['exitCode']==(1 if name=='elder-asset' else 0)
assert sha((R/'scripts/TestLoader.as').read_bytes())=='e38e2151bf619814a0ea65bf2b19d11d8f78a7704787c47c046666acee2f090b'
path='scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderCombatEffectsTest.as'
before=(R/path).read_bytes();after=before
replacements=[('actor.shield.getStrength()==1000','near(actor.shield.getStrength(),1000)',1),
              ('actor.shield.getStrength()==12','near(actor.shield.getStrength(),12)',1),
              ('shield.getStrength()==75','near(shield.getStrength(),75)',2),
              ('layer.getStrength()==1000','near(layer.getStrength(),1000)',1)]
for old,new,count in replacements:
    a=old.encode('utf8');assert after.count(a)==count,(old,after.count(a));after=after.replace(a,new.encode('utf8'))
anchor='        var actor:MovieClip=samples.kicks.actor;'
replacement='''        var reference:Number=samples.kicks.actor.空手攻击力*samples.kicks.actor.elderTuning.shieldAttackScale;
        trace("[CF6_SHIELD_REFERENCE] attackDelta="+(reference-100)+" hardDelta="+(reference*10-1000)+" beamDelta="+(reference*0.75-75)+" softDelta="+(reference*0.12-12));
        var actor:MovieClip=samples.kicks.actor;'''
assert after.count(anchor.encode('utf8'))==1
after=after.replace(anchor.encode('utf8'),replacement.encode('utf8'))
assert before.startswith(b'\xef\xbb\xbf') and after.startswith(b'\xef\xbb\xbf')
with zipfile.ZipFile(O/'before-r21-native-fixture-repair.zip','x',zipfile.ZIP_DEFLATED)as z:z.writestr(path,before)
(R/path).write_bytes(after)
result={'productionSourceChanged':False,'resourceSwfChanged':False,
        'currentElderSwfSha256':sha((R/'flashswf/arts/new/Codex老头素材.swf').read_bytes()),
        'changes':[{'path':path,'beforeSha256':sha(before),'afterSha256':sha(after)}],
        'reason':'Five exact-equality expressions cover the nine failed checks. The new 55/43 inverse reference normalization has IEEE double residuals around 1e-13. Use the existing absolute 1e-5 near helper for computed strengths, keep actual exact-boundary leech/crumble behaviors and capacity arithmetic checks, and record native arithmetic deltas.',
        'nativeRerunCompleted':False}
with(O/'r21-native-fixture-repair.json').open('x',encoding='utf8')as f:json.dump(result,f,ensure_ascii=False,indent=2)
plan=load(O/'native-r21-shield-allocation-plan.json');plan['output']='native-r21-fixture-repair';plan['runs']=[plan['runs'][0]]
with(O/'native-r21-fixture-repair-plan.json').open('x',encoding='utf8')as f:json.dump(plan,f,ensure_ascii=False,indent=2)
print(json.dumps({'changedTestFiles':1,'productionSourceChanged':False,'nativeRerunCompleted':False}))
