from pathlib import Path
import hashlib,json,zipfile
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017'
load=lambda p:json.loads(p.read_text('utf-8-sig'))
for suite in ['elder-asset','audio','player-aim','elder-render']:
    result=load(O/'native-r20-range-support'/suite/'result.json')
    assert result['bindingsUnchanged']
    if suite!='elder-asset':assert result['exitCode']==0,suite
changes={
 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderAssetTest.as':(
  'target.hp=1000;target._x=900;target._y=target.Z轴坐标=250;',
  'target.hp=1000;target._x=1100;target._y=target.Z轴坐标=250;'),
 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderCombatEffectsTest.as':(
  '        actor.shield.absorbDamage(100,false,1);',
  '        actor.shield.absorbDamage(25,false,1);'),
}
index=[]
with zipfile.ZipFile(O/'before-r20-native-fixture-repair.zip','x',zipfile.ZIP_DEFLATED)as z:
 for name,(old,new)in changes.items():
  b=(R/name).read_bytes();assert b.startswith(b'\xef\xbb\xbf')
  text=b.decode('utf-8-sig');assert text.count(old)==1,name
  z.writestr(name,b);index.append({'path':name,'beforeSha256':hashlib.sha256(b).hexdigest()})
for row in index:
 name=row['path'];old,new=changes[name];b=(R/name).read_bytes()
 b=b.replace(old.encode('utf8'),new.encode('utf8'));(R/name).write_bytes(b)
 row['afterSha256']=hashlib.sha256(b).hexdigest()
with(O/'r20-native-fixture-repair.json').open('x',encoding='utf8')as f:
 json.dump({'changes':index,'productionInputsChanged':False,'reason':'Keep the movement target outside the new 750 start range; make the shield-transition probe deplete the smaller hard layer while retaining soft capacity. Original failed assertions and all source snapshots are preserved.'},f,ensure_ascii=False,indent=2)
plan=load(O/'native-r20-range-support-plan.json');plan['output']='native-r20-fixture-repair';plan['runs']=[r for r in plan['runs']if r['name']=='elder-asset']
with(O/'native-r20-fixture-repair-plan.json').open('x',encoding='utf8')as f:json.dump(plan,f,ensure_ascii=False,indent=2)
print(json.dumps({'fixtureFilesChanged':len(index),'productionInputsChanged':False}))
