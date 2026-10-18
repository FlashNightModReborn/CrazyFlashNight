from evidence_utils import *
import subprocess

for row in js(TMP/'matrix-r11/input-identity.json')['sourceBindings']:
    assert sha(ROOT/row['path'])==row['sha256'],'Unexpected R11 source drift: '+row['path']
for relative in ['tools/cf6-elder-assets/ElderAI.as','tools/cf6-elder-assets/README.md',
    'tools/cf6-elder-assets/native-manifest.json','flashswf/arts/new/Codex老头素材.swf',
    'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderAssetTest.as']:
    put(TMP/'r11-before-ai'/relative,read(ROOT/relative))
ai=ROOT/'tools/cf6-elder-assets/ElderAI.as'
data=read(ai);assert data[:3]==b'\xef\xbb\xbf'
old='closeRange:elderForm=="human"?175:150'.encode()
new='closeRange:elderForm=="human"?175:190'.encode()
assert data.count(old)==1
ai.write_bytes(data.replace(old,new))
test=ROOT/'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderAssetTest.as'
data=read(test);assert data[:3]==b'\xef\xbb\xbf'
source=data[3:].decode('utf8')
needle='        check(r.elderChooseAttack(500,0,0)=="beam","robot beam range");'
insert='''        check(r.elderChooseAttack(190,0,0)=="kicks","robot kick approach includes 190 pixel boundary");
        check(r.elderChooseAttack(191,0,0)=="beam","outside kick approach retains ranged beam");
'''+needle
assert source.count(needle)==1;source=source.replace(needle,insert)
needle='''            u.状态改变(state);
        }
        if(ticks==7)'''
insert='''            if(c.move=="kicks"){
                var target:MovieClip=library.createEmptyMovieClip("kickReachTarget"+i,library.getNextHighestDepth());
                target.hp=1000;target._x=u._x+(c.side==0?190:-190);target._y=target.Z轴坐标=u.Z轴坐标;
                target.beginFill(0);target.moveTo(-20,-100);target.lineTo(20,-100);
                target.lineTo(20,0);target.lineTo(-20,0);target.lineTo(-20,-100);target.endFill();
                u.攻击目标=target._name;c.record.reachTarget=target;c.record.reachOverlaps=0;
            }
            u.状态改变(state);
        }
        if(ticks==7)'''
assert source.count(needle)==1;source=source.replace(needle,insert)
needle='''            if(action=="beam")rec.areaOk=rec.areaOk && Math.abs(bounds.xMax-bounds.xMin-461.05)<0.3;'''
insert=needle+'''
            if(action=="kicks" && rec.reachTarget!=null){
                var targetBounds:Object=rec.reachTarget.getBounds(library);
                var overlap:Boolean=bounds.xMin<targetBounds.xMax && bounds.xMax>targetBounds.xMin
                    && bounds.yMin<targetBounds.yMax && bounds.yMax>targetBounds.yMin;
                if(overlap)rec.reachOverlaps++;
                check(overlap,"authored kick contact reaches target from 190 pixels "+frame+" "+u.方向);
                check(Math.abs(rec.reachTarget._x-u._x)>=90,"kick approach does not overshoot its stop bound "+frame+" "+u.方向);
            }'''
assert source.count(needle)==1;source=source.replace(needle,insert)
needle='''                if(c.move=="hit0")check(rec.lastRecoveryFrame==12,"first authored hit branch ends at frame 12 "+i);'''
insert='''                if(c.move=="kicks")check(rec.reachOverlaps==2 && rec.moves>0,"both authored kicks connect after bounded approach "+i);
'''+needle
assert source.count(needle)==1;source=source.replace(needle,insert)
test.write_bytes(data[:3]+source.encode('utf8'))
subprocess.run(['python','-X','utf8','-B','tools/cf6-elder-assets/build.py','--import-approved'],cwd=ROOT,check=True)
subprocess.run(['python','-X','utf8','-B','tools/cf6-elder-assets/build.py','--check'],cwd=ROOT,check=True)
subprocess.run(['python','-X','utf8','-B','tools/cf6-elder-assets/balance.py'],cwd=ROOT,check=True)
jput(TMP/'r12-source-scope.json',{'scope':'Robot kick selection reach 150 to 190 pixels only; existing bounded approach and contact geometry retained. No damage, panel, resistance, target identity, animation timing or shared source changes.',
    'workersUnchanged':True,'fieldStatus':'R11 still running on frozen prior resources; R12 not executed',
    'aiSha256':sha(ai),'testSha256':sha(test)})
print('R12 main source prepared; worker resources untouched.')
