from pathlib import Path
import json
P=Path('tmp/cf6-combat-audio-20261017')
head='flashswf/arts/new/Codex大头机器人素材.swf';elder='flashswf/arts/new/Codex老头素材.swf';blade='flashswf/arts/new/Codex大刀机器人素材.swf'
newLibs=['Codex大头机器人素材','Codex老头素材','Codex大刀机器人素材','Codex蛮蛮素材','CodexWings素材','Codex特种兵素材','Codex光头保安素材','Antigravity专用素材']
tests=[]
def case(folder,kind,patterns,consumers):tests.append({'folder':folder,'kind':kind,'patterns':patterns,'executedConsumers':consumers})
case('head-final-pass1/headbot-asset','behavior',[r'^Cf6HeadbotAssetTest: (\d+) passed, 0 failed;',r'^Cf6RobotCombatTest headbot: (\d+) passed, 0 failed;'],[head])
case('native-tests-pass2/elder-asset','behavior',[r'^Cf6ElderAssetTest: (\d+) passed, 0 failed;',r'^Cf6RobotCombatTest elder: (\d+) passed, 0 failed;',r'^Cf6ElderCombatEffectsTest: (\d+) passed, 0 failed'],[elder])
case('blade-final-pass1/bladebot-asset','behavior',[r'^Cf6BladebotAssetTest: (\d+) passed, 0 failed;',r'^Cf6RobotCombatTest bladebot: (\d+) passed, 0 failed;'],[blade])
case('aim-final/player-aim','behavior',[r'^Cf6PlayerAimTest: (\d+) passed, 0 failed; 62 player-source cases; baseline=false'],[elder,blade])
case('blade-final-pass1/audio','behavior',[r'^Cf6AudioTest: (\d+) passed, 0 failed; 78 actual sound routes; libraries=8'],['flashswf/arts/new/'+n+'.swf' for n in newLibs])
case('legacy-audio-pass1/legacy','behavior',[r'^Cf6AudioTest: (\d+) passed, 0 failed; 6 actual sound routes; libraries=3'],['flashswf/arts/new/素材库-诺亚新敌人.swf','flashswf/arts/new/Codex专用素材.swf'])
for folder,swf in [('head-final-pass1/headbot-render',head),('death-render-pass2/elder',elder),('blade-final-pass1/bladebot-render',blade)]:
    case(folder,'render',[r'^Cf6RobotDeathRenderTest: (\d+) passed, 0 failed; 8 draw points'],[swf])
builds=[]
for family,folder,swf in [('headbot','build-pass4/headbot',head),('elder','build-pass2/elder',elder),('bladebot','build-pass5/bladebot',blade),
    ('manman','build-pass1/manman','flashswf/arts/new/Codex蛮蛮素材.swf'),('wings','build-pass3/wings','flashswf/arts/new/CodexWings素材.swf'),
    ('soldier','build-pass3/soldier','flashswf/arts/new/Codex特种兵素材.swf'),('guard','build-pass3/guard','flashswf/arts/new/Codex光头保安素材.swf'),
    ('zombie','build-pass1/zombie','flashswf/arts/new/Antigravity专用素材.swf')]:builds.append({'family':family,'folder':folder,'consumer':swf})
arenas=[]
for family,n in [('headbot',18),('bladebot',24),('elder',36),('headbot-final',6)]:
    arenas.append({'label':'arena/'+family,'experimentId':'cf6-'+family+'-combat-audio-20261017','planFolder':'arena-'+family,'expectedRows':n,
        'versionScope':'before final fragment rendering correction; behavior DoAction bodies equal to final, but not final image qualification' if family=='headbot' else 'final published consumer version'})
data={'nativeRuns':tests,'builds':builds,'arenaRuns':arenas,'cleanup':'native-cleanup.json',
    'finalImages':{'headbot':'final-images-head-fixed','elder':'final-images/elder','bladebot':'final-images-blade-fixed'},
    'visualReview':'image-review.json','audioAudit':'audio-audit-final3/audit.json','arenaSummary':'arena-summary.json'}
with (P/'delivery-inputs.json').open('x',encoding='utf8') as f:json.dump(data,f,ensure_ascii=False,indent=2);f.write('\n')
print(json.dumps({'nativeRuns':len(tests),'builds':len(builds),'arenaRows':sum(r['expectedRows'] for r in arenas)}))
