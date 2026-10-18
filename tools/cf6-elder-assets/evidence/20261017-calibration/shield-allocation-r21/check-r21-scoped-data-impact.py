from pathlib import Path
import hashlib, json, re, zipfile
import xml.etree.ElementTree as E

R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017'
shared='data/enemy_properties/CF6重制敌人.xml'
sha=lambda data:hashlib.sha256(data).hexdigest()
with zipfile.ZipFile(O/'before-r21-shield-allocation.zip') as z:
    before=z.read(shared)
    untouched={name:z.read(name) for name in ['data/units/units.json','tools/cf7-balance-tool/data/monster-flag-ledger.json']}
after=(R/shared).read_bytes();old=E.fromstring(before);new=E.fromstring(after)
assert [n.tag for n in old]==[n.tag for n in new]
changed=[a.tag for a,b in zip(old,new) if E.tostring(a)!=E.tostring(b)]
assert changed==['敌人-CF6老头机器人'],changed
a=old.find(changed[0]);b=new.find(changed[0]);assert [n.tag for n in a]==[n.tag for n in b]
fields=[x.tag for x,y in zip(a,b) if E.tostring(x)!=E.tostring(y)]
assert set(fields)=={'空手攻击力_min','空手攻击力_max','标识'},fields
flags=[x.tag for x,y in zip(a.find('标识'),b.find('标识')) if E.tostring(x)!=E.tostring(y)]
assert flags==['攻击倍率'],flags
assert b.findtext('空手攻击力_min')=='442' and b.findtext('空手攻击力_max')=='1172'
assert b.findtext('标识/攻击倍率')=='6.875'
def unrelated(data):
    text=data.decode('utf-8-sig').replace('\r\n','\n')
    text,count=re.subn(r'<敌人-CF6老头机器人>.*?</敌人-CF6老头机器人>','',text,flags=re.S)
    assert count==1
    return text.encode('utf8')
assert unrelated(before)==unrelated(after)
for name,data in untouched.items():assert data==(R/name).read_bytes(),name
levels=[]
for level in [30,60,99]:
    old_atk=int(float(a.findtext('空手攻击力_min'))+(float(a.findtext('空手攻击力_max'))-float(a.findtext('空手攻击力_min')))/59*level)
    new_atk=int(442+(1172-442)/59*level)
    old_hard=old_atk*35/43;new_hard=new_atk*55/43
    assert abs(new_hard/old_hard-1)<.014
    levels.append({'level':level,'oldAttack':old_atk,'newAttack':new_atk,'waveRawRatio':new_atk/old_atk,
                   'slamRawRatio':new_atk*18/(old_atk*8),'shieldHardnessRatio':new_hard/old_hard})
report={'qualified':True,'originalArchive':'before-r21-shield-allocation.zip','path':shared,
        'beforeSha256':sha(before),'afterSha256':sha(after),'onlyChangedEnemyNodes':changed,
        'onlyChangedRobotFields':fields,'onlyChangedFlags':flags,'levels':levels,
        'humanHeadAndAllOtherEnemyNodesUnchanged':True,'registrationsAndLedgerByteUnchanged':True,
        'boundary':'Exact source impact and canonical formula outputs; no arena outcome or current Head execution is claimed.'}
with(O/'r21-scoped-data-impact.json').open('x',encoding='utf8')as f:json.dump(report,f,ensure_ascii=False,indent=2)
print(json.dumps(report,ensure_ascii=False))
