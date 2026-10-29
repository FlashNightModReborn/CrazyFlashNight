"""Build a disposable RSL consumer for the native equipment fixture.

Separate loadMovie libraries do not share attachMovie linkage scope. This
consumer imports the actual soldier and weapon symbols like the game does;
no weapon art or production classes are copied into the fixture.
"""
from pathlib import Path
import hashlib
import json
import re
from lxml import etree as E
import build

ROOT = build.ROOT
OWNER = ROOT / 'scripts/Cf6SoldierNativeHost'
NAME = 'Cf6SoldierNativeHost'
N, NS, native = build.N, build.NS, build.native
IMPORTS = {
    '加载MC库0': 'flashswf/arts/things.swf',
    'Au的素材': 'flashswf/arts/new/Au的素材.swf',
    'Codex特种兵素材': 'flashswf/arts/new/Codex特种兵素材.swf',
    '敌人-CF6特种兵': 'flashswf/arts/new/Codex特种兵素材.swf',
    '敌人-CF6持盾特种兵': 'flashswf/arts/new/Codex特种兵素材.swf',
    '敌人-CF6特种精英': 'flashswf/arts/new/Codex特种兵素材.swf',
    '敌人-CF6持盾特种精英': 'flashswf/arts/new/Codex特种兵素材.swf',
    '敌人-CF6特种教官': 'flashswf/arts/new/Codex特种兵素材.swf',
    '敌人-CF6持盾特种教官': 'flashswf/arts/new/Codex特种兵素材.swf',
    'CF6战术烟雾': 'flashswf/arts/new/Codex特种兵素材.swf',
    '枪-长枪-M4A1改': 'flashswf/arts/things.swf',
    '枪-长枪-AK74战术版': 'flashswf/arts/things.swf',
    '枪-长枪-M4A1战术版': 'flashswf/arts/things.swf',
    '枪-长枪-DD MK18战术版': 'flashswf/arts/new/Au的素材.swf',
    '枪-长枪-AK47': 'flashswf/arts/things.swf',
    '枪-手枪-FR506': 'flashswf/arts/new/偷吃屑鱼坟头贡品.swf',
    '枪-手枪-短HK53': 'flashswf/arts/new/偷吃屑鱼坟头贡品.swf',
    '偷吃屑鱼坟头贡品': 'flashswf/arts/new/偷吃屑鱼坟头贡品.swf',
    '手雷-高爆手雷': 'flashswf/arts/原版素材库-子弹.swf',
    '手雷-普通手雷': 'flashswf/arts/原版素材库-子弹.swf',
    '高爆手雷': 'flashswf/arts/原版素材库-子弹.swf',
    '普通手雷': 'flashswf/arts/原版素材库-子弹.swf',
    '普通爆炸': 'flashswf/arts/原版素材库-子弹.swf',
    '原版素材库-子弹': 'flashswf/arts/原版素材库-子弹.swf',
}


def canonical_fixture_facades():
    skill_path=ROOT/'scripts/逻辑/单位函数/单位函数_lsy_主角技能.as'
    enemy_path=ROOT/'scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as'
    player_path=ROOT/'scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as'
    scripts=[]
    for path,names in ((skill_path,('霸体减伤','移除霸体减伤')),(enemy_path,('行走',)),(player_path,('初始化掉落物',))):
        text=path.read_text(encoding='utf-8-sig')
        for name in names:
            owner='敌人函数' if name=='行走' else '主角函数' if name=='初始化掉落物' else '技能函数'
            pattern=r'(?m)^_root\.'+owner+r'\.'+name+r' = function\([^\n]*\)[^\n]*\{[\s\S]*?^\};'
            matches=re.findall(pattern,text)
            if len(matches)!=1:raise ValueError('Canonical fixture facade changed: '+name)
            source=matches[0]
            if name=='行走':source=source.replace('_root.敌人函数.行走 =','_root.士兵测试标准行走 =',1)
            if name=='初始化掉落物':source=source.replace('_root.主角函数.初始化掉落物 =','_root.士兵测试初始化掉落物 =',1)
            scripts.append(source)
    bullet_source=(ROOT/'scripts/逻辑/战斗系统/战斗系统_fs_lsy_aka_重写子弹生成逻辑.as').read_text(encoding='utf-8-sig')
    matches=re.findall(r'(?m)^_root\.子弹属性初始化 = function\([^\n]*\)[^\n]*\{[\s\S]*?^\};?',bullet_source)
    if len(matches)!=1:raise ValueError('Canonical grenade payload initializer changed')
    scripts.append(matches[0])
    return ('import org.flashNight.arki.component.Buff.*;\n'
        'import org.flashNight.arki.component.Buff.Component.*;\n_root.技能函数={};\n'+'\n'.join(scripts))


