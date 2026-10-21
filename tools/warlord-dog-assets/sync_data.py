"""Project this dog's recorded formula/config into its own data nodes only."""
import argparse
import json
from pathlib import Path
import re
import xml.etree.ElementTree as E

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
KIND = '敌人-军阀铁卫犬'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    balance = json.loads((HERE/'balance-inputs.json').read_text(encoding='utf-8'))
    stats, inp = balance['stats'], balance['input']
    fields = {'displayname':'军阀铁卫犬','battleRecordAppearance':'fixed',
        '最小经验值':stats['expMin'],'最大经验值':stats['expMax'],
        'hp_min':stats['hpMin'],'hp_max':stats['hpMax'],
        '速度_min':stats['speedMin'],'速度_max':stats['speedMax'],
        '空手攻击力_min':stats['atkMin'],'空手攻击力_max':stats['atkMax'],
        '躲闪率_min':30,'躲闪率_max':15,
        '基本防御力_min':stats['defMin'],'基本防御力_max':stats['defMax'],
        '装备防御力':0,'性别':'男','重量':45,'韧性系数':1,'label':'null'}
    lines = [f'    <{KIND}>']+[f'        <{k}>{v}</{k}>' for k,v in fields.items()]
    lines += ['        <魔法抗性>','            <装甲>25</装甲>','            <统合>15</统合>',
              '            <凡俗>20</凡俗>','        </魔法抗性>','        <铁卫犬>']
    lines += [f'            <{k}>{v}</{k}>' for k,v in balance['config'].items()]
    lines += ['        </铁卫犬>','        <标识>']
    names = ['阶段','档次系数','成长系数','攻速系数','攻击倍率','段数系数','速度系数',
             '高攻低血防系数','霸体系数','高防低血系数']
    keys = ['stage','tierFactor','growthFactor','atkSpeedFactor','atkMultiplier','segmentFactor',
            'speedFactor','highAtkFactor','superArmorFactor','highDefFactor']
    lines += [f'            <{n}>{inp[k]}</{n}>' for n,k in zip(names,keys)]
    lines += ['        </标识>',f'    </{KIND}>']
    node = '\n'.join(lines)+'\n'
    path = ROOT/'data/enemy_properties/军阀新人物.xml'
    text = path.read_text(encoding='utf-8-sig')
    pattern = rf'    <{KIND}>.*?</{KIND}>\s*'
    projected = re.sub(pattern,node,text,flags=re.S) if f'<{KIND}>' in text else text.replace('</root>',node+'</root>')
    failures=[]
    if args.check:
        if projected != text: failures.append(str(path.relative_to(ROOT)))
    elif projected != text:
        path.write_text(projected,encoding='utf-8')
    units_path=ROOT/'data/units/units.json'
    text=units_path.read_text(encoding='utf-8-sig')
    units=json.loads(text)
    record={'id':balance['unitId'],'spritename':KIND,'level':20,'name':'军阀铁卫犬',
            'is_hostile':True,'height':175,'data':{'primary':None,'secondary':None,'secondary2':None,'melee':None}}
    found=[u for u in units if u['id']==balance['unitId'] or u['spritename']==KIND]
    if found:
        assert found==[record],found
    elif args.check:
        failures.append(str(units_path.relative_to(ROOT)))
    else:
        suffix=json.dumps(record,ensure_ascii=False,indent=2)
        indented='\n'.join('  '+line for line in suffix.splitlines())
        units_path.write_text(text.rstrip()[:-1].rstrip()+',\n'+indented+'\n]\n',encoding='utf-8')
    # Each replaced dog is explicitly in a military combat group, including base defence.
    for name in ['军阀临时补给点','军阀据点','残垣断壁','基地','难民营地']:
        path=ROOT/'data/stages/基地房顶'/f'{name}.xml'
        text=path.read_text(encoding='utf-8-sig')
        projected=text.replace('<Type>兵种13</Type>',f'<Type>兵种{balance["unitId"]}</Type>')
        if args.check:
            if projected!=text:failures.append(str(path.relative_to(ROOT)))
        elif projected!=text:path.write_text(projected,encoding='utf-8')
    # The opening wild dog stays ordinary. Only the military ambush replaces a rifleman.
    path=ROOT/'data/stages/地下2层/禁区边缘.xml'
    text=path.read_text(encoding='utf-8-sig')
    marker='<SubStage id="1">';head,tail=text.split(marker,1)
    middle,ending=tail.split('</SubStage>',1)
    if f'<Type>兵种{balance["unitId"]}</Type>' not in middle:
        matches=list(re.finditer(r'<Enemy>\s*<Type>兵种56</Type>.*?</Enemy>',middle,re.S))
        assert len(matches)==3
        match=matches[-1]
        dog=match.group().replace('<Type>兵种56</Type>',f'<Type>兵种{balance["unitId"]}</Type>')
        dog=dog.replace('<IsHostile>null</IsHostile>',
            '<IsHostile>null</IsHostile>\n                        <x>1080</x>\n                        <y>396</y>')
        middle=middle[:match.start()]+dog+middle[match.end():]
    matches=list(re.finditer(r'<Enemy>\s*<Type>兵种56</Type>.*?</Enemy>',middle,re.S))
    assert len(matches)==2
    for match,x in reversed(list(zip(matches,[990,900]))):
        soldier=match.group()
        if '<x>' not in soldier:
            soldier=soldier.replace('<IsHostile>null</IsHostile>',
                f'<IsHostile>null</IsHostile>\n                        <x>{x}</x>\n                        <y>396</y>')
            middle=middle[:match.start()]+soldier+middle[match.end():]
    projected=head+marker+middle+'</SubStage>'+ending
    if args.check:
        if projected!=text:failures.append(str(path.relative_to(ROOT)))
    elif projected!=text:path.write_text(projected,encoding='utf-8')
    if failures:raise SystemExit('Stale dog data: '+', '.join(failures))
    print(json.dumps({'check':args.check,'unitId':balance['unitId'],'failures':failures}))


if __name__=='__main__':main()
