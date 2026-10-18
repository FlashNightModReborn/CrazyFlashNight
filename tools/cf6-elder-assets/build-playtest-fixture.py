"""Generate only exact production adapters and the canonical male-player hit-area fixture."""
from pathlib import Path
import argparse,hashlib,json,shutil
from lxml import etree as E
ROOT=Path(__file__).resolve().parents[2]
NS={'x':'http://ns.adobe.com/xfl/2008/'}
def function(path,name):
    text=path.read_text('utf-8-sig');start=text.index(name+' = function(')
    return text[start:text.index('\n};',start)+3]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def expected():
    mapfile=ROOT/'scripts/逻辑/关卡系统/关卡系统_lsy_地图元件.as'
    shield=ROOT/'scripts/逻辑/单位函数/单位函数_fs_护盾函数.as'
    player=ROOT/'flashswf/arts/things0/LIBRARY/主角-男.xml'
    area=ROOT/'flashswf/arts/things0/LIBRARY/主角肢体素材/Symbol 6.xml'
    shape=ROOT/'flashswf/arts/things0/LIBRARY/shape/Symbol 5.xml'
    root=E.parse(str(player));entries=root.findall('.//x:DOMSymbolInstance[@name="area"]',NS)
    assert len(entries)==1 and entries[0].get('libraryItemName')=='主角肢体素材/Symbol 6'
    assert E.parse(str(area)).find('.//x:DOMSymbolInstance',NS).get('libraryItemName')=='shape/Symbol 5'
    edges=E.parse(str(shape)).find('.//x:Edge',NS).get('edges')
    assert edges=='!500 500S2|0 500!0 500|0 0!0 0|500 0!500 0|500 500'
    m=entries[0].find('x:matrix/x:Matrix',NS)
    values=[float(m.get(k,1 if k in ('a','d') else 0)) for k in ('a','b','c','d','tx','ty')]
    body='import org.flashNight.arki.spatial.animation.*;\nimport org.flashNight.arki.component.Shield.*;\nimport org.flashNight.arki.unit.*;\nimport flash.geom.*;\n_root.地图元件={};\n_root.护盾函数={};\n'
    for path,name in [(mapfile,'_root.地图元件.地图元件破碎动画'),(mapfile,'_root.地图元件.停止地图元件破碎动画'),(mapfile,'_root.地图元件.地图元件破碎动画运行中'),(shield,'_root.护盾函数.添加临时护盾'),(shield,'_root.护盾函数.添加衰减护盾'),(shield,'_root.护盾函数.移除护盾')]:body+=function(path,name)+'\n'
    body+='_root.cf6MakePlayerTarget=function(world:MovieClip,name:String,height:Number):MovieClip {\n    var target:MovieClip=world.createEmptyMovieClip(name,world.getNextHighestDepth());\n    target.hp=target.hp满血值=100000;target.等级=50;target.防御力=1;target.damageTakenMultiplier=1;\n    target.ti61CrumbleTakenMultiplier=1;target.魔法抗性={波:0};target.dispatcher={publish:function():Void {}};\n    target.shield=AdaptiveShield.createDormant("player-area-fixture");target.shield.setOwner(target);\n    target.Z轴坐标=target._y=200;\n    var area:MovieClip=target.createEmptyMovieClip("area",1);\n    area.beginFill(0xFF0000,0);area.moveTo(25,25);area.lineTo(0,25);area.lineTo(0,0);area.lineTo(25,0);area.lineTo(25,25);area.endFill();\n    area.transform.matrix=new Matrix(__MATRIX__);\n    target._xscale=target._yscale=UnitUtil.getHeightPercentage(height);\n    return target;\n};\n'.replace('__MATRIX__',','.join(str(v) for v in values))
    death=ROOT/'scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as'
    body+='import org.flashNight.arki.unit.UnitComponent.Deinitializer.*;\n'
    body+=function(death,'_root.敌人函数.死亡检测').replace('_root.敌人函数.死亡检测 =','_root.cf6ProductionDeathCheck =',1)+'\n'
    paths=[mapfile,shield,player,area,shape,death,ROOT/'scripts/类定义/org/flashNight/arki/unit/UnitUtil.as']
    manifest={'sources':[{'path':p.relative_to(ROOT).as_posix(),'sha256':sha(p)} for p in paths],'playerAreaMatrix':values,'shapePixels':[0,0,25,25],'scale':'production UnitUtil.getHeightPercentage'}
    return body,manifest
args=argparse.ArgumentParser();args.add_argument('--check',action='store_true');a=args.parse_args()
text,manifest=expected();folder=ROOT/'scripts/test-runners/cf6-playtest';folder.mkdir(exist_ok=True)
target=folder/'PlaytestFixture.as';ledger=Path(__file__).with_name('playtest-fixture-manifest.json')
if a.check:
    assert target.read_text('utf-8-sig')==text
    assert json.loads(ledger.read_text('utf8'))==manifest
else:
    if not target.exists():shutil.copyfile(ROOT/'tools/cf6-elder-assets/ElderAI.as',target)
    target.write_text(text,'utf-8-sig',newline='\n');ledger.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n','utf8',newline='\n')
print(json.dumps({'ok':True,'sources':len(manifest['sources']),'playerAreaMatrix':manifest['playerAreaMatrix']},ensure_ascii=False))
