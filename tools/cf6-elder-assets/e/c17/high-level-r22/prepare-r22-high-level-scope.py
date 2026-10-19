"""Narrow current acceptance to the user-selected 60-100 range and reduce early periodic sustain."""
from pathlib import Path
import datetime,hashlib,json,zipfile
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';P=R/'tools/cf6-elder-assets/evidence/20261017-calibration'
load=lambda p:json.loads(p.read_text('utf-8-sig'))
sha=lambda b:hashlib.sha256(b).hexdigest()
analysis=load(P/'history/r21-pilot-awake/phase-aware-summary.json')
assert len(analysis['rows'])==12 and sum(r['won'] for r in analysis['rows'])==1
assert load(P/'history/r21-pilot-awake/display-assessment.json')['qualified']
for row in load(P/'history/r21-pilot-awake/plan/input-identity.json')['sourceBindings']:
    assert sha((R/row['path']).read_bytes())==row['sha256'],row['path']
changes={}
def edit(path,before,after,count=1):
    data=changes.get(path,(R/path).read_bytes());a=before.encode('utf8');b=after.encode('utf8')
    assert data.count(a)==count,(path,before,data.count(a),count)
    changes[path]=data.replace(a,b)

p='tools/cf6-elder-assets/ElderAI.as'
edit(p,'reactivePulseFrames:1,reactivePulseMissingRatio:0.003125/3,reactivePulseCapacityLimit:0.000625/3,reactiveDecayFrames:36,',
       'reactivePulseFrames:1,reactivePulseMissingRatio:0.000625/3,reactivePulseCapacityLimit:0.000625/3,reactiveDecayFrames:36,')
edit(p,'+" reactiveScale="+this.elderTuning.reactiveShieldCapacityScale',
       '+" reactiveScale="+this.elderTuning.reactiveShieldCapacityScale+" pulseMissingRatio="+(this.elderTuning.reactivePulseMissingRatio*this.elderTuning.reactiveShieldCapacityScale)')

p='scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderCombatEffectsTest.as'
edit(p,'0.625/4','0.625/20')
edit(p,'0.3125/4','0.3125/20',count=2)
edit(p,'periodic grants apply the independent reactive budget every active frame',
       'periodic grants scale with actual missing HP instead of saturating at twenty percent loss')
edit(p,'near(actor.elderCombatStats.reactiveGranted-budgetGranted,4.6875)',
       'near(actor.elderCombatStats.reactiveGranted-budgetGranted,0.9375)')
edit(p,'thirty actual periodic grants apply the independent reactive supplement budget',
       'thirty actual grants at twenty percent HP loss use one fifth of the maximum supplement budget')
anchor='        // Exercise the real post-damage event order: the trigger hit has already settled its leech.'
addition='''        var woundedHp:Array=[500,1],woundedCapacity:Array=[0.078125,0.15609375];
        for(var woundedIndex:Number=0;woundedIndex<woundedHp.length;woundedIndex++){
            actor.elderClearReactiveShield();actor.hp=woundedHp[woundedIndex];actor.hp满血值=1000;
            actor.elderClock=0;actor.elderUpdateReactiveShield();actor.elderClock=1;actor.elderUpdateReactiveShield();
            layer=actor.shield.getShieldById(actor.elderReactiveShield);
            check(near(layer.getCapacity(),woundedCapacity[woundedIndex]) && actor.hp==woundedHp[woundedIndex],
                "actual periodic grant increases with deeper wounds without healing HP "+woundedHp[woundedIndex]);
        }

        // Exercise the real post-damage event order: the trigger hit has already settled its leech.'''
edit(p,anchor,addition)

p='tools/cf6-elder-assets/arena-plan.js'
edit(p,'n<1||n>99','n<1||n>100')

readme='tools/cf6-elder-assets/README.md';data=(R/readme).read_bytes();assert b'R22' not in data
section='''
## 2026-10-18 R22 中高等级校准（施工中）

维护者已将本轮优先范围调整为 60–100 级，低等级不再作为达标条件。新的完整矩阵采用 60／80／100 级、兽王与 EXUSIAI、双方各三次，共三十六场；每组平均和中位全链净削血均须为 50%–80%，每场均须自然落败，禁止胜局、平局和超时。30 级历史结果保留原记录，不改写为通过，也不再为它补强。此前 30／60／99 矩阵属于原验收范围。

R21 十二场为 11 负、1 胜、0 平、0 超时。60 级兽王胜局中应激盾实际吸收约 1.08 万伤害；原周期补充在缺失 20% 初始生命时已封顶。R22 只把周期补充的缺失生命比例调低五倍：每个有效帧补充当前缺失生命的 1/6400，上限仍为初始满血的 1/6400；最大三十帧预算仍为初始满血的 0.46875%，但仅损血 20% 时实际三十帧预算为 0.09375%。这保留了随失血加深的补充，并限制尚有较多生命时的长局续航。

每累计损失 5% 初始满血的强制触发、30% 转换率、7.5% 本层容量上限、36 帧无刷新衰减、各层盾强、R21 攻击面板与招式、750 射程和图形／碰撞均保持。专项原生检查后直接执行本轮三十六场完整矩阵；后续音频、玩家瞄准、当前图像和大头完整矩阵分别核对，不能拿旧执行身份代替本轮验收。
'''
pos=data.find(b'\n## ',data.index(b'## 2026-10-18 R21 ')+10);assert pos>0
changes[readme]=data[:pos]+section.encode('utf8')+data[pos:]

paths={r['path']for r in load(O/'before-r21-shield-allocation-index.json')}
paths.update(row['path']for row in load(P/'history/r21-pilot-awake/plan/input-identity.json')['sourceBindings'])
paths.update(changes)
paths.update(['tools/cf6-elder-assets/arena-plan.js','tools/cf6-elder-assets/analyze-arena.py',
              'tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts','.gitattributes'])
index=[]
with zipfile.ZipFile(O/'before-r22-high-level-budget.zip','x',zipfile.ZIP_DEFLATED,compresslevel=9)as z:
    for name in sorted(paths):
        original=(R/name).read_bytes();z.writestr(name,original)
        index.append({'path':name,'bytes':len(original),'sha256':sha(original)})
with(O/'before-r22-high-level-budget-index.json').open('x',encoding='utf8')as f:json.dump(index,f,ensure_ascii=False,indent=2)
for name,data in changes.items():
    if name.endswith('.as'):assert data.startswith(b'\xef\xbb\xbf') and (R/name).read_bytes().startswith(b'\xef\xbb\xbf')
    (R/name).write_bytes(data)
with(O/'r22-authorized-changes.json').open('x',encoding='utf8')as f:
    json.dump({'recordedAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'userScope':'目前瓶颈如何，如果实在困难就重点保60-100这个范围，低等级不考虑',
               'acceptedLevels':[60,80,100],'lowLevelAcceptanceRequired':False,'fullMatrixRows':36,
               'sourceChanges':list(changes),'onlyCombatParameterChanged':'reactivePulseMissingRatio:0.003125/3 -> 0.000625/3',
               'actualPeriodicMissingHpRatio':1/6400,'periodicMaximumInitialHpRatio':1/6400,
               'forcedConversionUnchanged':.3,'rangeDamagePanelsAndGeometryUnchanged':True,
               'compiled':False,'nativeQualificationPending':True,'fullMatrixExecuted':False},f,ensure_ascii=False,indent=2)
print(json.dumps({'changed':list(changes),'preservedBeforeFiles':len(index),'levels':[60,80,100],'compiled':False},ensure_ascii=False))