def main():
    generated = {}
    doc = E.Element(N+'DOMDocument', nsmap={None:NS['x']}, width='550',height='400',
        frameRate='30',xflVersion='2.2',creatorInfo='Adobe Flash Professional CS6',
        platform='Windows',versionInfo='Saved by Adobe Flash Windows 12.0 build 481',majorVersion='12',buildNumber='481')
    includes = E.SubElement(doc,N+'symbols')
    instances, anchors = [], []
    for index,(linkage,relative) in enumerate(IMPORTS.items()):
        name = 'Import'+str(index)
        item = native.symbol(name,[native.layer('RSL',[native.frame()])],symbol_type='movie clip')
        item.set('linkageImportForRS','true')
        item.set('linkageIdentifier',linkage)
        item.set('linkageURL','../'+relative)
        item.set('linkageExportInFirstFrame','true')
        generated['LIBRARY/'+name+'.xml'] = native.xml_bytes(item)
        E.SubElement(includes,N+'Include',href=name+'.xml',itemID=native.item_id(name),loadImmediate='false')
        (anchors if index<3 or relative=='flashswf/arts/new/偷吃屑鱼坟头贡品.swf' or linkage=='原版素材库-子弹' else instances).append(native.instance(name,symbol_type='movie clip',name='source'+str(index),alpha_mult=0,
            matrix=(1,0,0,1,-5000,-5000)))
    timeline = E.SubElement(E.SubElement(doc,N+'timelines'),N+'DOMTimeline',name='场景 1')
    E.SubElement(timeline,N+'layers').append(native.layer('真实 RSL 消费者',[
        native.frame(script='stop();\n'+canonical_fixture_facades()+'\n#include "../TestLoader.as"',elements=anchors),
        native.frame(1,elements=instances)]))
    generated['DOMDocument.xml'] = native.xml_bytes(doc)
    generated[NAME+'.xfl'] = b'PROXY-CS5\n'
    generated['MobileSettings.xml'] = b''
    generated['PublishSettings.xml'] = (ROOT/'scripts/FormerSheriffNativeHost/PublishSettings.xml').read_text(encoding='utf8').replace('FormerSheriffNativeHost',NAME).encode('utf8')
    manifest_path = build.HERE/'test-host-manifest.json'
    if manifest_path.exists():
        previous = json.loads(manifest_path.read_text(encoding='utf8'))
        for row in previous['files']:
            path = OWNER/row['path']
            if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=row['sha256']:
                raise ValueError('Fixture source changed outside its generator: '+row['path'])
    elif OWNER.exists() and any(OWNER.iterdir()):
        raise ValueError('Refuse to overwrite unowned fixture directory')
    for name,data in generated.items():
        path = OWNER/name
        path.parent.mkdir(parents=True,exist_ok=True)
        if not path.exists() or path.read_bytes()!=data:
            path.write_bytes(data)
    if manifest_path.exists():
        for row in previous['files']:
            if row['path'] not in generated:
                obsolete = (OWNER/row['path']).resolve()
                if not obsolete.is_relative_to(OWNER.resolve()):
                    raise ValueError('Invalid obsolete fixture path')
                backup = ROOT/'tmp/cf6-soldier-equipment-consumer/obsolete'/row['sha256']
                backup.parent.mkdir(exist_ok=True)
                if not backup.exists():
                    backup.write_bytes(obsolete.read_bytes())
                obsolete.unlink()
    manifest = {'schema':'cf6-soldier.equipment-consumer.v2','imports':IMPORTS,
        'canonicalFixtureFacadesSha256':hashlib.sha256(canonical_fixture_facades().encode('utf8')).hexdigest(),
        'generatorSha256':build.sha(Path(__file__)),
        'referencePublishSettingsSha256':build.sha(ROOT/'scripts/FormerSheriffNativeHost/PublishSettings.xml'),
        'files':[{'path':p,'sha256':hashlib.sha256(data).hexdigest()} for p,data in generated.items()]}
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps({'target':str(OWNER/(NAME+'.xfl')),'swf':str(OWNER.parent/(NAME+'.swf')),'imports':len(IMPORTS)},ensure_ascii=False))


if __name__=='__main__':
    main()
