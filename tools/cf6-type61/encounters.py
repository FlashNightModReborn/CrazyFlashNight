"""Apply reviewed Type61 soldier replacements to exact authored spawn positions."""
import copy
import json
from pathlib import Path

SOURCE = Path(__file__).with_name('encounters.source.json')
ROLES = {466:'ordinary',467:'ordinary',478:'elite',479:'elite',480:'instructor',481:'instructor'}


def positions(stage):
    for w,wave in enumerate(stage['stage']['Wave']['SubWave']):
        for i,enemy in enumerate(wave['EnemyGroup']['Enemy']):yield ('wave',w+1,i),enemy
    boss=stage.get('bossEncounter',{})
    for phase,part in [('boss',boss),('nextPhase',boss.get('nextPhase',{}))]:
        for g,group in enumerate(part.get('groups',[])):
            for i,enemy in enumerate(group['enemies']):yield (phase,g,i),enemy


def apply(stage, items):
    config=json.loads(SOURCE.read_text('utf-8'))
    if config['schema']!='cf6-type61-encounters.v1':
        raise ValueError('Unsupported encounter source')
    rows=config['maps'].get(stage['id'],[])
    slots=dict(positions(stage))
    seen=set()
    for row in rows:
        key=('wave',row['wave'],row['enemy']) if 'wave' in row else (row['phase'],row['group'],row['enemy'])
        if key in seen:raise ValueError('Duplicate encounter replacement')
        seen.add(key)
        enemy=slots[key]
        if (enemy['Type'],enemy['Quantity'])!=(row['expectedType'],row['expectedQuantity']):
            raise ValueError('Authored encounter changed: '+stage['id']+' '+str(key))
        unit=row['unit'];quantity=row['quantity']
        if unit not in ROLES or type(quantity)!=int or not 1<=quantity<=6:
            raise ValueError('Invalid soldier replacement')
        enemy['Type']='兵种'+str(unit);enemy['Quantity']=quantity
        params=enemy.setdefault('Parameters',{})
        params.update(copy.deepcopy(row['parameters']))
        # A shielded/non-shielded linkage owns its corresponding starting phase.
        params['特种兵初始阶段']=2 if unit%2==0 else 1
        role=ROLES[unit]
        if params.get('特种兵策略')!={'ordinary':'line','elite':'mobile','instructor':'adaptive'}[role]:
            raise ValueError('Soldier tactic does not match role')
        if role=='ordinary' and ('手枪' in params or '手枪2' in params):
            raise ValueError('Ordinary soldier cannot inherit elite sidearms')
        if role in ('elite','instructor') and not all(params.get(k) in items for k in ('手枪','手枪2')):
            raise ValueError('Both mobile sidearms must exist')
        if role in ('elite','instructor') and any(items[params[k]].findtext('use')!='手枪'
                or int(items[params[k]].findtext('data/level','999'))>enemy['Level'] for k in ('手枪','手枪2')):
            raise ValueError('Sidearm is incompatible with the soldier level or slot')
        if role in ('ordinary','instructor') and params.get('特种兵投掷物') not in items:
            raise ValueError('Missing authored throwable')
        if role=='elite' and params.get('特种兵投掷物') is not False:
            raise ValueError('Elite uses smoke rather than explosive grenades')
        if params.get('cf6EliteQuota'):
            if quantity!=1:raise ValueError('Finite loot carrier cannot multiply')
            params['称号']='军械教官' if role=='instructor' else '军械队长'
            weapons=[r['名字'] for r in params.get('掉落物',[]) if r['名字'] in items and items[r['名字']].findtext('use')=='长枪']
            if not weapons or params.get('长枪')!=weapons[0]:
                raise ValueError('Finite loot carrier must wield its reward weapon')
    military=[key for key,e in positions(stage) if e['Type'] in {'兵种'+str(n) for n in ROLES}]
    if set(military)!=seen:raise ValueError('Unreviewed soldier position in '+stage['id'])
