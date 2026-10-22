#!/usr/bin/env python3
"""Source-bounded Andy template. Generates a fragment, never installs chapter data or writes saves."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
NPC_SKILL_SOURCE = ROOT / 'scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as'
SLOT_MAP = [('head','头部装备'),('body','上装装备'),('leg','下装装备'),('hand','手部装备'),
            ('foot','脚部装备'),('neck','颈部装备'),('primary','长枪'),('secondary','手枪'),('secondary2','手枪2'),('melee','刀')]

def sha(data):
    return hashlib.sha256(data).hexdigest()

def clean_as2(text):
    return re.sub(r'//[^\n]*', '', re.sub(r'/\*.*?\*/', '', text, flags=re.S))

def npc_selection(text, name, level, has_blade, has_gun):
    """Finite source model of the current equipment-bucket/LCG membership selection.

    Desired player levels come independently from skills.xml. This model does not
    claim execution of AVM1 or copy the NPC's material/MP privileges.
    """
    source = clean_as2(text)
    pool = []
    for match in re.finditer(r'人形怪技能表\.push\(\{(.*?)\}\);', source):
        body = match[1]
        pool.append(dict(name=re.search(r'技能名:\s*"([^"]+)"', body)[1],
                         cost=int(re.search(r'点数:\s*(\d+)', body)[1]),
                         unlock=int(re.search(r'限制:\s*(\d+)', body)[1]),
                         kind=re.search(r'类型:\s*"([^"]+)"', body)[1]))
    if not pool: raise ValueError('NPC active skill pool could not be extracted')
    tiers = [int(n.strip()) for n in re.search(r'var 技能点数分界表:Array = \[([^\]]+)\]',source)[1].split(',')]
    tier = min(level//10,len(tiers)-1)
    budget = tiers[tier]
    if tier < len(tiers)-1: budget += level%10*(tiers[tier+1]-tiers[tier])//10
    elif level > 70: budget += (level-70)*100
    eligible = [i for i,entry in enumerate(pool) if entry['unlock'] <= level
                and (entry['kind'] != '刀技' or has_blade) and (entry['kind'] != '火器' or has_gun)]
    # AS2 builds buckets by ascending level, then source insertion order within each level.
    eligible.sort(key=lambda index:(pool[index]['unlock'],index))
    constants = {key:int(re.search(r'var LCG_'+key+r':Number = (\d+);',source)[1]) for key in ('A','C','M')}
    seed = level + sum(ord(c) for c in name)
    limit = 3+level//5
    selected = []
    initial_budget = budget
    while limit > 0 and eligible:
        seed = (constants['A']*seed+constants['C'])%constants['M']
        index = seed*len(eligible)//constants['M']
        candidate = eligible[index]
        eligible[index] = eligible[-1]
        eligible.pop()
        entry = pool[candidate]
        if budget >= entry['cost']:
            selected.append(entry['name'])
            budget -= entry['cost']
            limit -= 1
    # At this input even the full source pool's initial costs fit. Nonnegative
    # personality technology changes subsequent skill levels, not membership.
    return selected, dict(baseBudget=initial_budget,selectedBaseCost=initial_budget-budget,
                         allEligibleBaseCost=sum(entry['cost'] for entry in pool if entry['unlock'] <= level),
                         lcg=constants,selectionCount=3+level//5,
                         sourceModelOnly=True,actualAvm1Executed=False)

def build(root=ROOT, selection=None):
    selection = selection or json.loads((HERE/'selection.json').read_text('utf-8'))
    sources = set()
    def source(rel):
        path = root/rel
        sources.add(path)
        return path
    units = json.loads(source('data/units/units.json').read_text('utf-8-sig'))
    npc = next(unit for unit in units if unit['id']==selection['npcUnitId'])
    mirror = next(unit for unit in units if unit['id']==selection['hostileMirrorId'])
    if npc['name']!=selection['name'] or npc['level']!=selection['level'] or npc['NPC'] is not True:
        raise ValueError('selected production NPC identity drifted')
    if mirror['name']!=npc['name'] or mirror['data']!=npc['data']:
        raise ValueError('hostile Andy mirror no longer shares the source loadout')
    text = source('scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as').read_text('utf-8-sig')
    algorithm = text[text.index('_root.主角函数.初始化可用技能 = function() {'):
                     text.index('_root.主角函数.行走_玩家 = function() {')]
    if sha(algorithm.encode())!=selection['npcSkillAlgorithmSha256']:
        raise ValueError('NPC skill algorithm drift; review AS2 before updating the pinned selection contract')
    catalog_path=source('data/items/list.xml')
    items, item_paths, ambiguous_items = {}, {}, set()
    for row in ET.parse(catalog_path).findall('items'):
        path=root/'data/items'/row.text
        for item in ET.parse(path).findall('.//item'):
            name=item.findtext('name')
            if name in items and ET.tostring(items[name]) != ET.tostring(item): ambiguous_items.add(name)
            items[name],item_paths[name]=item,path
    skills_path=source('data/skills/skills.xml')
    skills={skill.findtext('Name'):skill for skill in ET.parse(skills_path).findall('Skill')}
    teaching=json.loads(source('data/skills/npc_skills.json').read_text('utf-8-sig'))[selection['teacherKey']]
    teacher=[teaching[key] for key in sorted(teaching,key=int)]
    generated, model = npc_selection(text,npc['name'],npc['level'],bool(npc['data']['melee']),
        any(npc['data'][key] for key in ('primary','secondary','secondary2')))
    extras=[name for name in generated if name not in teacher]
    if extras!=selection['expectedAdditionalSkills']:
        raise ValueError('NPC additional skill membership changed')
    selected=list(dict.fromkeys(teacher+generated))
    grants=[];skill_audit=[]
    for name in selected:
        meta=skills[name]
        maximum=int(meta.findtext('MaxLevel','0'))
        if maximum<1 or not meta.findtext('Type') or name=='驾驶': raise ValueError('unsupported player skill '+name)
        grants.append(dict(name=name,level=maximum))
        skill_audit.append(dict(name=name,level=maximum,type=meta.findtext('Type'),
            source=('teacher_and_npc' if name in teacher and name in generated else 'teacher' if name in teacher else 'npc'),
            spEquivalent=int(meta.findtext('UnlockSP'))+(maximum-1)*int(meta.findtext('UpgradeSP'))))
    if len(grants)!=selection['expectedSkillCount'] or sum(row['spEquivalent'] for row in skill_audit)!=selection['expectedSpEquivalent']:
        raise ValueError('fixed union count/SP-equivalence drift')
    growth_source=source('scripts/引擎/引擎_lsy_等级与经验值.as').read_text('utf-8-sig')
    if 'Math.floor(13 * 等级 * 等级 * 等级 * 等级 + 500)' not in growth_source:
        raise ValueError('cumulative experience formula drift; review the source curve')
    level=npc['level'];enhancement=selection['enhancement'];equipment=[];equipment_audit=[];omitted=[]
    tiers=ET.parse(source('data/equipment/equipment_config.xml')).findall('EquipmentConfig/LevelStatList/Level')
    if enhancement not in {int(row.get('index')) for row in tiers}: raise ValueError('enhancement is not supported')
    for key,slot in SLOT_MAP:
        original=npc['data'][key]
        name=selection['meleeOverride'] if key=='melee' else selection['primaryOverride'] if key=='primary' else original
        if not name: continue
        if name in ambiguous_items: raise ValueError('selected equipment has ambiguous registered definitions: '+name)
        meta=items[name];sources.add(item_paths[name])
        expected_use='手枪' if slot=='手枪2' else slot
        if meta.findtext('use')!=expected_use: raise ValueError('equipment slot mismatch: '+name)
        requirement=int(meta.findtext('data/level','0'))
        info=dict(slot=slot,name=name,npcOriginal=original,requiredLevel=requirement,
            source=item_paths[name].relative_to(root).as_posix(),icon=meta.findtext('icon'),
            dressup=meta.findtext('data/dressup',''),helmet=meta.findtext('helmet')=='true',
            ammo=meta.findtext('data/clipname'),lifecycle=ET.tostring(meta.find('lifecycle'),encoding='unicode') if meta.find('lifecycle') is not None else None)
        if requirement>level:
            if key not in ('primary','secondary','secondary2') or selection['omitNpcWeaponsAbovePlayerLevel'] is not True:
                raise ValueError('unusable mandatory initial equipment '+name)
            omitted.append(dict(**info,reason='NPC weapon exceeds player level; no substitution inferred'))
            continue
        equipment.append(dict(slot=slot,name=name,enhancement=enhancement));equipment_audit.append(info)
    npc_primary=items[npc['data']['primary']];sources.add(item_paths[npc['data']['primary']])
    # Null hairstyle is normalized explicitly; the source head's helmet rule also hides it.
    actor=dict(name=npc['name'],gender=npc['data']['gender'],height=npc['height'],face=npc['data']['face'],
        hair=npc['data']['hairstyle'] or '',level=level,experience=13*(level-1)**4+500,
        equipment=equipment,skills=grants)
    references={entry.get('id'):dict(entry.attrib) for entry in ET.parse(source('data/items/asset_source_map.xml')).findall('asset')}
    for entry in equipment_audit:
        entry['iconSource']=references.get('图标-'+str(entry['icon']))
        entry['dressupSource']=references.get(entry['dressup'])
    gun=items[selection['primaryOverride']]
    ammo=[]
    for kind,ammo_name in [('primary',gun.findtext('data/clipname')),('subweapon',gun.findtext('subweapon/reserveName'))]:
        if not ammo_name or ammo_name not in items or items[ammo_name].findtext('use')!='弹夹':
            raise ValueError('gun references an unknown ammunition item')
        sources.add(item_paths[ammo_name])
        ammo.append(dict(kind=kind,name=ammo_name,source=item_paths[ammo_name].relative_to(root).as_posix(),
                         count=None,quantityAuthority='chapter economy'))
    supplies=dict(schema='cf6-initial-gun-supply.v1',weapon=selection['primaryOverride'],enhancement=enhancement,
        alreadyEquippedByActor=True,grantAdditionalFreeCopy=False,ammo=ammo,
        authoredSubweapon={entry.tag:entry.text for entry in gun.find('subweapon')},
        note='Subweapon fields are source facts, not an additional ammunition grant or runtime test result.')
    source('scripts/逻辑系统分区/兵种系统_兼容.as')
    source('scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/DressupInitializer.as')
    source('scripts/逻辑/装备函数/镜之虎彻.as')
    source('scripts/逻辑/单位函数/单位函数_lsy_主角技能.as')
    source('scripts/引擎/引擎_lsy_等级与经验值.as')
    audit=dict(schema='cf6-actor-source-audit.v1',status='source_verified_pending_runtime',
        npcUnitId=npc['id'],hostileMirrorId=mirror['id'],teacherKey=selection['teacherKey'],
        sampling=dict(name=npc['name'],level=level,hasBlade=True,hasGun=True,explicitSkillOverride=False,
            note='Fixed skill membership is sampled from the source NPC equipment, independently of the player starting gun choice.'),
        model=model,teacherCount=len(teacher),npcSelected=generated,additionalSkills=extras,skillCount=len(grants),
        teacherSpEquivalent=sum(row['spEquivalent'] for row in skill_audit if row['name'] in teacher),
        totalSpEquivalent=sum(row['spEquivalent'] for row in skill_audit),
        spIsSpendableGrant=False,skills=skill_audit,equipment=equipment_audit,omittedEquipment=omitted,
        firstPrototypeGun=dict(name=selection['primaryOverride'],role=selection['primaryOverrideRole'],
            deliveryPolicy=selection['initialGunDeliveryPolicy'],ammo=items[selection['primaryOverride']].findtext('data/clipname')),
        originalNpcGun=dict(name=npc['data']['primary'],requiredLevel=int(npc_primary.findtext('data/level')),
            source=item_paths[npc['data']['primary']].relative_to(root).as_posix(),inherited=False),
        unresolved=['Starting ammunition quantity belongs to chapter economy; no additional free gun accompanies the same initial allocation.',
            'Several NPC equipment icons have no asset-source-map entry; actual fallback presentation has not been verified.'],
        conditions=['Andy head has helmet=true; renderer clears hairstyle.',
            'Mirror katana keeps its authored skill multipliers and MP-consuming lifecycle; no passive attributes are rewritten.',
            'Player energy shield still consumes one energy battery; NPC exemption is not copied.',
            'Active skill shortcuts are not invented. Fixed skills enter the regular player skill table.'],
        sourceFiles=[dict(path=path.relative_to(root).as_posix(),sha256=sha(path.read_bytes())) for path in sorted(sources)])
    return {'actor.fragment.json':{'actor':actor},'initial-supply-requirements.json':supplies,'source-audit.json':audit}

def main():
    parser=argparse.ArgumentParser(__doc__);parser.add_argument('--check',action='store_true');args=parser.parse_args()
    for name,data in build().items():
        content=(json.dumps(data,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
        path=HERE/name
        if args.check:
            if not path.is_file() or path.read_bytes()!=content: raise ValueError(name+' is stale')
        else:path.write_bytes(content)
    print('CF6 actor: 6 source NPC armor pieces + Mirror katana + approved M4A1 tactical candidate, all +11; 35 fixed max skills; NPC level-70 gun not inherited')

if __name__=='__main__':main()
