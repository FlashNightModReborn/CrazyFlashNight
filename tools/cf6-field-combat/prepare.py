"""Prepare an isolated native host and include actual production spawn/projectile bridges."""
from pathlib import Path
import xml.etree.ElementTree as ET
import re,hashlib,json,shutil,argparse
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
NS='http://ns.adobe.com/xfl/2008/'
def build(check=False):
    from check_structure import check as check_structure
    check_structure(HERE/'Cf6FieldCombatTest.as.txt')
    source=ROOT/'scripts/Cf6ActorAppearanceNativeHost';dest=ROOT/'scripts/tmp-cf6-field-combat3-host'
    outputs={}
    for p in (source/'LIBRARY').rglob('*'):
        if p.is_file():outputs[dest/p.relative_to(source)]=p.read_bytes()
    document=(source/'DOMDocument.xml').read_text(encoding='utf-8').replace('../scripts/TestLoader.as','../TestLoader.as')
    document=document.replace('</symbols>','<Include href="ImportFieldCodex.xml" loadImmediate="false"/><Include href="ImportFieldBullets.xml" loadImmediate="false"/><Include href="ImportFieldElder.xml" loadImmediate="false"/><Include href="ImportFieldGuard.xml" loadImmediate="false"/><Include href="ImportFieldHeadbot.xml" loadImmediate="false"/></symbols>')
    document=document.replace('</elements>','<DOMSymbolInstance libraryItemName="ImportFieldCodex" name="__fieldCodexRsl"/><DOMSymbolInstance libraryItemName="ImportFieldBullets" name="__fieldBulletRsl"/><DOMSymbolInstance libraryItemName="ImportFieldElder" name="__fieldElderRsl"/><DOMSymbolInstance libraryItemName="ImportFieldGuard" name="__fieldGuardRsl"/><DOMSymbolInstance libraryItemName="ImportFieldHeadbot" name="__fieldHeadbotRsl"/></elements>')
    outputs[dest/'DOMDocument.xml']=document.encode('utf-8')
    outputs[dest/'Cf6FieldCombatNativeHost.xfl']=(source/'Cf6ActorAppearanceNativeHost.xfl').read_bytes()
    settings=(source/'PublishSettings.xml').read_text(encoding='utf-8')
    for a,b in [('<PackagePaths>scripts/类定义;scripts;</PackagePaths>','<PackagePaths>类定义;</PackagePaths>'),('<defaultNames>1</defaultNames>','<defaultNames>0</defaultNames>'),('<flashDefaultName>1</flashDefaultName>','<flashDefaultName>0</flashDefaultName>'),('Cf6ActorAppearanceNativeHost.swf','../Cf6FieldCombat3NativeHost.swf')]:
        if settings.count(a)!=1:raise ValueError('host template changed '+a)
        settings=settings.replace(a,b)
    outputs[dest/'PublishSettings.xml']=settings.encode('utf-8')
    for name,link,url in [('ImportFieldCodex','Codex专用素材','flashswf/arts/new/Codex专用素材.swf'),('ImportFieldBullets','原版素材库-子弹','flashswf/arts/原版素材库-子弹.swf'),('ImportFieldElder','Codex老头素材','flashswf/arts/new/Codex老头素材.swf'),('ImportFieldGuard','Codex光头保安素材','flashswf/arts/new/Codex光头保安素材.swf'),('ImportFieldHeadbot','Codex大头机器人素材','flashswf/arts/new/Codex大头机器人素材.swf')]:
        outputs[dest/'LIBRARY'/(name+'.xml')]=('<DOMSymbolItem xmlns="'+NS+'" name="'+name+'" linkageImportForRS="true" linkageIdentifier="'+link+'" linkageURL="'+url+'" linkageExportInFirstFrame="true"><timeline><DOMTimeline name="'+name+'"><layers><DOMLayer name="RSL"><frames><DOMFrame index="0"><elements/></DOMFrame></frames></DOMLayer></layers></DOMTimeline></timeline></DOMSymbolItem>').encode('utf-8')
    boot=(ROOT/'scripts/asLoaderManifest/_collapsed_frame.as').read_text(encoding='utf-8-sig')
    imports='\n'.join(re.findall(r'^import .*?;',boot,re.M))
    math_source=(ROOT/'scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as').read_text(encoding='utf-8-sig')
    start=math_source.index('_root.根据等级计算值 = function(');end=math_source.index('_root.身高百分比转换',start)
    helper=math_source[start:end]
    utility_path=ROOT/'scripts/引擎/引擎_fs_常用工具函数.as'
    utility_bytes=utility_path.read_bytes();utility=utility_bytes.decode('utf-8-sig')
    copy_start=utility.index('_root.对象浅拷贝 = function(Obj){');copy_end=utility.index('_root.深拷贝数组',copy_start)
    shallow_copy=utility[copy_start:copy_end]
    helper_receipt={'shallowCopy':{'source':utility_path.relative_to(ROOT).as_posix(),
        'sourceBytes':len(utility_bytes),'sourceSha256':hashlib.sha256(utility_bytes).hexdigest(),
        'extractedUtf8Sha256':hashlib.sha256(shallow_copy.encode('utf-8')).hexdigest()}}
    fragment_path=ROOT/'scripts/逻辑/关卡系统/关卡系统_lsy_地图元件.as'
    fragment_bytes=fragment_path.read_bytes();fragment_source=fragment_bytes.decode('utf-8-sig');fragment_functions=[]
    for name in ['地图元件破碎动画','停止地图元件破碎动画','地图元件破碎动画运行中']:
        begin=fragment_source.index('_root.地图元件.'+name+' = function(')
        end=fragment_source.index('\n};',begin)+3
        fragment_functions.append(fragment_source[begin:end])
    fragment_helpers='\n'.join(fragment_functions)
    helper_receipt['fragmentEngine']={'source':fragment_path.relative_to(ROOT).as_posix(),'sourceBytes':len(fragment_bytes),
        'sourceSha256':hashlib.sha256(fragment_bytes).hexdigest(),'extractedUtf8Sha256':hashlib.sha256(fragment_helpers.encode('utf-8')).hexdigest()}
    outputs[HERE/'production-helpers.json']=(json.dumps(helper_receipt,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    template=imports+'\n'+helper+'\n'+shallow_copy+'\n_root.身高百分比转换=UnitUtil.getHeightPercentage;\n_root.获取操控编号=function(name){return name==_root.控制目标?0:-1;};\n'
    template+='import org.flashNight.arki.spatial.animation.*;\n_root.地图元件={};\n'+fragment_helpers+'\n'
    template+='#include "../逻辑/关卡系统/关卡系统_lsy_场景转换.as"\n#include "../逻辑/战斗系统/战斗系统_fs_lsy_aka_重写子弹生成逻辑.as"\n'
    # Match the production f36_4 definition context before deciding whether a bare-name failure is fixture-specific.
    template+='_root.__cf6NativeBoot={};\n_root.__cf6NativeBoot.f36_4=function():Void {\n#include "../逻辑/单位函数/单位函数_lsy_敌人模板迁移.as"\n};\n_root.__cf6NativeBoot.f36_4();\n'
    template+='trace("FocusedTestRunId cf6-field-combat Start: __FOCUSED_RUN_ID__");\n_root.cf6FieldCombatComplete=function():Void {trace("FocusedTestRunId cf6-field-combat Complete: __FOCUSED_RUN_ID__");};\norg.flashNight.arki.scene.Cf6FieldCombatTest.runAllTests();\n'
    outputs[HERE/'TestLoader.as.template']=b'\xef\xbb\xbf'+template.encode('utf-8')
    chapter=json.loads((ROOT/'data/stages/books/cf6-sting.runtime.json').read_text(encoding='utf-8-sig'))
    maps={m['id']:m for m in chapter['maps']}
    envroot=ET.parse(ROOT/'data/environment/stage_environment.xml').getroot()
    env=next(e for e in envroot if e.findtext('BackgroundURL')=='CF6_A01_BG.swf')
    boxes=[]
    for c in env.findall('Collision'):
        points=[tuple(map(float,p.text.split(','))) for p in c.findall('Point')]
        boxes.append([min(p[0] for p in points),min(p[1] for p in points),max(p[0] for p in points),max(p[1] for p in points)])
    spec=maps['A01']['mechanism']['turrets']
    for turret in spec['turrets']:
        own=[b for b in boxes if b[0]<turret['x']<b[2] and b[1]<turret['y']<b[3]]
        if len(own)!=1:raise ValueError('ambiguous authored own footprint')
        turret['ownFootprint']=own[0]
    units=json.loads((ROOT/'data/units/units.json').read_text(encoding='utf-8-sig'))
    clone=next(u for u in units if u['id']==460)
    attrs={'兵种名':clone['spritename'],'名字':clone['name'],'是否为敌人':clone['is_hostile'],'身高':clone['height']}
    def literal(v):
        if isinstance(v,dict):
            for k in v:
                if not re.match(r'^[^\W\d]\w*$',k,re.UNICODE):raise ValueError('invalid AS2 key '+k)
            return '{'+','.join(k+':'+literal(x) for k,x in v.items())+'}'
        if isinstance(v,list):return '['+','.join(literal(x) for x in v)+']'
        return json.dumps(v,ensure_ascii=False,separators=(',',':'))
    data='class org.flashNight.arki.scene.Cf6FieldCombatData {\n'
    def unit_attrs(n):
        u=next(u for u in units if u['id']==n)
        return {'兵种名':u['spritename'],'名字':u['name'],'是否为敌人':u['is_hostile'],'身高':u['height']}
    for name,value in [('turrets',spec),('walls',boxes),('podSpec',maps['A15']['mechanism']['interactiveProps']),('bossPodSpec',maps['A17']['mechanism']['interactiveProps']),('cloneAttributes',attrs),('humanAttributes',unit_attrs(473)),('robotAttributes',unit_attrs(474)),('guardAttributes',unit_attrs(469)),('headbotAttributes',unit_attrs(472)),('headbotPlan',maps['A17']['bossEncounter'])]:
        data+='public static function '+name+'():Object {return '+literal(value)+';}\n'
    data+='}\n'
    outputs[HERE/'Cf6FieldCombatData.as.txt']=data.encode('utf-8')
    target=ROOT/'scripts/类定义/org/flashNight/arki/scene/Cf6FieldCombatData.as'
    if not target.exists() and not check:shutil.copyfile(ROOT/'scripts/类定义/org/flashNight/arki/scene/BookRunRules.as',target)
    outputs[target]=b'\xef\xbb\xbf'+data.encode('utf-8')
    test_target=target.with_name('Cf6FieldCombatTest.as')
    test_source=HERE/'Cf6FieldCombatTest.as.txt'
    if test_source.exists():
        if not test_target.exists() and not check:shutil.copyfile(ROOT/'scripts/类定义/org/flashNight/arki/scene/BookRunRules.as',test_target)
        outputs[test_target]=b'\xef\xbb\xbf'+test_source.read_bytes()
    for path,raw in outputs.items():
        if path.exists() and path.read_bytes()==raw:continue
        if check or (path.is_relative_to(dest) and path.exists()):raise ValueError('preserve/reconcile differing native host '+str(path))
        path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
    print(json.dumps({'files':len(outputs),'state':'checked' if check else 'prepared'}))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');build(p.parse_args().check)
