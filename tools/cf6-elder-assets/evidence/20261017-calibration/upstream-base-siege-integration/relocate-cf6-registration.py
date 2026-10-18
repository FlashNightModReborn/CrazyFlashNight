from pathlib import Path
import hashlib, json, subprocess, zipfile

R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';F=O/'upstream-base-siege-integration'
assert subprocess.check_output(['git','rev-parse','HEAD']).decode().strip()=='937e1815465a5c1c01376b1a947787c0e1b9de8f'
units=json.loads((R/'data/units/units.json').read_text('utf-8-sig'))
assert all(v['id'] not in [472,473,474] for v in units)
changes={}
def edit(path,old,new):
    if path not in changes:changes[path]=(R/path).read_text('utf-8-sig')
    assert changes[path].count(old)==1,(path,old,changes[path].count(old))
    changes[path]=changes[path].replace(old,new)
edit('tools/cf6-headbot-assets/balance.py',"LINK, UNIT_ID = '敌人-CF6大头机器人', 470","LINK, UNIT_ID = '敌人-CF6大头机器人', 472")
edit('tools/cf6-headbot-assets/arena-plan.js','type:"兵种470"','type:"兵种472"')
edit('tools/cf6-headbot-assets/arena-plan.js','candidateUnitId:470,','candidateUnitId:472,')
edit('tools/cf6-elder-assets/balance.py',"CONFIG={'human':{'id':471,","CONFIG={'human':{'id':473,")
edit('tools/cf6-elder-assets/balance.py',"'robot':{'id':472,","'robot':{'id':474,")
edit('tools/cf6-elder-assets/arena-plan.js','type:"兵种471"','type:"兵种473"')
edit('tools/cf6-elder-assets/arena-plan.js','candidateUnitId:471,','candidateUnitId:473,')
edit('tools/cf6-elder-assets/arena-plan.js','successorUnitId:472,','successorUnitId:474,')
edit('tools/cf6-elder-assets/analyze-arena.py',
     "        assert context['candidateUnitId'] == 471 and context['rivalUnitId'] in (78, 361)",
     "        candidate_id = context['candidateUnitId']\n        # Historical frozen rows retain their original registrations; this is not a runtime alias.\n        assert candidate_id in (471, 473) and context['rivalUnitId'] in (78, 361)\n        assert context['successorUnitId'] == (472 if candidate_id == 471 else 474)")
edit('tools/cf6-elder-assets/analyze-arena.py',"own_spawns[0]['from'] == '兵种471'","own_spawns[0]['from'] == '兵种' + str(candidate_id)")
edit('tools/cf6-elder-assets/analyze-arena.py',"            'runId': raw_row['runId'], 'rival': rival, 'level': level, 'side': side,",
     "            'runId': raw_row['runId'], 'rival': rival, 'level': level, 'side': side,\n            'candidateUnitId': candidate_id, 'successorUnitId': context['successorUnitId'],")
edit('tools/cf6-headbot-assets/README.md','兵种 `470`，显示名','兵种 `472`，显示名')
edit('tools/cf6-headbot-assets/README.md','老头 R18 准备期间，这十三项大头输入均保持不变。',
     '老头 R18 准备期间，这十三项大头输入均保持不变。合并主线场景提交后，已发布的 470／471 为主线同伴，本轮尚未提交的大头、老头人形、老头机器人改用空闲的 472／473／474。此前大头十八场和 C4 六场仍保留原 470 编号；新编号与整合后的公共加载器将重新完成十八场验证，当前尚未把旧轮次作为该组合的完整通过记录。')
edit('tools/cf6-elder-assets/README.md','- 人形注册：兵种 471，','- 人形注册：兵种 473，')
edit('tools/cf6-elder-assets/README.md','- 机器人注册：兵种 472，','- 机器人注册：兵种 474，')
edit('tools/cf6-elder-assets/README.md','- 两者从同一 `Codex老头素材`',
     '- 合并上游主线场景时发现 470／471 已用于主线同伴，因此尚未提交的三角色注册统一迁到 472／473／474；此前老头 471／472 的冻结证据保留原身份，不作为运行时别名。\n- 两者从同一 `Codex老头素材`')
edit('tools/cf6-audio/README.md','核查包括兵种 461–472 的十二个目录身份，',
     '当前核查范围为兵种 461–469 与 472–474 的十二个目录身份；大头及老头两形态为避让上游主线同伴，由尚未提交的 470–472 迁至 472–474，历史证据保留原编号。另包括')
paths=set(changes)|{'data/units/units.json','launcher/web/modules/arena-unit-catalog.js','tools/cf6-headbot-assets/balance-inputs.json','tools/cf6-elder-assets/balance-inputs.json','data/enemy_properties/CF6重制敌人.xml'}
index=[]
with zipfile.ZipFile(F/'before-registration.zip','x',zipfile.ZIP_DEFLATED) as z:
    for name in sorted(paths):
        data=(R/name).read_bytes();z.writestr(name,data);index.append({'path':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
with (F/'before-registration-index.json').open('x',encoding='utf8') as f:json.dump(index,f,ensure_ascii=False,indent=2)
for name,text in changes.items():
    previous=(R/name).read_bytes();data=text.encode('utf8')
    if previous.startswith(b'\xef\xbb\xbf'):data=b'\xef\xbb\xbf'+data
    (R/name).write_bytes(data)
with (F/'registration-source-changes.json').open('x',encoding='utf8') as f:
    json.dump({'pendingCf6IdsBefore':[470,471,472],'currentCf6Ids':[472,473,474],'publishedCompanionsPreserved':[470,471],'changedSources':list(changes),'historicalEvidenceRewritten':False,'generatedOutputsPending':True},f,ensure_ascii=False,indent=2)
print(json.dumps({'changedSources':len(changes),'registration':[472,473,474],'historicalEvidenceRewritten':False}))
