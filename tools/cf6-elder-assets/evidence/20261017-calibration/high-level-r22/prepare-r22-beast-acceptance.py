from pathlib import Path
import datetime,hashlib,json,zipfile
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017'
load=lambda p:json.loads(p.read_text('utf-8-sig'))
readme=R/'tools/cf6-elder-assets/README.md'
sources=['tools/cf6-elder-assets/README.md','tools/cf6-elder-assets/analyze-arena.py',
         'tmp/cf6-combat-calibration-20261017/prepare-head-c5-full.py',
         'tmp/cf6-combat-calibration-20261017/verify-sealed-calibration.py']
with zipfile.ZipFile(O/'before-r22-beast-acceptance.zip','x',zipfile.ZIP_DEFLATED,compresslevel=9)as z:
    for name in sources:z.writestr(name,(R/name).read_bytes())
start=load(R/'tmp/arena-worker-experiments/cf6-cal-r22-full-20261018/execution-started.json')
scope={'profile':'high-level-beast-near-death-exusiai-net-hp-v1',
       'recordedAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
       'userInstructionAtUtc':'2026-10-18T08:59:56.063766Z',
       'userInstruction':'兽王这边需求可以简化成，至少把兽王的濒死状态逼出来，而不至于完整击败2形态即可，来简化调参难度。兽王的濒死形态出现后自身也会高速掉血，没有敌人供他吸血后就会自行死亡',
       'previousUserLevelScope':'目前瓶颈如何，如果实在困难就重点保60-100这个范围，低等级不考虑',
       'levels':[60,80,100],'experiment':'cf6-cal-r22-full-20261018',
       'alreadyStartedAtUtc':start['startedAt'],'frozenPlanHash':start['frozenPlanHash'],
       'originalFrozenPlanUnchanged':True,'battleConditionsUnchanged':True,
       'beastCriterion':'Every row must establish observed initial-form rage or an actual successor spawn beyond that threshold, then naturally lose without completing both forms. A successor spawn is reported as first-form defeat, not as observed rage if the rage callback is absent.',
       'exusiaiCriterion':'Each six-row group mean and median net HP loss is 50-80 percent; every row naturally loses.',
       'winsAllowed':0,'drawsAllowed':0,'timeoutsAllowed':0,
       'supersedesOnly':'Beast final-net-HP acceptance interval in the original preregistered purpose; historical metrics and original purpose remain intact.',
       'boundary':'This records a human-requested criterion change after execution started. It is not an assertion that the original criteria were met.'}
with(O/'r22-beast-acceptance-addendum.json').open('x',encoding='utf8')as f:json.dump(scope,f,ensure_ascii=False,indent=2)
text=readme.read_text('utf-8-sig')
before='新的完整矩阵采用 60／80／100 级、兽王与 EXUSIAI、双方各三次，共三十六场；每组平均和中位全链净削血均须为 50%–80%，每场均须自然落败，禁止胜局、平局和超时。'
after='新的完整矩阵采用 60／80／100 级、兽王与 EXUSIAI、双方各三次，共三十六场。维护者随后明确简化兽王目标：每场至少逼出一形态濒死狂暴，且不能完整击败两形态；实测一形态已死并生成二形态时记为已越过该进度，不冒称观察到狂暴回调。EXUSIAI 每组平均和中位全链净削血仍须为 50%–80%。两者均须自然落败，禁止胜局、平局和超时。兽王终场净削血保留为参考，不再作为通过门槛，也不全部归因于长老输出。'
assert text.count(before)==1
readme.write_text(text.replace(before,after),'utf8',newline='\n')
for name in ['prepare-head-c5-full.py','verify-sealed-calibration.py']:
    p=O/name;t=p.read_text('utf8')
    if name.startswith('prepare-'):
        assert t.count("elder = load(elder_base / 'phase-aware-summary.json')")==1
        t=t.replace("elder = load(elder_base / 'phase-aware-summary.json')","elder = load(elder_base / 'acceptance-summary.json')\nassert elder['profile'] == 'high-level-beast-near-death-exusiai-net-hp-v1'")
        t=t.replace("sha(elder_base / 'phase-aware-summary.json')","sha(elder_base / 'acceptance-summary.json')")
    else:
        assert t.count("analysis = load(P / entry['path'] / 'phase-aware-summary.json')")==1
        t=t.replace("analysis = load(P / entry['path'] / 'phase-aware-summary.json')","analysis = load(P / entry['path'] / 'acceptance-summary.json')\n        assert analysis['profile'] == 'high-level-beast-near-death-exusiai-net-hp-v1'")
    p.write_text(t,'utf8',newline='\n')
print(json.dumps({'levels':scope['levels'],'battleConditionsUnchanged':True,'originalFrozenPlanUnchanged':True,'profile':scope['profile']}))
