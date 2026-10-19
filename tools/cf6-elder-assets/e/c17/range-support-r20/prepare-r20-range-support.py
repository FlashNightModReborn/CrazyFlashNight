from pathlib import Path
import ast, datetime, hashlib, json, zipfile

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
analysis = json.loads((O / 'r19-pilot-awake-phase-aware-summary.json').read_text('utf8'))
assert len(analysis['rows']) == 12 and sum(r['won'] for r in analysis['rows']) == 2
assert hashlib.sha256((R / 'flashswf/arts/new/Codex老头素材.swf').read_bytes()).hexdigest() == 'aa84886bd82afa499f98a688de57e2517fa1719480e563fc464f6e7ecd3689c0'
changes = {}

def edit(path, old, new, count=1):
    if path not in changes: changes[path] = (R / path).read_text('utf-8-sig')
    assert changes[path].count(old) == count, (path, old, changes[path].count(old))
    changes[path] = changes[path].replace(old, new)

p = 'tools/cf6-elder-assets/build.py'
edit(p, "N = '{'+NS['x']+'}'", "N = '{'+NS['x']+'}'\nBEAM_ORIGINAL_WIDTH = 461.05\nBEAM_CONTACT_WIDTH = 600.0\nBEAM_ORIGINAL_LEFT = -230.5")
edit(p, "            action_durations[action]=len(frames)", """            if action in ('beam','heavyBeam'):
                length_scale=BEAM_CONTACT_WIDTH/BEAM_ORIGINAL_WIDTH
                for fr in frames:
                    for row in fr.values():
                        if row['id']==993:
                            m=row['matrix']
                            # Extend along the existing beam axis while preserving its authored muzzle end.
                            shift=BEAM_ORIGINAL_LEFT*(1-length_scale)
                            m[4]+=m[0]*shift;m[5]+=m[1]*shift
                            m[0]*=length_scale;m[1]*=length_scale
            action_durations[action]=len(frames)""")
edit(p, 'matrix=(461.05/25,0,0,32*a.get(\'beamThickness\',1)/25,m[4],m[5]);helper=H[\'Symbol 195\']',
        'matrix=(BEAM_CONTACT_WIDTH/25,0,0,32*a.get(\'beamThickness\',1)/25,m[4],m[5]);helper=H[\'Symbol 195\']')

p = 'tools/cf6-elder-assets/ElderAI.as'
edit(p, 'elderCombatStats={burstStarts:0,', 'elderCombatStats={decisionChecks:0,rangeOutsideChecks:0,burstStarts:0,')
edit(p, 'shootRange:elderForm=="human"?500:550', 'shootRange:elderForm=="human"?500:750')
edit(p, 'shieldAttackScale:35/43,meleeShieldCapacity:', 'shieldAttackScale:35/43,shieldCapacityScale:0.5,meleeShieldCapacity:')
edit(p, 'var capacity:Number=Math.min(state.baseHp*tune.reactiveCapacityLimit,remaining+amount);',
        'amount*=tune.shieldCapacityScale;\n    var capacity:Number=Math.min(state.baseHp*tune.reactiveCapacityLimit*tune.shieldCapacityScale,remaining+amount);')
edit(p, 'var capacity:Number=this.hp满血值*Math.min(this.elderTuning.beamShieldCapacityLimit,', 'var capacity:Number=this.hp满血值*this.elderTuning.shieldCapacityScale*Math.min(this.elderTuning.beamShieldCapacityLimit,')
edit(p, 'this.hp满血值*this.elderTuning.slamShieldCapacity,', 'this.hp满血值*this.elderTuning.slamShieldCapacity*this.elderTuning.shieldCapacityScale,')
edit(p, 'this.hp满血值*this.elderTuning.meleeShieldCapacity,', 'this.hp满血值*this.elderTuning.meleeShieldCapacity*this.elderTuning.shieldCapacityScale,')
edit(p, '    var tune:Object=this.elderTuning;\n    if(isNaN(dx)',
        '    var tune:Object=this.elderTuning;\n    if(this.elderForm=="robot"){\n        var stats:Object=this.elderCombatStats;stats.decisionChecks++;\n        if(dx>tune.shootRange)stats.rangeOutsideChecks++;\n    }\n    if(isNaN(dx)')
