"""Close native-admission failures without changing global weapons or actor budgets."""
import copy
import hashlib
import json
import argparse
import xml.etree.ElementTree as ET
import fixed_roster as fixed

HERE = fixed.HERE
ADAPTATIONS = {
    'CF6-C-WA-R-02': ('Sniper', 'data_ice', '墨冰'),
    'CF6-N-WA-01': ('Sniper', 'data_fire', '狱火'),
    'CF6-C-CU-P-04': ('Sniper', 'data_ice', '墨冰'),
    'CF6-N-WA-06': ('SVD', 'data_ice', '墨冰'),
    'CF6-N-WA-07': ('SVD', 'data_fire', '狱火'),
}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    source=fixed.read_source();fire=fixed.firepower_source();items=fixed.item_catalog()
    config=ET.parse(fixed.ROOT/'data/equipment/equipment_config.xml')
    enhance={int(x.get('index')):float(x.text) for x in config.findall('.//LevelStatList/Level')}
    evidence=HERE/'firepower-local-adaptations.source.json'
    old=json.loads(evidence.read_text('utf-8')) if evidence.exists() else None
    if source.get('loadoutRevision'):
        # This is the immutable first migration. The later reviewed loadout stage
        # owns mods and numeric anchors; never regenerate history over that stage.
        if not args.check:raise ValueError('Already migrated; use apply-loadout-plan.py for the subsequent reviewed stage')
        for entry in old['changes']:
            row=next(r for r in source['roster'] if r['unitIdentity']==entry['identity'])
            if any(row['primary'].get(k)!=entry['after'].get(k) for k in ('name','form','tier','enhancement')):
                raise ValueError('Historical local weapon adaptation drift: '+entry['identity'])
        # The original producer hashes its LF JSON string before Windows text
        # output can translate newlines. Preserve that established hash contract.
        original_content=json.dumps(old,ensure_ascii=False,indent=2)+'\n'
        if hashlib.sha256(original_content.encode('utf-8')).hexdigest()!=fire['localAdaptationsSha256']:
            raise ValueError('Historical adaptation evidence drift')
        print(json.dumps(dict(changedSlots=5,check=True,subsequentStage=source['loadoutRevision']['version'])))
        return
    changes=[]
    for row in source['roster']:
        identity=row['unitIdentity']
        if identity not in ADAPTATIONS:continue
        name,form,tier=ADAPTATIONS[identity];before=copy.deepcopy(row['primary']);after=copy.deepcopy(before)
        after.update(name=name,form=form,tier=tier)
        after['serialized']='{}#{}#{}#{}'.format(name,after['enhancement'],tier,','.join(after['mods']))
        if before['name']!='NA45' and before!=after:
            raise ValueError('Local adaptation original weapon drift: '+identity)
        effective=fixed.effective_item(after,items)
        level=int(effective.findtext('data/level'))
        if not row['level']-7<=level<=row['level'] or after['mods']!=['透镜']:
            raise ValueError('Local precision replacement is not in the reviewed envelope')
        raw=float(effective.findtext('data/power'))*enhance[after['enhancement']]
        raw=int(raw+.5)
        entry=dict(identity=identity,slot='primary',before=before,after=after,
            finalRequiredLevel=level,actorLevel=row['level'],rawPower=raw,
            reason='NA45 native carrier plus explosion consumes 2 damage units against the unchanged 1-unit slot; child explosion lacks complete fixed-group propagation. Use an already scoped single-projectile precision form; preserve enhancement, mods, schedule and AI.',
            bonusPolicy='Retain the excluded strong-precision family: zero added growth, passive or Nano.')
        if old:
            original=next(x for x in old['changes'] if x['identity']==identity)
            entry['before']=original['before']
        changes.append(entry)
        row['primary']=after
        fire['profiles'][identity]['slots']['primary'].update(name=name,tier=tier,family='strong_sniper',skill=0,nano=0,
            weaponOnlyRaw=raw,expectedB=raw,expectedC=raw)
    source['admission']['forms']=[dict(name=n,form=f,tier=t) for n,f,t in sorted({
        (r[k]['name'],r[k]['form'],r[k]['tier']) for r in source['roster'] for k in ('primary','secondary1','secondary2') if r[k]
    },key=lambda x:(x[0],x[1]))]
    for entry in source['admission']['weapons']:
        if entry['name']=='NA45':
            entry.update(decision='C',reason='Not admitted for this fixed158 candidate: native two-stage damage exceeds the unchanged one-unit seat budget; global weapon data unchanged.')
    report=dict(schema='cf6-fixed158-local-adaptations.v1',proposalSha256=fire['proposalSha256'],
        evidence='first all-form native projectile run; original failures retained with delivery evidence',
        changedSlots=5,selectedForms=len(source['admission']['forms']),changes=changes)
    content=json.dumps(report,ensure_ascii=False,indent=2)+'\n'
    fire['localAdaptationsSha256']=hashlib.sha256(content.encode()).hexdigest()
    outputs={fixed.SOURCE:source,HERE/'soldier-firepower.source.json':fire,evidence:report}
    for path,value in outputs.items():
        data=json.dumps(value,ensure_ascii=False,indent=2)+'\n'
        if args.check:
            if not path.exists() or path.read_text('utf-8')!=data:raise ValueError('Local adaptation is stale: '+path.name)
        else:path.write_text(data,encoding='utf-8')
    print(json.dumps(dict(changedSlots=5,selectedForms=report['selectedForms'],check=args.check)))


if __name__=='__main__':main()
