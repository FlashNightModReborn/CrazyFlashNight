"""Native fixed158 consumer: real weapon exports and lifecycle source, no copied art."""
from pathlib import Path
import importlib.util
import json
import argparse
import re
import sys
from lxml import etree as E
import build

ROOT=build.ROOT
sys.path.insert(0,str(ROOT/'tools'))
from choice_reward_catalog import item_catalog
sys.path.insert(0,str(ROOT/'tools/cf6-type61'))
import fixed_roster


def main(projectiles=False,chapter=False,firepower=False):
    spec=importlib.util.spec_from_file_location('soldier_native_consumer',Path(__file__).with_name('build-test-consumer.py'))
    consumer=importlib.util.module_from_spec(spec);spec.loader.exec_module(consumer)
    items=item_catalog()
    rows=json.loads((ROOT/'tools/cf6-type61/fixed-roster.source.json').read_text('utf8'))['roster']
    sources=E.parse(str(ROOT/'data/items/asset_source_map.xml')).getroot()
    lookup={x.get('id'):x for x in sources if x.get('id')}
    preferred={'枪-长枪-G36':'flashswf/arts/things.swf','枪-手枪-Glock 18':'flashswf/arts/things.swf',
               '枪-长枪-能量狙击枪':'flashswf/arts/new/乔恩.swf'}
    selected=[fixed_roster.effective_item(r[slot],items) for r in rows for slot in ('primary','secondary1','secondary2') if r[slot]]
    for item in selected:
        linkage=item.findtext('data/dressup');entry=lookup[linkage]
        source=entry.get('swf') or preferred.get(linkage)
        if source is None:raise ValueError('Unresolved weapon source: '+linkage)
        if not (ROOT/source).is_file():raise ValueError('Missing published source: '+source)
        consumer.IMPORTS[linkage]=source
    if chapter:
        for linkage in ('敌人-CF6Wings','敌人-CF6老头人形','敌人-CF6老头机器人'):
            source=lookup[linkage].get('swf')
            if not source:raise ValueError('Unresolved chapter native actor: '+linkage)
            consumer.IMPORTS[linkage]=source
    if projectiles:
        pending={item.findtext('data/bullet') for item in selected}
        pending.update(r['subweapon']['bullet'] for r in rows if r.get('subweapon'))
        pending.update(items[r['throwable']['name']].findtext('data/bullet') for r in rows if r.get('throwable'))
        pending.update(['横向拖尾追踪联弹','普通无壳子弹','铁枪磁轨弹'])
        cases=E.parse(str(ROOT/'data/items/bullets_cases.xml')).getroot()
        virtual={x.findtext('name') for x in cases.findall('bullet') if x.find('attribute/rayConfig') is not None}
        virtual.update(['近战子弹','近战联弹','透明子弹'])
        visited=set()
        while pending:
            name=pending.pop()
            if not name or name in visited:continue
            visited.add(name)
            if name in virtual:continue
            if name not in lookup:
                parts=name.split('-')
                if len(parts)>1:pending.update(parts);continue
                raise ValueError('Missing real projectile asset: '+name)
            entry=lookup[name];source=entry.get('swf') or preferred.get(name)
            if not source:raise ValueError('Ambiguous projectile source: '+name)
            consumer.IMPORTS[name]=source
            source_file=(ROOT/source).with_suffix('')/'LIBRARY'/(entry.get('symbolName')+'.xml')
            if source_file.is_file():
                for script in E.parse(str(source_file)).xpath('//*[local-name()="script"]'):
                    pending.update(re.findall(r'子弹种类\s*[=:]\s*"([^"\n]+)"',script.text or ''))
                    pending.update(re.findall(r'子弹属性初始化\(this,\s*"([^"\n]+)"',script.text or ''))
        if firepower:
            # The FM92 scatter now uses interceptable unit grenades. They attach
            # to gameWorld, so its native test host needs the shared RSL namespace.
            for name in ('fm92刺弹炮弹','高压爆炸','火焰集束手雷爆炸'):
                source=lookup[name].get('swf')
                if not source or not (ROOT/source).is_file():
                    raise ValueError('Missing timed projectile source: '+name)
                consumer.IMPORTS[name]=source
        consumer.NAME='Cf6FirepowerProjectileHost' if firepower else 'Cf6FixedProjectileHost'
    else:consumer.NAME='Cf6FixedChapterHost' if chapter else 'Cf6FixedSoldierNativeHost'
    consumer.OWNER=ROOT/'scripts'/consumer.NAME
    anchors=[]
    for source in sorted(set(consumer.IMPORTS.values())):
        stem=Path(source).stem
        if stem in lookup and lookup[stem].get('swf')==source:
            consumer.IMPORTS[stem]=source;anchors.append(stem)
        elif projectiles or chapter:
            # Some legacy libraries have no exported library-named anchor.
            # A real first-frame import forces their definitions to load; the
            # fixture retires this preview before creating its first actor.
            anchors.append(next(name for name,path in consumer.IMPORTS.items() if path==source))
    extra='''import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.UnitComponent.Dressup.*;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.*;
import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.item.equipment.*;
import org.flashNight.arki.camera.*;
import org.flashNight.arki.bullet.Factory.*;
import org.flashNight.arki.bullet.BulletComponent.Queue.*;
import org.flashNight.gesh.object.*;
_root.cf6InstallNativeEquipmentLifecycle=function():Void {
    #include "../逻辑/单位函数/单位函数_fs_装备生命周期配置.as"
    #include "../逻辑/装备函数/通用装备函数.as"
    #include "../逻辑/装备函数/G1111.as"
    #include "../逻辑/装备函数/M134.as"
    #include "../逻辑/装备函数/M249.as"
    #include "../逻辑/装备函数/NEGEV.as"
    #include "../逻辑/装备函数/P90.as"
    #include "../逻辑/装备函数/RPG.as"
};
'''
    player_source=(ROOT/'scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as').read_text('utf-8-sig')
    slot_sources=[]
    for name in ('创建主动战技槽位表','获取装备主动战技种类'):
        matches=re.findall(r'(?m)^_root\.主角函数\.'+name+r' = function[^\n]*\{[\s\S]*?^\};?',player_source)
        if len(matches)!=1:raise ValueError('Canonical skill routing facade changed: '+name)
        slot_sources.append(matches[0])
    extra=extra.replace('    #include "../逻辑/单位函数/单位函数_fs_装备生命周期配置.as"',
        '\n'.join(slot_sources)+'\n    #include "../逻辑/单位函数/单位函数_fs_装备生命周期配置.as"')
    extra+='\n_root.cf6NativeRslAnchorCount='+str(len(consumer.IMPORTS))+';\n'
    if projectiles:
        battle=(ROOT/'scripts/逻辑/战斗系统/战斗系统_fs_lsy_aka_重写子弹生成逻辑.as').read_text('utf-8-sig')
        legacy=re.findall(r'(?m)^_root\.子弹区域shoot = function[^\n]*\n\{[\s\S]*?^\}',battle)
        if len(legacy)!=1:raise ValueError('Canonical legacy projectile facade changed')
        extra+='\nimport org.flashNight.arki.bullet.BulletComponent.Chain.*;\nimport org.flashNight.gesh.depth.*;\nimport org.flashNight.neur.ScheduleTimer.*;\n'
        extra+='#include "../逻辑/战斗系统/战斗系统_fs_联弹管理.as"\n'+legacy[0]+'\n_root.子弹区域shoot表演=_root.子弹区域shoot;\n'
    if chapter:
        boot=(ROOT/'scripts/asLoaderManifest/_collapsed_frame.as').read_text('utf-8-sig')
        extra+='\n'+'\n'.join(re.findall(r'^import .*?;',boot,re.M))+'\n'
        extra+='_root.cf6InstallChapterRuntime=function():Void {\n#include "../逻辑/单位函数/单位函数_lsy_敌人模板迁移.as"\n};\n'
        conversion=(ROOT/'scripts/逻辑/关卡系统/关卡系统_lsy_场景转换.as').read_text('utf-8-sig')
        loader=re.findall(r'(?m)^_root\.加载游戏世界人物 = function[^\n]*\{[\s\S]*?^\}',conversion)
        if len(loader)!=1:raise ValueError('Canonical actor attachment facade drift')
        begin=player_source.index('_root.根据等级计算值 = function(')
        end=player_source.index('_root.身高百分比转换',begin)
        calculator=player_source[begin:end]
        extra+='_root.cf6InstallChapterHelpers=function():Void {\n'+loader[0]+'\n'+calculator+'\n};\n'
    manifest='firepower-projectile-host-manifest.json' if firepower else 'fixed-projectile-host-manifest.json' if projectiles else 'fixed-chapter-host-manifest.json' if chapter else 'fixed-test-host-manifest.json'
    consumer.main(manifest,1024,576,extra,anchors)


if __name__=='__main__':
    parser=argparse.ArgumentParser();group=parser.add_mutually_exclusive_group()
    group.add_argument('--projectiles',action='store_true');group.add_argument('--chapter',action='store_true')
    group.add_argument('--firepower-projectiles',action='store_true');args=parser.parse_args()
    main(args.projectiles or args.firepower_projectiles,args.chapter,args.firepower_projectiles)