edit(p, '+" reactive="+stats.reactiveForced',
        '+" decisions="+stats.decisionChecks+"/"+stats.rangeOutsideChecks+" startRange="+this.elderTuning.shootRange+" shieldScale="+this.elderTuning.shieldCapacityScale\n        +" reactive="+stats.reactiveForced')

p = 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderAssetTest.as'
edit(p, 'bounds.xMax-bounds.xMin-461.05', 'bounds.xMax-bounds.xMin-600')
edit(p, '        check(r.elderChooseAttack(551,0,0)=="none","robot range bound");', '''        var rangeChecks:Number=r.elderCombatStats.decisionChecks,outsideChecks:Number=r.elderCombatStats.rangeOutsideChecks;
        check(r.elderChooseAttack(750,0,0)=="beam","robot includes the authorized 750 pixel start boundary");
        check(r.elderChooseAttack(751,0,0)=="none","robot range remains bounded beyond 750 pixels");
        check(r.elderCombatStats.decisionChecks==rangeChecks+2 && r.elderCombatStats.rangeOutsideChecks==outsideChecks+1,"range diagnostics count actual selector calls and the exceeded bound without changing selection");''')

p = 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderCombatEffectsTest.as'
edit(p, '        // Keep legacy exact-threshold fixtures', '        check(samples.kicks.actor.elderTuning.shieldCapacityScale==0.5,"all production grants use the halved capacity budget while retaining hardness");\n        // Keep legacy exact-threshold fixtures')
for old,new,count in [
    ('near(shield.getCapacity(),100)', 'near(shield.getCapacity(),50)',3),
    ('near(shield.getCapacity(),88)', 'near(shield.getCapacity(),38)',1),
    ('near(shield.getCapacity(),70)', 'near(shield.getCapacity(),20)',1),
    ('near(hard.getCapacity(),15)', 'near(hard.getCapacity(),7.5)',1),
    ('hard.absorbDamage(5,false,1)==0 && hard.absorbDamage(5,false,1)==0', 'hard.absorbDamage(2,false,1)==0 && hard.absorbDamage(2,false,1)==0',1),
    ('near(hard.getCapacity(),5)', 'near(hard.getCapacity(),3.5)',1),
    ('slamShieldAbsorbed-slamAbsorbedBefore,10)', 'slamShieldAbsorbed-slamAbsorbedBefore,4)',1),
    ('near(hard.getCapacity(),229.77)', 'near(hard.getCapacity(),114.885)',1),
    ('near(shield.getCapacity(),200)', 'near(shield.getCapacity(),100)',1),
    ('near(shield.getCapacity(),125)', 'near(shield.getCapacity(),25)',1),
    ('beamShieldUnused-unusedBefore,125)', 'beamShieldUnused-unusedBefore,25)',2),
    ('beamShieldUnused-unusedBefore,325)', 'beamShieldUnused-unusedBefore,125)',2),
    ('near(shield.getCapacity(),2000)', 'near(shield.getCapacity(),1000)',1),
    ('near(shield.getCapacity(),1200)', 'near(shield.getCapacity(),200)',1),
    ('beamCaps:Array=[600,4000/13,100,400000/10201,400000/10201]', 'beamCaps:Array=[300,2000/13,50,200000/10201,200000/10201]',1),
    ('layer.getCapacity()==20', 'layer.getCapacity()==10',1),
    ('getCapacity()==40 && actor.shield.getShieldCount()==2', 'getCapacity()==20 && actor.shield.getShieldCount()==2',1),
    ('getCapacity()==100,"a multi-threshold burst records every crossing but respects the ten-percent capacity ceiling"', 'getCapacity()==50,"a multi-threshold burst records every crossing but respects the halved five-percent capacity ceiling"',1),
    ('near(layer.getCapacity(),0.625/3)', 'near(layer.getCapacity(),0.625/6)',1),
    ('near(layer.getCapacity(),0.3125/3)', 'near(layer.getCapacity(),0.3125/6)',2),
    ('reactiveGranted-budgetGranted,6.25)', 'reactiveGranted-budgetGranted,3.125)',1),
    ('thirty actual periodic grants keep the unchanged total supplement budget', 'thirty actual periodic grants apply the halved total supplement budget',1),
    ('near(layer.getCapacity(),306.36)', 'near(layer.getCapacity(),153.18)',1),
]: edit(p, old, new, count)

p = 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6PlayerAimTest.as'
edit(p, '                continue;\n            }\n            for(var h:Number=0;', '''                for(heightIndex=0;heightIndex<heights.length;heightIndex++){
                    addCase(side,heights[heightIndex],750,"none",undefined,undefined,"beam");
                    addCase(side,heights[heightIndex],750,"none");
                    addCase(side,heights[heightIndex],750,"afterFirst");
                }
                addCase(side,175,820,"outside",undefined,undefined,"beam");
                addCase(side,175,820,"outside");
                continue;
            }
            for(var h:Number=0;''')
edit(p, 'dodge:String,lane:Number,origin:Number):Void', 'dodge:String,lane:Number,origin:Number,action:String):Void')
edit(p, 'lane:lane==undefined?0:lane,origin:origin==undefined?200:origin}',
        'lane:lane==undefined?0:lane,origin:origin==undefined?200:origin,action:action==undefined?"heavyBeam":action}')
edit(p, 'u.状态改变(stage==0?"空手攻击":stage==1?"激光束":"蓄能重束");',
        'u.状态改变(stage==0?"空手攻击":stage==1?"激光束":c.action=="beam"?"空手攻击":"蓄能重束");')
edit(p, '''                    var wantedHits:Number=c.dodge=="none"?4:1;
                    check(c.record.powers.join(",")=="50,100,150,200","actual four ramping declarations "+i);
                    check(c.record.hits==wantedHits,"standing or moving player receives expected contacts "+i+" got "+c.record.hits);
                    check(c.record.hitPowers.join(",")==(wantedHits==4?"50,100,150,200":"50"),"moving after first hit avoids stronger pulses "+i);''', '''                    var normal:Boolean=c.action=="beam";
                    var wantedHits:Number=c.dodge=="outside"?0:c.dodge=="none"?(normal?1:4):1;
                    var declared:String=normal?"300":"50,100,150,200";
                    var landed:String=wantedHits==0?"":normal?"300":wantedHits==4?declared:"50";
                    check(c.record.powers.join(",")==declared,"actual normal or four ramping declarations "+i);
                    check(c.record.hits==wantedHits,"standing, distant or moving player receives expected contacts "+i+" distance="+c.distance+" got "+c.record.hits);
                    check(c.record.hitPowers.join(",")==landed,"range edge and moving after first hit reject the expected pulses "+i);''')
p = 'scripts/run-cf6-player-aim-tests.ps1'
edit(p, '$caseCount=if($Baseline){32}else{74}', '$caseCount=if($Baseline){32}else{96}')
p = 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderRenderTest.as'
edit(p, 'matrix.tx=matrix.tx*1.2*sign+(point.side==0?300:800);matrix.ty=matrix.ty*1.2+330;', '''var beamFraming:Boolean=point.form==1 && (point.state=="空手攻击" || point.state=="蓄能重束");
        matrix.tx=matrix.tx*1.2*sign+(point.side==0?(beamFraming?200:300):(beamFraming?900:800));matrix.ty=matrix.ty*1.2+330;''')

p = 'tools/cf6-elder-assets/README.md'
if p not in changes: changes[p] = (R / p).read_text('utf8')
pos = changes[p].index('## 2026-10-17 跨纵深射击')
changes[p] = changes[p][:pos] + '''## 2026-10-18 R20 射程与护盾试验（施工中）

用户已授权机器人起手射程从 550 调到 750 像素并收紧护盾。普通束与重束的局部光束长度从 461.05 调到 600，沿原光束轴从既有枪口向外延长，画面与真实碰撞一起装配；默认 190 身高对应整数 108% 缩放。人形 500 射程、重束四段时刻及逐段倍率、锁定后不追踪保持现状。每侧三档玩家身高将分别核对 750 处的普通束、四段重束、首段后换线，以及 820 处的碰撞外侧。

各来源护盾容量统一乘 0.5；强度率、硬度上限、时限与衰减率的设置方式不变。连打实际容量为满血 5%，砸地为 0.75%；光束容量为上一段公式的一半。应激盾仍每累计损失初始满血 5% 强制生成，实际兑换 20% 所失生命，单层上限为初始满血 5%；每帧周期补充为缺失生命的 1/1920、最多初始满血的 1/9600，每 30 有效帧最多补初始满血 0.3125%。它不治疗 HP，也不撤销触发击已完成的吸血。伤害倍率、阶段／档次和公式分配不变。

诊断末行增加机器人普通选招调用数与其中超出当前射程的次数；组合衔接不走普通选招时不计入，计数不改写选择。该数据仅识别射程门的出现次数，不把终场距离当作全程因果。R20 尚待新鲜编译、原生回归、当前图像和独立斗兽；R19 十二场十负二胜、零超时全部保留，不能作为本版通过记录。

''' + changes[p][pos:]

paths = {row['path'] for row in json.loads((O / 'before-r19-output-distribution-index.json').read_text('utf8'))}
paths.update(changes)
index = []
with zipfile.ZipFile(O / 'before-r20-range-support.zip', 'x', zipfile.ZIP_DEFLATED) as z:
    for name in sorted(paths):
        data = (R / name).read_bytes();z.writestr(name,data)
        index.append({'path':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
with (O / 'before-r20-range-support-index.json').open('x',encoding='utf8') as f: json.dump(index,f,ensure_ascii=False,indent=2)
for name,value in changes.items():
    if name.endswith('.py'): ast.parse(value)
    before = (R / name).read_bytes()
    if b'\r\n' in before: value=value.replace('\n','\r\n')
    data=value.encode('utf8')
    if before.startswith(b'\xef\xbb\xbf') or name.endswith('.as'): data=b'\xef\xbb\xbf'+data
    (R / name).write_bytes(data)
for source,dest in [('build-r19-elder','build-r20-elder'),('finish-native-cleanup-after-r19-c5','finish-native-cleanup-after-r20')]:
    text=(O/(source+'.ps1')).read_text('utf-8-sig').replace('r19-c5','r20').replace('r19','r20').replace('R19','R20')
    with (O/(dest+'.ps1')).open('xb') as f: f.write(text.encode('utf-8-sig'))
plan=json.loads((O/'native-r19-c5-integration-plan.json').read_text('utf8'));plan['output']='native-r20-range-support'
plan['runs'].append({'name':'elder-render','runner':'scripts/run-cf6-elder-render-tests.ps1','args':['-Charge','-Capture','-TimeoutSeconds','900']})
with (O/'native-r20-range-support-plan.json').open('x',encoding='utf8') as f:json.dump(plan,f,ensure_ascii=False,indent=2)
with (O/'r20-authorized-changes.json').open('x',encoding='utf8') as f:
    json.dump({'recordedAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'authorization':'User accepted trial 750 robot start range and reduced shield sustain after visible/collision extension was explained.','changed':list(changes),'robotStartRange':750,'humanStartRange':500,'localBeamLength':600,'shieldCapacityScale':.5,'compiled':False},f,ensure_ascii=False,indent=2)
print(json.dumps({'changed':list(changes),'compiled':False,'playerCases':96,'capacityScale':.5}))
